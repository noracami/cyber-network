defmodule GridMasterWeb.ActivityControllerTest do
  use GridMasterWeb.ConnCase, async: true

  alias GridMaster.Room

  test "回報房間數與進行中牌局數", %{conn: conn} do
    room_id = "act#{System.unique_integer([:positive])}"
    {:ok, room} = GridMaster.Rooms.ensure(room_id)

    for id <- ["a", "b"] do
      Room.join(room, %{id: id, name: id, role: "discord"}, self())
      :ok = Room.lobby_op(room, :seat_take, id)
      :ok = Room.lobby_op(room, :ready, id)
    end

    :ok = Room.lobby_op(room, :game_start, "a")

    body = conn |> get(~p"/api/activity") |> json_response(200)
    assert body["rooms"] >= 1
    assert body["in_game"] >= 1
  end
end
