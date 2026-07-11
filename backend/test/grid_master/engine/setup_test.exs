defmodule GridMaster.Engine.SetupTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine

  import GridMaster.EngineHelpers

  test "開局結構正確（3 人局）" do
    {state, events} = new_game(["p1", "p2", "p3"])

    assert state.step == 1
    assert state.round == 1
    assert state.phase == :auction
    assert state.market == [3, 4, 5, 6, 7, 8, 9, 10]

    # 42 張 − 市場 8 − 依人數移除 8 = 26 張實卡在牌庫（13 號在頂）＋ step3 標記
    assert Enum.count(state.deck, &is_integer/1) == 26
    assert hd(state.deck) == 13
    assert List.last(state.deck) == :step3
    assert length(state.removed) == 8
    assert Enum.all?(Map.values(state.players), &(&1.credits == 50))

    assert state.resource_market == %{
             "hydro" => 24,
             "thermal" => 18,
             "waste" => 6,
             "quantum" => 2
           }

    assert {:game_started, _} = List.keyfind(events, :game_started, 0)
  end

  test "同 seed 完全可重現" do
    {a, _} = Engine.new(["p1", "p2"], seed: {7, 7, 7})
    {b, _} = Engine.new(["p1", "p2"], seed: {7, 7, 7})
    assert a == b
  end

  test "不同 seed 產生不同洗牌" do
    {a, _} = Engine.new(["p1", "p2"], seed: {1, 1, 1})
    {b, _} = Engine.new(["p1", "p2"], seed: {9, 9, 9})
    refute a.deck == b.deck
  end

  test "未指定叢集時依人數隨機抽相鄰組合" do
    {state, _} = Engine.new(["p1", "p2", "p3", "p4"], seed: {5, 5, 5})
    assert MapSet.size(state.active_regions) == 4

    # 相鄰性：啟用叢集構成連通子圖（沿叢集鄰接邊 BFS 可達全部）
    map = GridMaster.Data.map()
    city_region = Map.new(map["cities"], &{&1["id"], &1["region"]})

    region_adjacency =
      Enum.reduce(map["edges"], %{}, fn %{"between" => [a, b]}, acc ->
        {ra, rb} = {city_region[a], city_region[b]}

        if ra == rb or not MapSet.member?(state.active_regions, ra) or
             not MapSet.member?(state.active_regions, rb) do
          acc
        else
          acc
          |> Map.update(ra, [rb], &[rb | &1])
          |> Map.update(rb, [ra], &[ra | &1])
        end
      end)

    start = Enum.at(state.active_regions, 0)
    reachable = bfs([start], MapSet.new([start]), region_adjacency)
    assert reachable == state.active_regions
  end

  test "鄰接表只含啟用叢集的城市" do
    {state, _} = new_game(["p1", "p2"], active_regions: ~w(nw sw))
    assert MapSet.size(state.static.active_cities) == 14
    refute Map.has_key?(state.static.adjacency, "miami")
    assert Map.has_key?(state.static.adjacency, "seattle")
  end

  defp bfs([], visited, _adj), do: visited

  defp bfs([node | rest], visited, adj) do
    discovered = adj |> Map.get(node, []) |> Enum.uniq() |> Enum.reject(&(&1 in visited))
    bfs(rest ++ discovered, MapSet.union(visited, MapSet.new(discovered)), adj)
  end
end
