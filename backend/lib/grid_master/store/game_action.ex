defmodule GridMaster.Store.GameAction do
  @moduledoc "append-only 動作日誌：initial_state 依 seq 重套即可重播任意時間點。"

  use Ecto.Schema

  schema "game_actions" do
    field :game_id, :id
    field :seq, :integer
    field :round, :integer
    field :player_id, :string
    field :action, :string
    field :payload, :map
    field :inserted_at, :utc_datetime_usec
  end
end
