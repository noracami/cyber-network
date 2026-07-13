defmodule GridMaster.Repo.Migrations.CardGenBatch do
  use Ecto.Migration

  def change do
    alter table(:card_gen_history) do
      # pending → completed / failed;既有列都是同步時代的完成品
      add :status, :string, null: false, default: "completed"
      add :batch_id, :string
    end

    create index(:card_gen_history, [:status])
  end
end
