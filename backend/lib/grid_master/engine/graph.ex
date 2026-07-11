defmodule GridMaster.Engine.Graph do
  @moduledoc """
  地圖圖論運算。鄰接表已在 setup 時依啟用叢集過濾——
  未啟用叢集的城市不可建、也不可借道（原版規則）。
  """

  @doc """
  多源 Dijkstra：玩家已佔網路（sources，成本 0）到 target 的最低過路費和。
  無城市時首城免過路費（回 0）。
  """
  @spec min_toll(map(), Enumerable.t(), String.t()) :: non_neg_integer() | :unreachable
  def min_toll(adjacency, sources, target) do
    if Enum.empty?(sources) do
      0
    else
      queue = Enum.reduce(sources, :gb_sets.empty(), &:gb_sets.add({0, &1}, &2))
      dijkstra(queue, MapSet.new(), adjacency, target)
    end
  end

  defp dijkstra(queue, done, adjacency, target) do
    if :gb_sets.is_empty(queue) do
      :unreachable
    else
      {{dist, node}, queue} = :gb_sets.take_smallest(queue)

      cond do
        node == target ->
          dist

        MapSet.member?(done, node) ->
          dijkstra(queue, done, adjacency, target)

        true ->
          done = MapSet.put(done, node)

          queue =
            Enum.reduce(Map.get(adjacency, node, []), queue, fn {neighbor, cost}, q ->
              if MapSet.member?(done, neighbor),
                do: q,
                else: :gb_sets.add({dist + cost, neighbor}, q)
            end)

          dijkstra(queue, done, adjacency, target)
      end
    end
  end
end
