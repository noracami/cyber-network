defmodule GridMasterWeb.AuthController do
  @moduledoc """
  Discord OAuth2 流程（scope 只要 `identify`）。

  成功後不建任何 DB 紀錄——直接以 `Phoenix.Token` 簽出含 Discord 身份的
  token 交給前端存 localStorage，WebSocket 連線時驗簽即得身份。
  無狀態、跨裝置、天然支援斷線重連的 Session 綁定（PRD §3.3）。
  """

  use GridMasterWeb, :controller

  @authorize_url "https://discord.com/oauth2/authorize"
  @token_url "https://discord.com/api/oauth2/token"
  @me_url "https://discord.com/api/users/@me"

  @doc "導向 Discord 授權頁；state 存 session 防 CSRF。"
  def request(conn, _params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    query =
      URI.encode_query(%{
        client_id: config()[:client_id],
        redirect_uri: config()[:redirect_uri],
        response_type: "code",
        scope: "identify",
        state: state
      })

    conn
    |> put_session(:discord_state, state)
    |> redirect(external: @authorize_url <> "?" <> query)
  end

  @doc "Discord 回呼：驗 state → 換 access token → 取身份 → 簽發登入 token。"
  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, :discord_state)
    conn = delete_session(conn, :discord_state)

    with true <- is_binary(expected) and Plug.Crypto.secure_compare(expected, state),
         {:ok, profile} <- exchange_and_fetch(code) do
      token = Phoenix.Token.sign(GridMasterWeb.Endpoint, "discord_auth", profile)
      redirect(conn, external: config()[:frontend_url] <> "/#discord_token=" <> token)
    else
      _ -> fail(conn)
    end
  end

  def callback(conn, _params), do: fail(conn)

  defp fail(conn), do: redirect(conn, external: config()[:frontend_url] <> "/#discord_error=1")

  defp exchange_and_fetch(code) do
    req_options = Application.get_env(:grid_master, :discord_req_options, [])

    with {:ok, %{status: 200, body: %{"access_token" => access_token}}} <-
           Req.post(
             [
               url: @token_url,
               form: [
                 client_id: config()[:client_id],
                 client_secret: config()[:client_secret],
                 grant_type: "authorization_code",
                 code: code,
                 redirect_uri: config()[:redirect_uri]
               ]
             ] ++ req_options
           ),
         {:ok, %{status: 200, body: %{"id" => id} = user}} <-
           Req.get([url: @me_url, auth: {:bearer, access_token}] ++ req_options) do
      {:ok,
       %{
         id: id,
         name: user["global_name"] || user["username"] || "Discord 玩家",
         avatar: avatar_url(user)
       }}
    else
      _ -> :error
    end
  end

  defp avatar_url(%{"id" => id, "avatar" => hash}) when is_binary(hash),
    do: "https://cdn.discordapp.com/avatars/#{id}/#{hash}.png?size=64"

  defp avatar_url(_user), do: nil

  defp config, do: Application.fetch_env!(:grid_master, :discord_oauth)
end
