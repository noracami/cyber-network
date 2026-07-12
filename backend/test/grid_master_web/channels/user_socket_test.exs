defmodule GridMasterWeb.UserSocketTest do
  # 會動 Application env（admin_discord_ids），關閉 async
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias GridMasterWeb.UserSocket

  @endpoint GridMasterWeb.Endpoint

  defp sign(payload), do: Phoenix.Token.sign(@endpoint, "discord_auth", payload)

  test "有效 discord_token → Discord 身份（id 前綴 d_、帶頭像）" do
    token = sign(%{id: "424242", name: "DC 玩家", avatar: "https://cdn.example/a.png"})
    {:ok, socket} = connect(UserSocket, %{"discord_token" => token})

    assert socket.assigns.user.id == "d_424242"
    assert socket.assigns.user.name == "DC 玩家"
    assert socket.assigns.user.avatar == "https://cdn.example/a.png"
    assert socket.assigns.user.role == "discord"
  end

  test "同一 Discord 帳號跨裝置連線得到同一身份" do
    token_a = sign(%{id: "777", name: "A 裝置", avatar: nil})
    token_b = sign(%{id: "777", name: "B 裝置", avatar: nil})
    {:ok, socket_a} = connect(UserSocket, %{"discord_token" => token_a})
    {:ok, socket_b} = connect(UserSocket, %{"discord_token" => token_b})

    assert socket_a.assigns.user.id == socket_b.assigns.user.id
  end

  test "同時帶訪客 token 時，alias_of 指向訪客身份（供 Room 合併座位）" do
    {:ok, guest_socket} = connect(UserSocket, %{"token" => "shared-guest-token", "name" => "訪客"})

    token = sign(%{id: "555", name: "DC", avatar: nil})

    {:ok, discord_socket} =
      connect(UserSocket, %{"discord_token" => token, "token" => "shared-guest-token"})

    assert discord_socket.assigns.user.alias_of == guest_socket.assigns.user.id
  end

  test "壞掉的 discord_token → 退回訪客身份" do
    {:ok, socket} =
      connect(UserSocket, %{
        "discord_token" => "tampered-garbage",
        "token" => "guest-fallback-token",
        "name" => "備援訪客"
      })

    assert socket.assigns.user.role == "guest"
    assert socket.assigns.user.name == "備援訪客"
  end

  test "壞 token 且無訪客備援 → 拒絕連線" do
    assert :error = connect(UserSocket, %{"discord_token" => "garbage"})
  end

  test "有效 password_token → 帳密身份（id 前綴 p_、role user，可入座）" do
    token = Phoenix.Token.sign(@endpoint, "password_auth", %{id: 42, name: "Neo"})
    {:ok, socket} = connect(UserSocket, %{"password_token" => token})

    assert socket.assigns.user.id == "p_42"
    assert socket.assigns.user.name == "Neo"
    assert socket.assigns.user.role == "user"
    assert socket.assigns.user.avatar == nil
  end

  test "password_token 也支援訪客 alias_of 合併" do
    {:ok, guest_socket} = connect(UserSocket, %{"token" => "pw-guest-token", "name" => "訪客"})
    token = Phoenix.Token.sign(@endpoint, "password_auth", %{id: 7, name: "Sub7"})

    {:ok, socket} = connect(UserSocket, %{"password_token" => token, "token" => "pw-guest-token"})
    assert socket.assigns.user.alias_of == guest_socket.assigns.user.id
  end

  test "壞掉的 password_token → 退回訪客身份" do
    {:ok, socket} =
      connect(UserSocket, %{
        "password_token" => "garbage",
        "token" => "pw-fallback-token",
        "name" => "備援"
      })

    assert socket.assigns.user.role == "guest"
  end

  test "ADMIN_DISCORD_IDS 內的帳號取得 admin 身份" do
    Application.put_env(:grid_master, :admin_discord_ids, ["909090"])
    on_exit(fn -> Application.put_env(:grid_master, :admin_discord_ids, []) end)

    token = sign(%{id: "909090", name: "管理員", avatar: nil})
    {:ok, socket} = connect(UserSocket, %{"discord_token" => token})
    assert socket.assigns.user.role == "admin"
  end
end
