defmodule GridMaster.Room do
  @moduledoc """
  房間 GenServer：大廳座位／準備狀態、聊天快取（50 則）、斷線計時、
  包裹純函數引擎並廣播狀態。所有事件進 Mailbox 序列化，天生無併發衝突。

  生命週期：`:lobby` → `:in_game` → `:game_over` → `:lobby`（PRD §3.1）。
  斷線規則：大廳中已入座者離線超過 `seat_timeout`（預設 120 秒）自動離座；
  遊戲中斷線保留座位等重連。
  """

  use GenServer, restart: :transient

  alias GridMaster.Engine
  alias GridMaster.Engine.View
  alias GridMaster.Npc

  @max_seats 6
  @chat_limit 50
  @default_seat_timeout :timer.seconds(120)
  # NPC 出手延遲（毫秒區間）：擬人節奏，測試可縮短
  @default_npc_delay {900, 1800}

  defstruct id: nil,
            status: :lobby,
            users: %{},
            seats: [],
            chat: [],
            engine: nil,
            result: nil,
            connections: %{},
            monitors: %{},
            timers: %{},
            seat_timeout: @default_seat_timeout,
            npc_timer: nil,
            npc_delay: @default_npc_delay

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :id)))
  end

  def via(id), do: {:via, Registry, {GridMaster.RoomRegistry, id}}

  @doc "加入房間（channel 連上時呼叫），回傳完整快照。"
  def join(room, user, channel_pid), do: GenServer.call(room, {:join, user, channel_pid})

  @doc "大廳操作：:seat_take | :seat_leave | :ready | :unready | :game_start | :back_to_lobby"
  def lobby_op(room, op, user_id), do: GenServer.call(room, {:lobby_op, op, user_id})

  def chat(room, user_id, text), do: GenServer.call(room, {:chat, user_id, text})

  def game_action(room, user_id, type, payload),
    do: GenServer.call(room, {:game_action, user_id, type, payload})

  def admin_abort(room, user_id), do: GenServer.call(room, {:admin_abort, user_id})

  def snapshot(room), do: GenServer.call(room, :snapshot)

  # ── Server ──────────────────────────────────────────────────

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       id: Keyword.fetch!(opts, :id),
       seat_timeout: Keyword.get(opts, :seat_timeout, @default_seat_timeout),
       npc_delay: Keyword.get(opts, :npc_delay, @default_npc_delay)
     }}
  end

  @impl true
  def handle_call({:join, user, channel_pid}, _from, s) do
    s = migrate_identity(s, user)
    ref = Process.monitor(channel_pid)
    avatar = Map.get(user, :avatar)

    s = %{
      s
      | monitors: Map.put(s.monitors, ref, user.id),
        connections: Map.update(s.connections, user.id, 1, &(&1 + 1)),
        users:
          Map.update(
            s.users,
            user.id,
            %{name: user.name, role: user.role, avatar: avatar, ready: false},
            &Map.merge(&1, %{name: user.name, role: user.role, avatar: avatar})
          )
    }

    s = cancel_timer(s, user.id)
    {:reply, snapshot_view(s), broadcast_sync(s)}
  end

  def handle_call(:snapshot, _from, s), do: {:reply, snapshot_view(s), s}

  def handle_call({:lobby_op, op, user_id}, _from, s) do
    case do_lobby_op(op, user_id, s) do
      {:ok, s, messages} ->
        s = Enum.reduce(messages, s, &sysmsg(&2, &1))
        {:reply, :ok, s |> broadcast_sync() |> schedule_npc()}

      {:error, reason} ->
        {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:chat, user_id, text}, _from, s) do
    user = s.users[user_id]
    text = if is_binary(text), do: String.trim(text), else: ""

    if user != nil and text != "" and String.length(text) <= 300 do
      {:reply, :ok, push_chat(s, %{kind: "chat", from: user_id, name: user.name, text: text})}
    else
      {:reply, {:error, :invalid_message}, s}
    end
  end

  def handle_call({:game_action, user_id, type, payload}, _from, s) do
    if s.status != :in_game do
      {:reply, {:error, :not_in_game}, s}
    else
      case Engine.apply_action(s.engine, user_id, {type, payload}) do
        {:ok, engine, events} ->
          s = %{s | engine: engine} |> broadcast_events(events) |> maybe_finish()
          {:reply, :ok, s |> broadcast_sync() |> schedule_npc()}

        {:error, reason} ->
          {:reply, {:error, reason}, s}
      end
    end
  end

  # 結束遊戲權限（2026-07-12 下放）：管理員之外，本局入座玩家也可結束——
  # 單人配 NPC 遊玩時才有辦法自行收局。
  def handle_call({:admin_abort, user_id}, _from, s) do
    cond do
      match?(%{role: "admin"}, s.users[user_id]) ->
        s = s |> reset_to_lobby() |> sysmsg("管理員強制結束了遊戲，回到大廳") |> broadcast_sync()
        {:reply, :ok, s}

      s.status != :lobby and user_id in s.seats ->
        s = s |> reset_to_lobby() |> sysmsg("#{name(s, user_id)} 結束了遊戲，回到大廳") |> broadcast_sync()
        {:reply, :ok, s}

      true ->
        {:reply, {:error, :forbidden}, s}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, s) do
    case Map.pop(s.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, s}

      {user_id, monitors} ->
        count = max(Map.get(s.connections, user_id, 1) - 1, 0)
        s = %{s | monitors: monitors, connections: Map.put(s.connections, user_id, count)}
        s = if count == 0, do: handle_offline(s, user_id), else: s
        {:noreply, broadcast_sync(s)}
    end
  end

  def handle_info(:npc_tick, s) do
    s = %{s | npc_timer: nil}

    with :in_game <- s.status,
         npc when npc != nil <- Npc.pending(s.engine, npc_ids(s)) do
      {:noreply, npc_act(s, npc)}
    else
      _not_npc_turn -> {:noreply, s}
    end
  end

  def handle_info({:seat_timeout, user_id}, s) do
    s = %{s | timers: Map.delete(s.timers, user_id)}
    offline? = Map.get(s.connections, user_id, 0) == 0

    if offline? and s.status == :lobby and user_id in s.seats do
      display = name(s, user_id)

      s =
        s
        |> unseat(user_id)
        |> prune_user(user_id)
        |> sysmsg("#{display} 離線逾時，已自動離座")
        |> broadcast_sync()

      {:noreply, s}
    else
      {:noreply, s}
    end
  end

  # ── 大廳操作 ────────────────────────────────────────────────

  defp do_lobby_op(:seat_take, user_id, s) do
    cond do
      s.status != :lobby -> {:error, :not_in_lobby}
      s.users[user_id] == nil -> {:error, :unknown_user}
      # 產品規則（2026-07-12 定案）：訪客只能旁觀與聊天，入座需 Discord 登入
      s.users[user_id].role == "guest" -> {:error, :login_required}
      user_id in s.seats -> {:error, :already_seated}
      length(s.seats) >= @max_seats -> {:error, :room_full}
      true -> {:ok, %{s | seats: s.seats ++ [user_id]}, ["#{name(s, user_id)} 入座"]}
    end
  end

  defp do_lobby_op(:npc_add, user_id, s) do
    cond do
      s.status != :lobby ->
        {:error, :not_in_lobby}

      s.users[user_id] == nil ->
        {:error, :unknown_user}

      # NPC 操作與入座同門檻：登入使用者限定
      s.users[user_id].role == "guest" ->
        {:error, :login_required}

      length(s.seats) >= @max_seats ->
        {:error, :room_full}

      true ->
        n = Enum.find(1..@max_seats, &(Npc.id(&1) not in s.seats))
        npc_id = Npc.id(n)

        users =
          Map.put(s.users, npc_id, %{
            name: Npc.display_name(n),
            role: "npc",
            avatar: nil,
            ready: true
          })

        {:ok, %{s | users: users, seats: s.seats ++ [npc_id]},
         ["#{Npc.display_name(n)} 加入了牌局"]}
    end
  end

  defp do_lobby_op(:npc_remove, user_id, s) do
    npc_id = s.seats |> Enum.filter(&Npc.npc?/1) |> List.last()

    cond do
      s.status != :lobby -> {:error, :not_in_lobby}
      s.users[user_id] == nil -> {:error, :unknown_user}
      s.users[user_id].role == "guest" -> {:error, :login_required}
      npc_id == nil -> {:error, :no_npc}
      true -> {:ok, s |> unseat(npc_id) |> prune_user(npc_id), ["#{name(s, npc_id)} 已移除"]}
    end
  end

  defp do_lobby_op(:seat_leave, user_id, s) do
    cond do
      s.status != :lobby -> {:error, :not_in_lobby}
      user_id not in s.seats -> {:error, :not_seated}
      true -> {:ok, unseat(s, user_id), ["#{name(s, user_id)} 離座"]}
    end
  end

  defp do_lobby_op(:ready, user_id, s), do: set_ready(s, user_id, true)
  defp do_lobby_op(:unready, user_id, s), do: set_ready(s, user_id, false)

  defp do_lobby_op(:game_start, user_id, s) do
    cond do
      s.status != :lobby ->
        {:error, :not_in_lobby}

      user_id not in s.seats ->
        {:error, :not_seated}

      length(s.seats) < 2 ->
        {:error, :not_enough_players}

      not Enum.all?(s.seats, &s.users[&1].ready) ->
        {:error, :not_all_ready}

      true ->
        seed =
          {:rand.uniform(2_000_000_000), :rand.uniform(2_000_000_000),
           :rand.uniform(2_000_000_000)}

        {engine, events} = Engine.new(s.seats, seed: seed)
        s = %{s | status: :in_game, engine: engine, result: nil}
        {:ok, broadcast_events(s, events), ["遊戲開始！"]}
    end
  end

  defp do_lobby_op(:back_to_lobby, user_id, s) do
    cond do
      s.status != :game_over -> {:error, :not_game_over}
      s.users[user_id] == nil -> {:error, :unknown_user}
      true -> {:ok, reset_to_lobby(s), ["回到大廳"]}
    end
  end

  defp set_ready(s, user_id, ready?) do
    cond do
      s.status != :lobby ->
        {:error, :not_in_lobby}

      user_id not in s.seats ->
        {:error, :not_seated}

      true ->
        users = Map.update!(s.users, user_id, &%{&1 | ready: ready?})
        {:ok, %{s | users: users}, []}
    end
  end

  # ── NPC 驅動 ────────────────────────────────────────────────

  defp npc_ids(s), do: Enum.filter(s.seats, &Npc.npc?/1)

  # 遊戲中且輪到 NPC → 排一次延遲出手（已排過就不重複）
  defp schedule_npc(%{status: :in_game, npc_timer: nil} = s) do
    npcs = npc_ids(s)

    if npcs != [] and Npc.pending(s.engine, npcs) != nil do
      {min_delay, max_delay} = s.npc_delay
      ref = Process.send_after(self(), :npc_tick, Enum.random(min_delay..max_delay))
      %{s | npc_timer: ref}
    else
      s
    end
  end

  defp schedule_npc(s), do: s

  defp npc_act(s, npc) do
    case try_npc_candidates(s.engine, npc, Npc.candidates(s.engine, npc)) do
      {:ok, engine, events} ->
        %{s | engine: engine}
        |> broadcast_events(events)
        |> maybe_finish()
        |> broadcast_sync()
        |> schedule_npc()

      :error ->
        # 理論上到不了（候選清單以必成動作收尾）；保守停手避免空轉
        s |> sysmsg("#{name(s, npc)} 卡住了，請結束遊戲重開") |> broadcast_sync()
    end
  end

  defp try_npc_candidates(_engine, _npc, []), do: :error

  defp try_npc_candidates(engine, npc, [{type, payload} | rest]) do
    case Engine.apply_action(engine, npc, {type, payload}) do
      {:ok, _engine, _events} = ok -> ok
      {:error, _reason} -> try_npc_candidates(engine, npc, rest)
    end
  end

  # ── 內部輔助 ────────────────────────────────────────────────

  # 訪客登入 Discord 後身份合併：座位與準備狀態轉移給新身份，移除舊訪客殘影。
  # 牌局進行中不合併（引擎玩家以舊 id 註冊，中途改名會破壞對應）。
  defp migrate_identity(s, %{id: new_id} = user) do
    old_id = Map.get(user, :alias_of)

    cond do
      old_id in [nil, new_id] ->
        s

      not Map.has_key?(s.users, old_id) ->
        s

      s.status == :in_game and old_id in s.seats ->
        s

      true ->
        old_user = s.users[old_id]
        was_seated = old_id in s.seats

        seats =
          s.seats
          |> Enum.map(&if(&1 == old_id, do: new_id, else: &1))
          |> Enum.uniq()

        users =
          s.users
          |> Map.delete(old_id)
          |> Map.put_new(new_id, %{
            name: user.name,
            role: user.role,
            avatar: Map.get(user, :avatar),
            ready: old_user.ready
          })

        s = cancel_timer(s, old_id)

        s = %{
          s
          | seats: seats,
            users: users,
            connections: Map.delete(s.connections, old_id)
        }

        if was_seated do
          sysmsg(s, "#{old_user.name} 已登入為 #{user.name}，座位保留")
        else
          s
        end
    end
  end

  defp handle_offline(s, user_id) do
    cond do
      s.status == :lobby and user_id in s.seats ->
        s |> start_timer(user_id) |> sysmsg("#{name(s, user_id)} 已離線")

      user_id in s.seats ->
        sysmsg(s, "#{name(s, user_id)} 已離線，座位保留中")

      true ->
        prune_user(s, user_id)
    end
  end

  defp maybe_finish(%{engine: %{phase: :finished}} = s) do
    result = s.engine.winner

    %{s | status: :game_over, result: result}
    |> sysmsg("遊戲結束，#{name(s, result.winner)} 獲勝！")
  end

  defp maybe_finish(s), do: s

  defp reset_to_lobby(s) do
    # NPC 永遠準備好；真人重置為未準備
    users = Map.new(s.users, fn {id, u} -> {id, %{u | ready: u.role == "npc"}} end)
    if s.npc_timer, do: Process.cancel_timer(s.npc_timer)
    s = %{s | status: :lobby, engine: nil, result: nil, users: users, npc_timer: nil}

    # 回到大廳時，離線中的入座者開始計時
    Enum.reduce(s.seats, s, fn id, acc ->
      if Map.get(acc.connections, id, 0) == 0, do: start_timer(acc, id), else: acc
    end)
  end

  defp unseat(s, user_id) do
    users =
      case s.users[user_id] do
        nil -> s.users
        user -> Map.put(s.users, user_id, %{user | ready: false})
      end

    %{s | seats: List.delete(s.seats, user_id), users: users}
  end

  defp prune_user(s, user_id) do
    if user_id in s.seats or Map.get(s.connections, user_id, 0) > 0 do
      s
    else
      %{
        s
        | users: Map.delete(s.users, user_id),
          connections: Map.delete(s.connections, user_id)
      }
    end
  end

  defp start_timer(s, user_id) do
    s = cancel_timer(s, user_id)
    ref = Process.send_after(self(), {:seat_timeout, user_id}, s.seat_timeout)
    %{s | timers: Map.put(s.timers, user_id, ref)}
  end

  defp cancel_timer(s, user_id) do
    case Map.pop(s.timers, user_id) do
      {nil, _timers} ->
        s

      {ref, timers} ->
        Process.cancel_timer(ref)
        %{s | timers: timers}
    end
  end

  defp name(s, user_id) do
    case s.users[user_id] do
      %{name: name} -> name
      nil -> "？"
    end
  end

  # ── 視圖與廣播 ──────────────────────────────────────────────

  defp room_view(s) do
    %{
      id: s.id,
      status: s.status,
      seats: s.seats,
      users:
        Map.new(s.users, fn {id, u} ->
          {id,
           %{
             name: u.name,
             role: u.role,
             avatar: Map.get(u, :avatar),
             ready: u.ready,
             online: u.role == "npc" or Map.get(s.connections, id, 0) > 0,
             seated: id in s.seats
           }}
        end),
      game: s.engine && View.render(s.engine),
      result: s.result
    }
  end

  defp snapshot_view(s), do: Map.put(room_view(s), :chat, Enum.reverse(s.chat))

  defp broadcast_sync(s) do
    GridMasterWeb.Endpoint.broadcast("room:" <> s.id, "room_sync", room_view(s))
    s
  end

  defp broadcast_events(s, events) do
    GridMasterWeb.Endpoint.broadcast("room:" <> s.id, "game_events", %{
      events: Enum.map(events, fn {type, payload} -> Map.put(payload, :type, type) end)
    })

    s
  end

  defp push_chat(s, message) do
    message =
      Map.merge(message, %{
        id: System.unique_integer([:positive, :monotonic]),
        at: DateTime.to_iso8601(DateTime.utc_now())
      })

    s = %{s | chat: Enum.take([message | s.chat], @chat_limit)}
    GridMasterWeb.Endpoint.broadcast("room:" <> s.id, "chat_new", message)
    s
  end

  defp sysmsg(s, text), do: push_chat(s, %{kind: "sys", from: nil, name: nil, text: text})
end
