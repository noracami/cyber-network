defmodule GridMasterWeb.UserSocket do
  @moduledoc """
  WebSocket 入口。MVP 身份：客戶端持有隨機 token（localStorage），
  user_id 由 token 雜湊導出——同 token 重連即同身份（斷線重連的基礎）。
  token 等於 `:admin_token` 設定值者取得 admin 身份；M6 再接 Discord OAuth。
  """

  use Phoenix.Socket

  channel "room:*", GridMasterWeb.RoomChannel

  # Discord 登入 token 有效期（30 天；過期自動退回訪客身份，前端會清除）
  @discord_token_max_age 30 * 24 * 3600

  @impl true
  def connect(params, socket, _connect_info) do
    case discord_user(params["discord_token"]) do
      {:ok, user} ->
        # alias_of：同瀏覽器的訪客身份。Room 會把訪客的座位合併給 Discord 身份，
        # 避免「登入後舊訪客殘影還佔著位子」。
        user = Map.put(user, :alias_of, guest_alias(params["token"]))
        {:ok, assign(socket, :user, user)}

      :error ->
        guest_connect(params, socket)
    end
  end

  defp guest_alias(token) when is_binary(token) and byte_size(token) >= 8, do: user_id(token)
  defp guest_alias(_token), do: nil

  defp discord_user(token) when is_binary(token) do
    case Phoenix.Token.verify(GridMasterWeb.Endpoint, "discord_auth", token,
           max_age: @discord_token_max_age
         ) do
      {:ok, %{id: discord_id, name: name, avatar: avatar}} ->
        {:ok,
         %{
           id: "d_" <> discord_id,
           name: sanitize_name(name),
           avatar: avatar,
           role: discord_role(discord_id)
         }}

      _invalid ->
        :error
    end
  end

  defp discord_user(_missing), do: :error

  # ADMIN_DISCORD_IDS：逗號分隔的 Discord ID 清單，生產環境的 admin 授權方式
  defp discord_role(discord_id) do
    admins = Application.get_env(:grid_master, :admin_discord_ids, [])
    if discord_id in admins, do: "admin", else: "discord"
  end

  defp guest_connect(params, socket) do
    token = params["token"]

    if is_binary(token) and byte_size(token) >= 8 do
      user = %{id: user_id(token), name: sanitize_name(params["name"]), avatar: nil, role: role(token)}
      {:ok, assign(socket, :user, user)}
    else
      :error
    end
  end

  @impl true
  def id(socket), do: "user_socket:" <> socket.assigns.user.id

  defp user_id(token) do
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    "u_" <> binary_part(hash, 0, 12)
  end

  defp role(token) do
    admin_token = Application.get_env(:grid_master, :admin_token)
    if is_binary(admin_token) and token == admin_token, do: "admin", else: "guest"
  end

  defp sanitize_name(name) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, 20) do
      "" -> "訪客"
      trimmed -> trimmed
    end
  end

  defp sanitize_name(_name), do: "訪客"
end
