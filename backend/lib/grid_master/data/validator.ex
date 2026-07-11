defmodule GridMaster.Data.Validator do
  @moduledoc """
  靜態遊戲數據的載入期驗證：結構、數量、引用完整性與地圖連通性。

  刻意用 `Map.fetch!` 逐欄取值而非模式匹配過濾——缺欄位的壞數據要炸出
  KeyError，而不是被 comprehension 靜默跳過。
  """

  @plant_types ~w(hydro thermal waste quantum hybrid self fusion)
  @no_fuel_types ~w(self fusion)
  @resources ~w(hydro thermal waste quantum)
  @player_counts ~w(2 3 4 5 6)

  @spec validate!(:map | :deck | :rules, map()) :: :ok
  def validate!(kind, data)

  def validate!(:map, data) do
    regions = Map.fetch!(data, "regions")
    cities = Map.fetch!(data, "cities")
    edges = Map.fetch!(data, "edges")

    check!(length(cities) == 42, "地圖應有 42 城，實際 #{length(cities)}")
    check!(length(edges) == 87, "地圖應有 87 條連線，實際 #{length(edges)}")

    city_ids = MapSet.new(cities, &Map.fetch!(&1, "id"))
    check!(MapSet.size(city_ids) == length(cities), "城市 id 重複")

    region_ids = MapSet.new(regions, &Map.fetch!(&1, "id"))

    Enum.each(cities, fn city ->
      id = Map.fetch!(city, "id")
      region = Map.fetch!(city, "region")
      %{"x" => x, "y" => y} = Map.fetch!(city, "pos")

      check!(region in region_ids, "城市 #{id} 的叢集 #{region} 不存在")
      check!(is_number(x) and is_number(y), "城市 #{id} 座標非法")
    end)

    Enum.each(region_ids, fn region_id ->
      count = Enum.count(cities, &(Map.fetch!(&1, "region") == region_id))
      check!(count == 7, "叢集 #{region_id} 應有 7 城，實際 #{count}")
    end)

    pairs =
      Enum.map(edges, fn edge ->
        [a, b] = Map.fetch!(edge, "between")
        cost = Map.fetch!(edge, "cost")

        check!(a in city_ids, "連線端點 #{a} 不存在")
        check!(b in city_ids, "連線端點 #{b} 不存在")
        check!(a != b, "連線 #{a} 自成迴圈")
        check!(is_integer(cost) and cost >= 0, "連線 #{a}-#{b} 費用非法：#{inspect(cost)}")

        [a, b] |> Enum.sort() |> List.to_tuple()
      end)

    check!(pairs == Enum.uniq(pairs), "存在重複連線")
    check!(connected?(city_ids, edges), "地圖不連通")
    :ok
  end

  def validate!(:deck, data) do
    plants = Map.fetch!(data, "plants")
    setup = Map.fetch!(data, "setup")

    check!(length(plants) == 42, "牌庫應有 42 張設施卡，實際 #{length(plants)}")

    numbers = Enum.map(plants, &Map.fetch!(&1, "number"))
    check!(numbers == Enum.uniq(numbers), "卡號重複")

    Enum.each(plants, fn plant ->
      number = Map.fetch!(plant, "number")
      type = Map.fetch!(plant, "type")
      fuel = Map.fetch!(plant, "fuel")
      powers = Map.fetch!(plant, "powers")
      name = Map.fetch!(plant, "name")

      check!(is_integer(number) and number >= 1, "卡號非法：#{inspect(number)}")
      check!(type in @plant_types, "#{number} 號卡類型非法：#{type}")
      check!(is_integer(fuel) and fuel >= 0, "#{number} 號卡燃料數非法")
      check!(is_integer(powers) and powers >= 1, "#{number} 號卡供電數非法")
      check!(fuel == 0 == type in @no_fuel_types, "#{number} 號卡燃料數與類型矛盾（#{type}／#{fuel}）")
      check!(is_binary(name) and name != "", "#{number} 號卡缺卡名")
    end)

    number_set = MapSet.new(numbers)
    initial_market = Map.fetch!(setup, "initial_market")
    initial_future = Map.fetch!(setup, "initial_future")
    top_of_deck = Map.fetch!(setup, "top_of_deck")

    Enum.each(initial_market ++ initial_future ++ [top_of_deck], fn n ->
      check!(n in number_set, "牌庫設置引用不存在的卡號 #{n}")
    end)

    check!(top_of_deck not in (initial_market ++ initial_future), "置頂卡不能同時在初始市場")
    check!(Map.fetch!(setup, "step3_at_bottom") == true, "setup.step3_at_bottom 應為 true")
    :ok
  end

  def validate!(:rules, rules) do
    starting_credits = Map.fetch!(rules, "starting_credits")
    check!(is_integer(starting_credits) and starting_credits > 0, "starting_credits 非法")

    slot_costs = Map.fetch!(rules, "city_slot_costs")

    check!(
      length(slot_costs) == 3 and Enum.all?(slot_costs, &is_integer/1),
      "city_slot_costs 應為 3 階整數"
    )

    payout = Map.fetch!(rules, "payout")
    check!(length(payout) == 21, "payout 表應有 21 格（供電 0–20 城），實際 #{length(payout)}")
    check!(payout == Enum.sort(payout), "payout 表應遞增")

    market = Map.fetch!(rules, "resource_market")
    check!(Enum.sort(Map.keys(market)) == Enum.sort(@resources), "resource_market 應恰含四種資源")

    Enum.each(market, fn {resource, cfg} ->
      total = Map.fetch!(cfg, "total")
      initial = Map.fetch!(cfg, "initial")

      check!(
        is_integer(total) and is_integer(initial) and initial in 0..total,
        "#{resource} 市場 initial/total 非法"
      )
    end)

    check!(
      Map.fetch!(rules, "resupply_order") == @resources,
      "resupply_order 應為 #{inspect(@resources)}"
    )

    resupply = Map.fetch!(rules, "resupply")
    check!(Enum.sort(Map.keys(resupply)) == @player_counts, "resupply 應涵蓋 2–6 人")

    Enum.each(resupply, fn {players, steps} ->
      Enum.each(~w(step1 step2 step3), fn step ->
        row = Map.fetch!(steps, step)

        check!(
          length(row) == 4 and Enum.all?(row, &(is_integer(&1) and &1 >= 0)),
          "resupply #{players} 人 #{step} 格式非法"
        )
      end)
    end)

    player_counts = Map.fetch!(rules, "player_counts")
    check!(Enum.sort(Map.keys(player_counts)) == @player_counts, "player_counts 應涵蓋 2–6 人")

    Enum.each(player_counts, fn {players, cfg} ->
      Enum.each(~w(regions removed_plants max_plants step2_trigger game_end), fn key ->
        value = Map.fetch!(cfg, key)
        check!(is_integer(value) and value >= 0, "player_counts #{players} 人 #{key} 非法")
      end)
    end)

    :ok
  end

  defp connected?(city_ids, edges) do
    adjacency =
      Enum.reduce(edges, %{}, fn edge, acc ->
        [a, b] = Map.fetch!(edge, "between")

        acc
        |> Map.update(a, [b], &[b | &1])
        |> Map.update(b, [a], &[a | &1])
      end)

    start = Enum.at(city_ids, 0)
    reachable = bfs([start], MapSet.new([start]), adjacency)
    MapSet.size(reachable) == MapSet.size(city_ids)
  end

  defp bfs([], visited, _adjacency), do: visited

  defp bfs([node | rest], visited, adjacency) do
    discovered =
      adjacency
      |> Map.get(node, [])
      |> Enum.uniq()
      |> Enum.reject(&(&1 in visited))

    bfs(rest ++ discovered, MapSet.union(visited, MapSet.new(discovered)), adjacency)
  end

  defp check!(true, _message), do: :ok
  defp check!(false, message), do: raise(ArgumentError, "遊戲數據驗證失敗：" <> message)
end
