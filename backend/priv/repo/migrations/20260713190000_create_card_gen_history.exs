defmodule GridMaster.Repo.Migrations.CreateCardGenHistory do
  use Ecto.Migration

  def change do
    # 卡面生成紀錄：一次 image API 呼叫一列（n > 1 時 urls 多值）
    create table(:card_gen_history) do
      add :prompt, :text, null: false
      add :model, :string, null: false
      add :size, :string
      add :n, :integer, null: false, default: 1
      add :tokens, :integer
      add :duration_ms, :integer
      add :urls, {:array, :string}, null: false, default: []
      add :error_msg, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:card_gen_history, [:inserted_at])
  end
end
