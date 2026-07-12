defmodule GridMasterWeb.RoomChannelTest do
  use ExUnit.Case, async: true

  import Phoenix.ChannelTest

  alias GridMasterWeb.UserSocket

  @endpoint GridMasterWeb.Endpoint

  defp connect_user(token, name) do
    {:ok, socket} = connect(UserSocket, %{"token" => token, "name" => name})
    socket
  end

  # 入座需登入：模擬 Discord 身份連線
  defp connect_discord(discord_id, name) do
    token =
      Phoenix.Token.sign(@endpoint, "discord_auth", %{id: discord_id, name: name, avatar: nil})

    {:ok, socket} = connect(UserSocket, %{"discord_token" => token})
    socket
  end

  defp join_room(socket, room_id) do
    {:ok, snapshot, socket} = subscribe_and_join(socket, "room:" <> room_id)
    {snapshot, socket}
  end

  # 房號需通過白名單（^[a-z0-9]{4,6}$）：固定 6 字元
  defp new_room_id,
    do: "r" <> String.pad_leading("#{rem(System.unique_integer([:positive]), 100_000)}", 5, "0")

  test "token 太短拒絕連線；缺 token 拒絕連線" do
    assert :error = connect(UserSocket, %{"token" => "abc"})
    assert :error = connect(UserSocket, %{})
  end

  test "同 token 重連得到同一身份（斷線重連基礎）" do
    socket_a = connect_user("same-token-12345", "小明")
    socket_b = connect_user("same-token-12345", "小明")
    assert socket_a.assigns.user.id == socket_b.assigns.user.id

    socket_c = connect_user("other-token-9876", "小華")
    refute socket_a.assigns.user.id == socket_c.assigns.user.id
  end

  test "房號白名單：main 與 4–6 字元小寫英數之外一律拒絕" do
    socket = connect_user("guest-token-0001", "小明")

    for bad <- ["ab", "toolong7", "ABCD", "a-b3d", "房間一"] do
      assert {:error, %{reason: "invalid_room"}} =
               subscribe_and_join(socket, "room:" <> bad)
    end

    assert {:ok, _snapshot, _socket} = subscribe_and_join(socket, "room:main")
  end

  test "join 回傳大廳快照、聊天歷史與自己的身份" do
    socket = connect_user("guest-token-0001", "小明")
    {snapshot, socket} = join_room(socket, new_room_id())

    assert snapshot.status == :lobby
    assert snapshot.chat == []
    assert snapshot.game == nil
    assert snapshot.self == socket.assigns.user.id
  end

  test "Discord 使用者入座 → 廣播 room_sync；聊天 → 廣播 chat_new" do
    socket = connect_discord("10001", "小明")
    {_snapshot, socket} = join_room(socket, new_room_id())

    ref = push(socket, "seat_take", %{})
    assert_reply ref, :ok
    assert_broadcast "room_sync", %{status: :lobby, seats: [_]}

    ref = push(socket, "chat_send", %{"text" => "大家好"})
    assert_reply ref, :ok
    assert_broadcast "chat_new", %{kind: "chat", text: "大家好", name: "小明"}
  end

  test "訪客入座被拒（login_required），聊天不受影響" do
    socket = connect_user("guest-token-0002", "小明")
    {_snapshot, socket} = join_room(socket, new_room_id())

    ref = push(socket, "seat_take", %{})
    assert_reply ref, :error, %{reason: "login_required"}

    ref = push(socket, "chat_send", %{"text" => "旁觀發言"})
    assert_reply ref, :ok
  end

  test "名字過長被截斷、空名得到預設值" do
    socket = connect_user("guest-token-0003", String.duplicate("超", 30))
    assert String.length(socket.assigns.user.name) == 20

    socket = connect_user("guest-token-0004", "   ")
    assert socket.assigns.user.name == "訪客"
  end

  test "未知事件與未知動作被拒絕" do
    socket = connect_user("guest-token-0005", "小明")
    {_snapshot, socket} = join_room(socket, new_room_id())

    ref = push(socket, "hack_the_planet", %{})
    assert_reply ref, :error, %{reason: "unknown_event"}

    ref = push(socket, "action", %{"type" => "delete_everything", "payload" => %{}})
    assert_reply ref, :error, %{reason: "unknown_action"}
  end

  test "完整開局：兩位玩家經 channel 入座開打並下第一手" do
    room_id = new_room_id()
    socket_a = connect_discord("20001", "玩家A")
    socket_b = connect_discord("20002", "玩家B")
    {_snapshot, socket_a} = join_room(socket_a, room_id)
    {_snapshot, socket_b} = join_room(socket_b, room_id)

    for socket <- [socket_a, socket_b] do
      ref = push(socket, "seat_take", %{})
      assert_reply ref, :ok
      ref = push(socket, "ready", %{})
      assert_reply ref, :ok
    end

    ref = push(socket_a, "game_start", %{})
    assert_reply ref, :ok
    assert_broadcast "game_events", %{events: _}
    assert_broadcast "room_sync", %{status: :in_game, game: game}
    [first | _] = game.turn_order

    first_socket = if socket_a.assigns.user.id == first, do: socket_a, else: socket_b

    ref =
      push(first_socket, "action", %{
        "type" => "auction_choose",
        "payload" => %{"plant" => 3, "bid" => 3}
      })

    assert_reply ref, :ok

    # 錯誤的出價 payload 被引擎擋下並回報原因
    other_socket = if first_socket == socket_a, do: socket_b, else: socket_a
    ref = push(other_socket, "action", %{"type" => "auction_bid", "payload" => %{"amount" => 1}})
    assert_reply ref, :error, %{reason: "bid_too_low"}
  end

  test "admin token 才能掀桌" do
    room_id = new_room_id()
    guest = connect_user("normal-guest-tok", "路人")
    {_snapshot, guest} = join_room(guest, room_id)

    ref = push(guest, "admin_abort", %{})
    assert_reply ref, :error, %{reason: "forbidden"}

    admin = connect_user("dev-admin-token", "GM")
    assert admin.assigns.user.role == "admin"
    {_snapshot, admin} = join_room(admin, room_id)

    ref = push(admin, "admin_abort", %{})
    assert_reply ref, :ok
  end
end
