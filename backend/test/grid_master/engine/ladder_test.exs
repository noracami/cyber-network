defmodule GridMaster.Engine.LadderTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine.Ladder

  test "滿市場的水力最便宜是 $1" do
    assert Ladder.cheapest("hydro", 24) == 1
    assert {:ok, 5} = Ladder.cost("hydro", 24, 4)
  end

  test "火力初始 18 個，最便宜 $3" do
    assert Ladder.cheapest("thermal", 18) == 3
    assert {:ok, 3} = Ladder.cost("thermal", 18, 1)
    assert {:ok, 6} = Ladder.cost("thermal", 18, 2)
  end

  test "廢料初始 6 個，自 $7 起" do
    assert Ladder.cheapest("waste", 6) == 7
    assert Ladder.cost("waste", 6, 4) == {:ok, 7 + 7 + 7 + 8}
  end

  test "算力用專屬階梯，初始 2 個在 $14、$16" do
    assert Ladder.cheapest("quantum", 2) == 14
    assert {:ok, 30} = Ladder.cost("quantum", 2, 2)
    assert Ladder.capacity("quantum") == 12
  end

  test "存量不足回 :error；買 0 個免費" do
    assert :error = Ladder.cost("waste", 6, 7)
    assert {:ok, 0} = Ladder.cost("waste", 6, 0)
    assert Ladder.cheapest("hydro", 0) == nil
  end
end
