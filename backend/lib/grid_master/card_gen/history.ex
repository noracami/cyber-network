defmodule GridMaster.CardGen.History do
  @moduledoc "卡面生成紀錄——一次 image API 呼叫一列。"

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "card_gen_history" do
    field :prompt, :string
    field :model, :string
    field :size, :string
    field :n, :integer, default: 1
    field :tokens, :integer
    field :duration_ms, :integer
    field :urls, {:array, :string}, default: []
    field :error_msg, :string
    field :status, :string, default: "pending"
    field :batch_id, :string
    timestamps()
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [
      :prompt,
      :model,
      :size,
      :n,
      :tokens,
      :duration_ms,
      :urls,
      :error_msg,
      :status,
      :batch_id
    ])
    |> validate_required([:prompt, :model, :status])
    |> validate_inclusion(:status, ["pending", "completed", "failed"])
    |> validate_length(:prompt, max: 10_000)
  end
end
