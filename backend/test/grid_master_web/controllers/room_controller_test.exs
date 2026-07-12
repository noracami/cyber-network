defmodule GridMasterWeb.RoomControllerTest do
  use GridMasterWeb.ConnCase, async: true

  alias GridMaster.Room

  test "列出活躍房間：狀態、入座數、在線真人數（NPC 不算）", %{conn: conn} do
    room_id =
      "rl" <> String.pad_leading("#{rem(System.unique_integer([:positive]), 10_000)}", 4, "0")

    {:ok, room} = GridMaster.Rooms.ensure(room_id)

    Room.join(room, %{id: "a", name: "a", role: "discord"}, self())
    :ok = Room.lobby_op(room, :seat_take, "a")
    :ok = Room.lobby_op(room, :npc_add, "a")

    body = conn |> get(~p"/api/rooms") |> json_response(200)
    entry = Enum.find(body["rooms"], &(&1["id"] == room_id))

    assert entry["status"] == "lobby"
    assert entry["seated"] == 2
    assert entry["online"] == 1
  end
end
