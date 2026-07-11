defmodule GridMaster.Engine.GraphTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine.Graph

  #   a --3-- b --4-- c
  #    \------10-----/
  @adjacency %{
    "a" => [{"b", 3}, {"c", 10}],
    "b" => [{"a", 3}, {"c", 4}],
    "c" => [{"b", 4}, {"a", 10}],
    "d" => []
  }

  test "首城免過路費" do
    assert Graph.min_toll(@adjacency, [], "c") == 0
  end

  test "取最低費用路徑而非最少邊數" do
    assert Graph.min_toll(@adjacency, ["a"], "c") == 7
  end

  test "多源取最近者" do
    assert Graph.min_toll(@adjacency, ["a", "b"], "c") == 4
  end

  test "不連通回 :unreachable" do
    assert Graph.min_toll(@adjacency, ["a"], "d") == :unreachable
  end

  test "真實地圖抽查：Seattle 網路到 Boise" do
    {state, _} = GridMaster.EngineHelpers.new_game(["p1", "p2"])
    # 直連 12 vs 繞 Portland 3+13=16 → 12
    assert Graph.min_toll(state.static.adjacency, ["seattle"], "boise") == 12
    # 加入 Salt Lake City 後走 SLC–Boise 8
    assert Graph.min_toll(state.static.adjacency, ["seattle", "salt_lake_city"], "boise") == 8
  end
end
