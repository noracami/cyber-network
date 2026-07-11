defmodule GridMasterWeb.UserSocket do
  @moduledoc """
  WebSocket 入口。MVP 身份：客戶端持有隨機 token（localStorage），
  user_id 由 token 雜湊導出——同 token 重連即同身份（斷線重連的基礎）。
  token 等於 `:admin_token` 設定值者取得 admin 身份；M6 再接 Discord OAuth。
  """

  use Phoenix.Socket

  channel "room:*", GridMasterWeb.RoomChannel

  @impl true
  def connect(params, socket, _connect_info) do
    token = params["token"]

    if is_binary(token) and byte_size(token) >= 8 do
      user = %{id: user_id(token), name: sanitize_name(params["name"]), role: role(token)}
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
