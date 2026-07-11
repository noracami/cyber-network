defmodule GridMaster.Engine.TurnOrderTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine.{Player, TurnOrder}

  defp player(cities, plant_numbers) do
    %Player{
      cities: MapSet.new(Enum.map(1..cities//1, &"c#{&1}")),
      plants: Enum.map(plant_numbers, &%{"number" => &1})
    }
  end

  test "城市多者第一" do
    players = %{"a" => player(2, [10]), "b" => player(3, [5])}
    assert TurnOrder.compute(players, ["a", "b"]) == ["b", "a"]
  end

  test "城市平手比最大卡號" do
    players = %{"a" => player(2, [10, 30]), "b" => player(2, [25])}
    assert TurnOrder.compute(players, ["b", "a"]) == ["a", "b"]
  end

  test "雙平手維持原相對順序" do
    players = %{"a" => player(0, []), "b" => player(0, []), "c" => player(0, [])}
    assert TurnOrder.compute(players, ["c", "a", "b"]) == ["c", "a", "b"]
  end
end
