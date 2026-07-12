defmodule GridMasterWeb.AccountControllerTest do
  use GridMasterWeb.ConnCase, async: true

  describe "POST /api/auth/register" do
    test "成功 → 回 token 與顯示名，token 可驗簽出帳號身份", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{username: "Neo", password: "matrix"})
      assert %{"token" => token, "name" => "Neo"} = json_response(conn, 200)

      assert {:ok, %{id: id, name: "Neo"}} =
               Phoenix.Token.verify(GridMasterWeb.Endpoint, "password_auth", token, max_age: 60)

      assert is_integer(id)
    end

    test "帳號格式不符 → 422 帶中文錯誤訊息", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{username: "no@email.com", password: "pass"})
      assert %{"error" => "帳號須為 3–20 個英數字元"} = json_response(conn, 422)
    end

    test "密碼太短 → 422", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{username: "Trinity", password: "abc"})
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "密碼"
    end

    test "帳號已存在 → 422", %{conn: conn} do
      post(conn, ~p"/api/auth/register", %{username: "Morpheus", password: "redpill"})
      conn = post(conn, ~p"/api/auth/register", %{username: "morpheus", password: "bluepill"})
      assert %{"error" => "帳號已被使用"} = json_response(conn, 422)
    end
  end

  describe "POST /api/auth/login" do
    setup %{conn: conn} do
      post(conn, ~p"/api/auth/register", %{username: "Smith", password: "agent007"})
      :ok
    end

    test "正確帳密 → 回 token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{username: "smith", password: "agent007"})
      assert %{"token" => _token, "name" => "Smith"} = json_response(conn, 200)
    end

    test "錯誤密碼 → 401，訊息不洩漏帳號是否存在", %{conn: conn} do
      wrong_pw = post(conn, ~p"/api/auth/login", %{username: "Smith", password: "nope"})
      no_user = post(conn, ~p"/api/auth/login", %{username: "ghost", password: "nope"})
      assert json_response(wrong_pw, 401) == json_response(no_user, 401)
    end

    test "缺參數 → 401 不噴 500", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{})
      assert %{"error" => _message} = json_response(conn, 401)
    end
  end
end
