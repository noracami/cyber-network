defmodule GridMaster.Accounts do
  @moduledoc """
  測試用輕量帳號（PRD-v1.1 R6）——無 email、無驗證信、無密碼找回。
  這是 Postgres 首次真正承載的功能；遊戲狀態仍全在 GenServer 記憶體。
  """

  import Ecto.Query

  alias GridMaster.Accounts.Account
  alias GridMaster.Repo

  @doc "註冊；成功即視同登入。"
  def register(attrs) do
    %Account{}
    |> Account.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "帳密驗證。帳號不存在時仍跑一次假雜湊，避免時間差洩漏帳號存在性。"
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    account = get_by_username(username)

    if account && Argon2.verify_pass(password, account.password_hash) do
      {:ok, account}
    else
      unless account, do: Argon2.no_user_verify()
      :error
    end
  end

  def authenticate(_username, _password), do: :error

  defp get_by_username(username) do
    downcased = String.downcase(username)
    Repo.one(from a in Account, where: fragment("lower(?)", a.username) == ^downcased)
  end
end
