defmodule GridMaster.RoomTest do
  use ExUnit.Case, async: true

  alias GridMaster.Room

  defp start_room(opts \\ []) do
    id = "t#{System.unique_integer([:positive])}"
    pid = start_supervised!({Room, Keyword.merge([id: id, seat_timeout: 60], opts)})
    GridMasterWeb.Endpoint.subscribe("room:" <> id)
    pid
  end

  # 入座需登入，測試玩家預設用 discord 身份
  defp user(id, role \\ "discord"), do: %{id: id, name: id, role: role}

  defp join_seated(room, ids) do
    for id <- ids do
      Room.join(room, user(id), self())
      :ok = Room.lobby_op(room, :seat_take, id)
      :ok = Room.lobby_op(room, :ready, id)
    end
  end

  describe "大廳流程" do
    test "入座、準備、開局" do
      room = start_room()
      Room.join(room, user("a"), self())
      Room.join(room, user("b"), self())

      assert :ok = Room.lobby_op(room, :seat_take, "a")
      assert {:error, :already_seated} = Room.lobby_op(room, :seat_take, "a")
      assert :ok = Room.lobby_op(room, :seat_take, "b")

      # 未全員準備不能開局；旁觀者不能準備
      assert {:error, :not_seated} = Room.lobby_op(room, :ready, "c")
      assert :ok = Room.lobby_op(room, :ready, "a")
      assert {:error, :not_all_ready} = Room.lobby_op(room, :game_start, "a")
      assert :ok = Room.lobby_op(room, :ready, "b")
      assert :ok = Room.lobby_op(room, :game_start, "a")

      snapshot = Room.snapshot(room)
      assert snapshot.status == :in_game
      assert snapshot.game.round == 1
      assert Enum.sort(snapshot.game.turn_order) == ["a", "b"]
      assert_received %Phoenix.Socket.Broadcast{event: "game_events"}

      # 遊戲中不能離座、不能再開局
      assert {:error, :not_in_lobby} = Room.lobby_op(room, :seat_leave, "a")
      assert {:error, :not_in_lobby} = Room.lobby_op(room, :game_start, "a")
    end

    test "訪客不能入座（需 Discord 登入），但能聊天" do
      room = start_room()
      Room.join(room, user("g1", "guest"), self())

      assert {:error, :login_required} = Room.lobby_op(room, :seat_take, "g1")
      assert :ok = Room.chat(room, "g1", "旁觀嘴砲")
    end

    test "少於 2 人不能開局；座位上限 6" do
      room = start_room()
      Room.join(room, user("solo"), self())
      :ok = Room.lobby_op(room, :seat_take, "solo")
      :ok = Room.lobby_op(room, :ready, "solo")
      assert {:error, :not_enough_players} = Room.lobby_op(room, :game_start, "solo")

      for i <- 1..5 do
        Room.join(room, user("p#{i}"), self())
        assert :ok = Room.lobby_op(room, :seat_take, "p#{i}")
      end

      Room.join(room, user("p6"), self())
      assert {:error, :room_full} = Room.lobby_op(room, :seat_take, "p6")
    end
  end

  describe "遊戲動作轉發" do
    test "輪到者動作成功並廣播，非法動作回錯誤" do
      room = start_room()
      join_seated(room, ["a", "b"])
      :ok = Room.lobby_op(room, :game_start, "a")

      [first, second] = Room.snapshot(room).game.turn_order

      # 先消化開局的 game_events 廣播
      assert_received %Phoenix.Socket.Broadcast{
        event: "game_events",
        payload: %{events: start_events}
      }

      assert Enum.any?(start_events, &(&1.type == :game_started))

      # 不在順位 → 引擎錯誤原樣回傳
      assert {:error, :not_your_turn} =
               Room.game_action(room, second, :auction_choose, %{plant: 3, bid: 3})

      assert :ok = Room.game_action(room, first, :auction_choose, %{plant: 3, bid: 3})
      assert_received %Phoenix.Socket.Broadcast{event: "game_events", payload: %{events: events}}
      assert Enum.any?(events, &(&1.type == :auction_opened))

      # 旁觀者不是玩家
      Room.join(room, user("ghost"), self())

      assert {:error, :unknown_player} =
               Room.game_action(room, "ghost", :auction_bid, %{amount: 10})
    end

    test "大廳狀態不接受遊戲動作" do
      room = start_room()
      Room.join(room, user("a"), self())
      assert {:error, :not_in_game} = Room.game_action(room, "a", :build_done, %{})
    end
  end

  describe "聊天室" do
    test "訊息快取上限 50 則、空訊息拒絕" do
      room = start_room()
      Room.join(room, user("a"), self())

      assert {:error, :invalid_message} = Room.chat(room, "a", "   ")
      assert {:error, :invalid_message} = Room.chat(room, "陌生人", "hi")

      for i <- 1..55, do: :ok = Room.chat(room, "a", "訊息 #{i}")

      chat = Room.snapshot(room).chat
      assert length(chat) == 50
      # 快照按時間排序，最舊的已被擠出
      assert List.first(chat).text == "訊息 6"
      assert List.last(chat).text == "訊息 55"
    end
  end

  describe "斷線處理" do
    test "大廳入座者離線逾時自動離座" do
      room = start_room(seat_timeout: 60)
      channel = spawn(fn -> receive(do: (:stop -> :ok)) end)
      Room.join(room, user("a"), channel)
      :ok = Room.lobby_op(room, :seat_take, "a")

      send(channel, :stop)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "chat_new",
                       payload: %{text: "a 離線逾時，已自動離座"}
                     },
                     500

      assert Room.snapshot(room).seats == []
    end

    test "逾時前重連保住座位" do
      room = start_room(seat_timeout: 100)
      channel = spawn(fn -> receive(do: (:stop -> :ok)) end)
      Room.join(room, user("a"), channel)
      :ok = Room.lobby_op(room, :seat_take, "a")

      send(channel, :stop)
      # 等 DOWN 處理完（會廣播離線 sysmsg）
      assert_receive %Phoenix.Socket.Broadcast{payload: %{text: "a 已離線"}}, 500

      Room.join(room, user("a"), self())
      Process.sleep(150)
      assert Room.snapshot(room).seats == ["a"]
    end

    test "遊戲中斷線保留座位" do
      room = start_room(seat_timeout: 60)
      channel = spawn(fn -> receive(do: (:stop -> :ok)) end)
      Room.join(room, user("a"), channel)
      Room.join(room, user("b"), self())

      for id <- ["a", "b"] do
        :ok = Room.lobby_op(room, :seat_take, id)
        :ok = Room.lobby_op(room, :ready, id)
      end

      :ok = Room.lobby_op(room, :game_start, "a")
      send(channel, :stop)
      Process.sleep(150)

      snapshot = Room.snapshot(room)
      assert snapshot.status == :in_game
      assert "a" in snapshot.seats
    end
  end

  describe "身份合併（訪客 → Discord 登入）" do
    test "旁觀中的訪客登入後，舊訪客殘影移除" do
      room = start_room()
      Room.join(room, user("u_guest", "guest"), self())

      # OAuth 重導後以 Discord 身份重連，alias_of 指向原訪客
      Room.join(
        room,
        %{
          id: "d_42",
          name: "DC客兒",
          role: "discord",
          avatar: "http://a/b.png",
          alias_of: "u_guest"
        },
        self()
      )

      snapshot = Room.snapshot(room)
      assert Map.has_key?(snapshot.users, "d_42")
      refute Map.has_key?(snapshot.users, "u_guest")
    end

    test "入座中的舊身份（admin token 路徑）登入 Discord，座位與準備狀態跟著走" do
      room = start_room()
      Room.join(room, user("u_gm", "admin"), self())
      :ok = Room.lobby_op(room, :seat_take, "u_gm")
      :ok = Room.lobby_op(room, :ready, "u_gm")

      Room.join(
        room,
        %{id: "d_42", name: "DC客兒", role: "discord", avatar: nil, alias_of: "u_gm"},
        self()
      )

      snapshot = Room.snapshot(room)
      assert snapshot.seats == ["d_42"]
      assert snapshot.users["d_42"].ready
      refute Map.has_key?(snapshot.users, "u_gm")
    end

    test "牌局進行中不合併，避免破壞引擎玩家對應" do
      room = start_room()
      join_seated(room, ["u_a", "u_b"])
      :ok = Room.lobby_op(room, :game_start, "u_a")

      Room.join(
        room,
        %{id: "d_9", name: "DC", role: "discord", avatar: nil, alias_of: "u_a"},
        self()
      )

      snapshot = Room.snapshot(room)
      assert "u_a" in snapshot.seats
      refute "d_9" in snapshot.seats
      # 兩個身份並存：舊的還是玩家，新的是旁觀者
      assert Map.has_key?(snapshot.users, "u_a")
      assert Map.has_key?(snapshot.users, "d_9")
    end

    test "alias 不存在或相同時不動作" do
      room = start_room()

      Room.join(
        room,
        %{id: "d_1", name: "DC", role: "discord", avatar: nil, alias_of: "u_nobody"},
        self()
      )

      assert Map.has_key?(Room.snapshot(room).users, "d_1")
    end
  end

  describe "結束遊戲（掀桌）" do
    test "admin 與入座玩家可結束；旁觀者不行（2026-07-12 權力下放）" do
      room = start_room()
      Room.join(room, user("gm", "admin"), self())
      Room.join(room, user("watcher"), self())
      join_seated(room, ["a", "b"])
      :ok = Room.lobby_op(room, :game_start, "a")

      assert {:error, :forbidden} = Room.admin_abort(room, "watcher")
      assert :ok = Room.admin_abort(room, "gm")

      snapshot = Room.snapshot(room)
      assert snapshot.status == :lobby
      assert snapshot.game == nil
      # 座位保留但準備狀態重置
      assert Enum.sort(snapshot.seats) == ["a", "b"]
      refute snapshot.users["a"].ready
    end
  end
end
