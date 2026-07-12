defmodule GridMaster.Accounts.Account do
  @moduledoc """
  測試用輕量帳號（PRD-v1.1 R6）。規則定案（2026-07-12）：
  帳號純英數 3–20 字（不用 email、禁符號）、密碼至少 4 字。
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password], message: "必填")
    |> validate_format(:username, ~r/\A[a-zA-Z0-9]{3,20}\z/, message: "須為 3–20 個英數字元")
    |> validate_length(:password, min: 4, max: 72, message: "長度須為 4–72 個字元")
    |> unique_constraint(:username, name: :accounts_username_lower_index, message: "已被使用")
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if changeset.valid? and is_binary(password) do
      changeset
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
