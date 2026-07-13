defmodule GridMasterWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP 版 admin 驗證，授權來源與 UserSocket 相同：
  Bearer token 等於 `:admin_token` 設定值，或為 Discord 登入 token
  且該 Discord ID 在 `:admin_discord_ids` 清單內。
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @auth_token_max_age 30 * 24 * 3600

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- bearer_token(conn),
         true <- admin?(token) do
      conn
    else
      _denied ->
        conn
        |> put_status(403)
        |> json(%{error: "需要 admin 權限"})
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _missing -> nil
    end
  end

  defp admin?(token) do
    static_admin?(token) or discord_admin?(token)
  end

  defp static_admin?(token) do
    admin_token = Application.get_env(:grid_master, :admin_token)
    is_binary(admin_token) and Plug.Crypto.secure_compare(token, admin_token)
  end

  defp discord_admin?(token) do
    case Phoenix.Token.verify(GridMasterWeb.Endpoint, "discord_auth", token,
           max_age: @auth_token_max_age
         ) do
      {:ok, %{id: discord_id}} ->
        discord_id in Application.get_env(:grid_master, :admin_discord_ids, [])

      _invalid ->
        false
    end
  end
end
