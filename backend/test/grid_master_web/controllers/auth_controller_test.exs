defmodule GridMasterWeb.AuthControllerTest do
  # Application.put_env 是全域操作，關閉 async 避免污染其他測試
  use GridMasterWeb.ConnCase, async: false

  setup do
    Application.put_env(:grid_master, :discord_req_options,
      plug: {Req.Test, DiscordStub},
      retry: false
    )

    Req.Test.stub(DiscordStub, fn conn ->
      case conn.request_path do
        "/api/oauth2/token" ->
          Req.Test.json(conn, %{"access_token" => "stub-access-token"})

        "/api/users/@me" ->
          Req.Test.json(conn, %{
            "id" => "112233",
            "username" => "kerker",
            "global_name" => "客兒",
            "avatar" => "abcdef"
          })
      end
    end)

    on_exit(fn -> Application.delete_env(:grid_master, :discord_req_options) end)
    :ok
  end

  test "GET /auth/discord 導向 Discord 授權頁並埋入 state", %{conn: conn} do
    conn = get(conn, ~p"/auth/discord")
    location = redirected_to(conn, 302)

    assert location =~ "discord.com/oauth2/authorize"
    assert location =~ "scope=identify"
    assert get_session(conn, :discord_state) != nil
    assert location =~ URI.encode_www_form(get_session(conn, :discord_state))
  end

  test "callback 成功：簽發身份 token 並導回前端", %{conn: conn} do
    conn = get(conn, ~p"/auth/discord")
    state = get_session(conn, :discord_state)

    conn = get(recycle(conn), ~p"/auth/discord/callback?code=fake-code&state=#{state}")
    location = redirected_to(conn, 302)
    assert location =~ "#discord_token="

    token = location |> String.split("#discord_token=") |> List.last()

    assert {:ok, %{id: "112233", name: "客兒", avatar: avatar}} =
             Phoenix.Token.verify(GridMasterWeb.Endpoint, "discord_auth", token, max_age: 60)

    assert avatar == "https://cdn.discordapp.com/avatars/112233/abcdef.png?size=64"
  end

  test "state 不符（CSRF）→ 導回錯誤", %{conn: conn} do
    conn = get(conn, ~p"/auth/discord")
    conn = get(recycle(conn), ~p"/auth/discord/callback?code=fake-code&state=wrong-state")
    assert redirected_to(conn, 302) =~ "#discord_error=1"
  end

  test "缺 code 參數 → 導回錯誤", %{conn: conn} do
    conn = get(conn, ~p"/auth/discord/callback?state=whatever")
    assert redirected_to(conn, 302) =~ "#discord_error=1"
  end
end
