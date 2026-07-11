defmodule GridMaster.Engine.TurnOrder do
  @moduledoc """
  順位計算：城市多者前；平手比手上最大卡號。
  雙平手（僅開局前可能）保持前一順位的相對順序（穩定排序）。
  """

  @spec compute(map(), [String.t()]) :: [String.t()]
  def compute(players, previous_order) do
    previous_index = previous_order |> Enum.with_index() |> Map.new()

    players
    |> Map.keys()
    |> Enum.sort_by(fn id ->
      player = players[id]
      {-MapSet.size(player.cities), -max_plant(player), previous_index[id]}
    end)
  end

  defp max_plant(%{plants: []}), do: 0
  defp max_plant(player), do: player.plants |> Enum.map(& &1["number"]) |> Enum.max()
end
