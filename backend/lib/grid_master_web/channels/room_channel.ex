defmodule GridMasterWeb.RoomChannel do
  @moduledoc """
  房間 Channel：JSON 事件 ↔ Room GenServer 的轉譯層。
  遊戲動作經白名單轉成引擎的 atom 動作；未知事件一律拒絕。
  """

  use Phoenix.Channel

  alias GridMaster.{Room, Rooms}
  alias GridMasterWeb.Presence

  @lobby_ops %{
    "seat_take" => :seat_take,
    "seat_leave" => :seat_leave,
    "ready" => :ready,
    "unready" => :unready,
    "game_start" => :game_start,
    "back_to_lobby" => :back_to_lobby,
    "npc_add" => :npc_add,
    "npc_remove" => :npc_remove
  }

  @game_actions %{
    "auction_choose" => {:auction_choose, ~w(plant bid)a},
    "auction_bid" => {:auction_bid, ~w(amount)a},
    "auction_fold" => {:auction_fold, []},
    "auction_pass" => {:auction_pass, []},
    "auction_discard" => {:auction_discard, ~w(plant)a},
    "resources_buy" => {:resources_buy, ~w(hydro thermal waste quantum)a},
    "build" => {:build, ~w(city)a},
    "build_done" => {:build_done, []},
    "power_submit" => {:power_submit, ~w(plants)a}
  }

  @impl true
  def join("room:" <> room_id, _params, socket) do
    {:ok, room} = Rooms.ensure(room_id)
    snapshot = Room.join(room, socket.assigns.user, self())
    send(self(), :after_join)

    # self：告訴客戶端自己的 user_id（token 雜湊導出，客戶端無法自行得知）
    {:ok, Map.put(snapshot, :self, socket.assigns.user.id), assign(socket, :room, room)}
  end

  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.user
    {:ok, _ref} = Presence.track(socket, user.id, %{name: user.name})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in(event, _params, socket) when is_map_key(@lobby_ops, event) do
    socket.assigns.room
    |> Room.lobby_op(@lobby_ops[event], socket.assigns.user.id)
    |> respond(socket)
  end

  def handle_in("chat_send", %{"text" => text}, socket) do
    socket.assigns.room
    |> Room.chat(socket.assigns.user.id, text)
    |> respond(socket)
  end

  def handle_in("admin_abort", _params, socket) do
    socket.assigns.room
    |> Room.admin_abort(socket.assigns.user.id)
    |> respond(socket)
  end

  def handle_in("action", %{"type" => type} = params, socket) do
    case translate(type, Map.get(params, "payload", %{})) do
      {:ok, action_type, payload} ->
        socket.assigns.room
        |> Room.game_action(socket.assigns.user.id, action_type, payload)
        |> respond(socket)

      :error ->
        {:reply, {:error, %{reason: "unknown_action"}}, socket}
    end
  end

  def handle_in(_event, _params, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  defp respond(:ok, socket), do: {:reply, :ok, socket}

  defp respond({:error, reason}, socket),
    do: {:reply, {:error, %{reason: to_string(reason)}}, socket}

  defp translate(type, payload) when is_map(payload) do
    case @game_actions[type] do
      nil ->
        :error

      {action_type, keys} ->
        atom_payload =
          keys
          |> Enum.map(fn key -> {key, Map.get(payload, Atom.to_string(key))} end)
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()

        {:ok, action_type, atom_payload}
    end
  end

  defp translate(_type, _payload), do: :error
end
