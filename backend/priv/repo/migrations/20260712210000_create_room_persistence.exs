defmodule GridMaster.Repo.Migrations.CreateRoomPersistence do
  use Ecto.Migration

  def change do
    # 一房一列的續局快照：每次動作後整份覆寫
    create table(:room_snapshots, primary_key: false) do
      add :room_id, :string, primary_key: true
      add :version, :integer, null: false
      add :payload, :binary, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    # 對局表：開局建列（initial_state 為重播起點），完局補名次、中止補 aborted_at
    create table(:games) do
      add :room_id, :string, null: false
      add :map, :string, null: false
      add :version, :integer, null: false
      add :initial_state, :binary, null: false
      add :players, {:array, :map}
      add :winner_id, :string
      add :winner_name, :string
      add :rounds, :integer
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :aborted_at, :utc_datetime_usec
    end

    create index(:games, [:room_id])

    # append-only 動作日誌：initial_state 依序重套 seq 即可重播
    create table(:game_actions) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :seq, :integer, null: false
      add :round, :integer
      add :player_id, :string, null: false
      add :action, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:game_actions, [:game_id, :seq])
  end
end
