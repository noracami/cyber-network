defmodule GridMaster.Engine.Shuffle do
  @moduledoc "以顯式 :rand 狀態進行的可重放洗牌／抽選。"

  @spec shuffle(list(), :rand.state()) :: {list(), :rand.state()}
  def shuffle(list, rng), do: do_shuffle(list, [], rng)

  defp do_shuffle([], acc, rng), do: {acc, rng}

  defp do_shuffle(list, acc, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {item, rest} = List.pop_at(list, i - 1)
    do_shuffle(rest, [item | acc], rng)
  end

  @spec pick(nonempty_list(), :rand.state()) :: {term(), :rand.state()}
  def pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end
end
