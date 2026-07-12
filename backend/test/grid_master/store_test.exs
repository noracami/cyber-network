defmodule GridMaster.StoreTest do
  @moduledoc """
  R1 持久化測試：快照 round-trip（重啟續局）、版本防護、空房清理、
  games 對局表生命週期、動作日誌連號與重播不變量。

  async: false → DataCase 給 shared sandbox，Room 進程可直接用測試的
  DB 連線。真人回合以 NPC 候選策略代打（與 npc_test 同模式）。
  """

  use GridMaster.DataCase, async: false

  alias GridMaster.{Npc, Replay, Room, Store}
  alias GridMaster.Store.{Game, GameAction, RoomSnapshot}

  defp start_room(id, opts \\ []) do
    opts = Keyword.merge([id: id, store: Store, npc_delay: {1, 2}], opts)
    start_supervised!({Room, opts}, id: make_ref())
  end

  defp fresh_id, do: "st#{System.unique_integer([:positive])}"

  defp user(id, role \\ "discord"), do: %{id: id, name: id, role: role}

  defp begin_game(room) do
    Room.join(room, user("a"), self())
    :ok = Room.lobby_op(room, :seat_take, "a")
    :ok = Room.lobby_op(room, :npc_add, "a")
    :ok = Room.lobby_op(room, :ready, "a")
    :ok = Room.lobby_op(room, :game_start, "a")
  end

  # 推進 n 拍：真人回合代打一手，NPC 回合等 tick
  defp drive_room(_room, _human, 0), do: :ok

  defp drive_room(room, human, n) do
    s = :sys.get_state(room)

    cond do
      s.engine == nil or s.engine.phase == :finished ->
        :ok

      Npc.pending(s.engine, [human]) == human ->
        play_first(room, human, Npc.candidates(s.engine, human))
        drive_room(room, human, n - 1)

      true ->
        Process.sleep(5)
        drive_room(room, human, n - 1)
    end
  end

  defp play_first(_room, _human, []), do: :ok

  defp play_first(room, human, [{type, payload} | rest]) do
    case Room.game_action(room, human, type, payload) do
      :ok -> :ok
      {:error, _reason} -> play_first(room, human, rest)
    end
  end

  # 等到輪到真人（NPC 不會再出手）再取狀態，狀態比較才不會被 tick 打擾
  defp settle_on_human(room, human, tries \\ 400) do
    s = :sys.get_state(room)

    cond do
      s.engine != nil and s.engine.phase != :finished and
          Npc.pending(s.engine, [human]) == human ->
        s

      tries == 0 ->
        flunk("等不到真人回合")

      true ->
        Process.sleep(5)
        settle_on_human(room, human, tries - 1)
    end
  end

  defp wait_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("條件逾時未成立")
      true -> Process.sleep(5) && wait_until(fun, tries - 1)
    end
  end

  defp stop_existing_room(id) do
    case Registry.lookup(GridMaster.RoomRegistry, id) do
      [{pid, _value}] -> GenServer.stop(pid)
      [] -> :ok
    end
  end

  test "快照 round-trip：重啟後牌局原地繼續且可續玩" do
    id = fresh_id()
    room = start_room(id)
    begin_game(room)
    drive_room(room, "a", 30)

    before = settle_on_human(room, "a")
    assert %RoomSnapshot{version: _} = Repo.get(RoomSnapshot, id)

    :ok = GenServer.stop(room)
    room2 = start_room(id)
    restored = :sys.get_state(room2)

    assert restored.status == :in_game
    assert restored.seats == before.seats
    assert restored.game_id == before.game_id
    assert restored.action_seq == before.action_seq
    # 引擎逐欄一致（rng 匯出成純資料比較、static 打包時本就拆掉）
    assert Store.pack_engine(restored.engine) == Store.pack_engine(before.engine)
    # static 已重建
    assert restored.engine.static != nil

    # 還原後可以繼續行動（此刻輪到真人，代打一手要成功入日誌）
    play_first(room2, "a", Npc.candidates(restored.engine, "a"))
    assert :sys.get_state(room2).action_seq == before.action_seq + 1
  end

  test "版本不符的快照直接棄用，房間全新開張" do
    id = fresh_id()

    Repo.insert!(%RoomSnapshot{
      room_id: id,
      version: -1,
      payload: :erlang.term_to_binary(%{bogus: true}),
      updated_at: DateTime.utc_now()
    })

    room = start_room(id)
    s = :sys.get_state(room)
    assert s.status == :lobby
    assert s.users == %{}
    # 壞快照已被清掉
    assert Repo.get(RoomSnapshot, id) == nil
  end

  test "大廳空房（無真人）刪快照" do
    id = fresh_id()
    room = start_room(id)

    conn = spawn(fn -> receive(do: (:bye -> :ok)) end)
    Room.join(room, user("a"), conn)
    assert %RoomSnapshot{} = Repo.get(RoomSnapshot, id)

    # 未入座者斷線即被清出房間 → 房間空了，快照一併刪除
    send(conn, :bye)
    wait_until(fn -> Repo.get(RoomSnapshot, id) == nil end)
  end

  test "main 大廳即使無人也保留快照，聊天歷史跨重啟" do
    stop_existing_room("main")
    room = start_room("main")

    conn = spawn(fn -> receive(do: (:bye -> :ok)) end)
    Room.join(room, user("a"), conn)
    :ok = Room.chat(room, "a", "重啟前的留言")
    send(conn, :bye)
    wait_until(fn -> :sys.get_state(room).users == %{} end)

    assert %RoomSnapshot{} = Repo.get(RoomSnapshot, "main")

    :ok = GenServer.stop(room)
    room2 = start_room("main")
    assert Enum.any?(:sys.get_state(room2).chat, &(&1.text == "重啟前的留言"))
  end

  test "對局表開局建列、動作日誌連號、重播重建出一致狀態" do
    id = fresh_id()
    room = start_room(id)
    begin_game(room)

    %{game_id: game_id} = :sys.get_state(room)
    game = Repo.get!(Game, game_id)
    assert game.room_id == id
    assert game.map == "usa"
    assert game.initial_state != nil
    assert game.started_at != nil
    assert game.finished_at == nil

    drive_room(room, "a", 60)
    s = settle_on_human(room, "a")
    assert s.action_seq > 0

    seqs =
      Repo.all(
        from(a in GameAction, where: a.game_id == ^game_id, order_by: a.seq, select: a.seq)
      )

    assert seqs == Enum.to_list(1..s.action_seq)

    # 重播不變量：initial_state 依序重套動作 == 當下實際引擎狀態
    assert {:ok, replayed} = Replay.run(game_id)
    assert Store.pack_engine(replayed) == Store.pack_engine(s.engine)
  end

  test "中途結束遊戲：對局補 aborted_at，快照回大廳" do
    id = fresh_id()
    room = start_room(id)
    begin_game(room)
    %{game_id: game_id} = :sys.get_state(room)

    :ok = Room.admin_abort(room, "a")

    game = Repo.get!(Game, game_id)
    assert game.aborted_at != nil
    assert game.finished_at == nil

    {:ok, saved} = Store.load(id)
    assert saved.status == :lobby
    assert saved.game_id == nil
  end

  test "sweep 清掃逾時快照，main 例外" do
    stale_at = DateTime.add(DateTime.utc_now(), -25, :hour)

    for room_id <- ["stale1", "main"] do
      Repo.insert!(%RoomSnapshot{
        room_id: room_id,
        version: Store.snapshot_version(),
        payload: :erlang.term_to_binary(%{}),
        updated_at: stale_at
      })
    end

    Repo.insert!(%RoomSnapshot{
      room_id: "fresh1",
      version: Store.snapshot_version(),
      payload: :erlang.term_to_binary(%{}),
      updated_at: DateTime.utc_now()
    })

    :ok = Store.sweep(24)

    assert Repo.get(RoomSnapshot, "stale1") == nil
    assert Repo.get(RoomSnapshot, "main") != nil
    assert Repo.get(RoomSnapshot, "fresh1") != nil
  end

  test "finish_game 補上名次與勝者" do
    {engine, _events} = GridMaster.Engine.new(["a", "npc_1"], seed: {1, 2, 3})
    {:ok, game_id} = Store.create_game("t", engine)

    :ok =
      Store.finish_game(game_id, %{
        players: [
          %{rank: 1, id: "a", name: "小明", npc: false, powered: 17, credits: 20, cities: 18}
        ],
        winner_id: "a",
        winner_name: "小明",
        rounds: 12
      })

    game = Repo.get!(Game, game_id)
    assert game.winner_id == "a"
    assert game.winner_name == "小明"
    assert game.rounds == 12
    assert [%{"rank" => 1, "npc" => false} | _] = game.players
    assert game.finished_at != nil
  end
end
