defmodule GridMasterWeb.AccountController do
  @moduledoc """
  帳密註冊／登入（PRD-v1.1 R6，測試用輕量帳號）。

  成功即簽發與 Discord 登入同模式的 `Phoenix.Token`（salt `"password_auth"`、
  30 天效期），前端存 localStorage，WebSocket 連線時驗簽得 `p_<id>` 身份。
  """

  use GridMasterWeb, :controller

  alias GridMaster.Accounts

  @field_names %{username: "帳號", password: "密碼"}

  def register(conn, params) do
    case Accounts.register(%{username: params["username"], password: params["password"]}) do
      {:ok, account} ->
        json(conn, session(account))

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: first_error(changeset)})
    end
  end

  def login(conn, params) do
    case Accounts.authenticate(params["username"] || "", params["password"] || "") do
      {:ok, account} ->
        json(conn, session(account))

      :error ->
        conn |> put_status(401) |> json(%{error: "帳號或密碼錯誤"})
    end
  end

  defp session(account) do
    token =
      Phoenix.Token.sign(GridMasterWeb.Endpoint, "password_auth", %{
        id: account.id,
        name: account.username
      })

    %{token: token, name: account.username}
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.find_value("註冊失敗", fn {field, [msg | _rest]} ->
      "#{@field_names[field] || field}#{msg}"
    end)
  end
end
