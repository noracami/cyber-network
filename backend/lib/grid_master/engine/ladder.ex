defmodule GridMaster.Engine.Ladder do
  @moduledoc """
  資源價格階梯。

  「買最便宜、補最貴空格」的原版規則保證：已填格永遠是階梯高價端的連續區段，
  因此市場只需存數量（engine-design.md §6.1）。階梯由便宜到貴排列，
  數量為 c 時，最便宜的在庫單位位於 index `total - c`。
  """

  @standard Enum.flat_map(1..8, &List.duplicate(&1, 3))
  @quantum [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16]

  def ladder("quantum"), do: @quantum
  def ladder(_resource), do: @standard

  def capacity(resource), do: length(ladder(resource))

  @doc "買 qty 個（從最便宜起）的總價。存量不足回 :error。"
  @spec cost(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | :error
  def cost(_resource, _count, 0), do: {:ok, 0}

  def cost(resource, count, qty) do
    if qty > count do
      :error
    else
      steps = ladder(resource)
      {:ok, steps |> Enum.slice(length(steps) - count, qty) |> Enum.sum()}
    end
  end

  @doc "目前最便宜單價（空市場回 nil），給 view 層顯示用。"
  def cheapest(_resource, 0), do: nil

  def cheapest(resource, count) do
    steps = ladder(resource)
    Enum.at(steps, length(steps) - count)
  end
end
