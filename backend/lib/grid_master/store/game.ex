defmodule GridMaster.Store.Game do
  @moduledoc """
  對局紀錄：開局即建列，自然完局補名次結果，中途結束補 `aborted_at`。
  戰績查詢以 `finished_at IS NOT NULL` 過濾；玩家名字存當時顯示值，
  不外鍵 accounts（訪客與 NPC 沒有帳號列）。
  """

  use Ecto.Schema

  schema "games" do
    field :room_id, :string
    field :map, :string
    field :version, :integer
    field :initial_state, :binary
    field :players, {:array, :map}
    field :winner_id, :string
    field :winner_name, :string
    field :rounds, :integer
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :aborted_at, :utc_datetime_usec
  end
end
