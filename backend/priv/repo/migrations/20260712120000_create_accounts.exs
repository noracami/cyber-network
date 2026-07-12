defmodule GridMaster.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :username, :string, null: false
      add :password_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # 帳號不分大小寫唯一（保留使用者輸入的原始大小寫顯示）
    create unique_index(:accounts, ["lower(username)"], name: :accounts_username_lower_index)
  end
end
