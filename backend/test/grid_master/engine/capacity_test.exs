defmodule GridMaster.Engine.CapacityTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine.Capacity

  defp res(hydro, thermal, waste \\ 0, quantum \\ 0) do
    %{"hydro" => hydro, "thermal" => thermal, "waste" => waste, "quantum" => quantum}
  end

  defp plant(type, fuel), do: %{"type" => type, "fuel" => fuel}

  test "容量 = 燃料需求 ×2；hybrid 彈性容量" do
    caps = Capacity.caps([plant("hydro", 2), plant("hybrid", 2), plant("self", 0)])
    assert caps == %{hydro: 4, thermal: 0, waste: 0, quantum: 0, hybrid: 4}

    # hybrid 容量可裝水力或火力
    assert Capacity.fits?(caps, res(8, 0))
    assert Capacity.fits?(caps, res(4, 4))
    refute Capacity.fits?(caps, res(4, 5))
    refute Capacity.fits?(caps, res(9, 0))
  end

  test "trim 依「先丟便宜」修剪超量資源" do
    caps = Capacity.caps([plant("waste", 1)])
    trimmed = Capacity.trim(caps, res(3, 0, 2, 0))
    assert trimmed == res(0, 0, 2, 0)
  end

  test "burn：hybrid 先燒水力再燒火力" do
    assert {:ok, after_burn} = Capacity.burn(res(1, 2), [plant("hybrid", 2)])
    assert after_burn == res(0, 1)
  end

  test "burn：資源不足回 :error" do
    assert :error = Capacity.burn(res(0, 0, 1, 0), [plant("waste", 2)])
    assert :error = Capacity.burn(res(1, 0), [plant("hybrid", 2), plant("hydro", 2)])
  end

  test "burn：免燃料設施不耗資源" do
    assert {:ok, unchanged} = Capacity.burn(res(1, 1), [plant("self", 0), plant("fusion", 0)])
    assert unchanged == res(1, 1)
  end
end
