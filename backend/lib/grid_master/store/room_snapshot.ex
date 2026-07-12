defmodule GridMaster.Store.RoomSnapshot do
  @moduledoc "一房一列的房間續局快照（term_to_binary payload）。"

  use Ecto.Schema

  @primary_key {:room_id, :string, autogenerate: false}
  schema "room_snapshots" do
    field :version, :integer
    field :payload, :binary
    field :updated_at, :utc_datetime_usec
  end
end
