defmodule GridMaster.Engine.Setup do
  @moduledoc """
  開局設置：依人數移卡、13 號置頂、Step 3 卡置底、資源市場初始化、
  隨機抽選相鄰叢集、預計算靜態索引。
  """

  alias GridMaster.Data
  alias GridMaster.Engine.{Auction, Player, Shuffle, State}

  @doc """
  建立新牌局。opts:
  - `:seed`（必填）— `:rand.seed_s/2` 的三元組，供整局重放
  - `:active_regions` — 指定啟用叢集（測試用；預設隨機抽相鄰組合）
  """
  @spec new([String.t()], keyword()) :: {State.t(), [tuple()]}
  def new(player_ids, opts) when length(player_ids) in 2..6 do
    rng = :rand.seed_s(:exsss, Keyword.fetch!(opts, :seed))

    map = Data.map()
    deck_data = Data.deck()
    rules = Data.rules()
    config = Map.fetch!(rules["player_counts"], Integer.to_string(length(player_ids)))

    {turn_order, rng} = Shuffle.shuffle(player_ids, rng)

    setup_cfg = deck_data["setup"]
    market = Enum.sort(setup_cfg["initial_market"] ++ setup_cfg["initial_future"])
    top_card = setup_cfg["top_of_deck"]

    rest =
      deck_data["plants"]
      |> Enum.map(& &1["number"])
      |> Kernel.--(market)
      |> List.delete(top_card)

    {shuffled, rng} = Shuffle.shuffle(rest, rng)
    {removed, kept} = Enum.split(shuffled, config["removed_plants"])
    deck = [top_card | kept] ++ [:step3]

    {active_regions, rng} =
      case Keyword.get(opts, :active_regions) do
        nil -> pick_regions(map, config["regions"], rng)
        regions -> {MapSet.new(regions), rng}
      end

    players =
      Map.new(player_ids, fn id ->
        {id, %Player{credits: rules["starting_credits"]}}
      end)

    state = %State{
      step: 1,
      round: 1,
      phase: :auction,
      phase_state: Auction.new(turn_order),
      turn_order: turn_order,
      rng: rng,
      players: players,
      market: market,
      deck: deck,
      removed: removed,
      resource_market: Map.new(rules["resource_market"], fn {r, cfg} -> {r, cfg["initial"]} end),
      city_owners: %{},
      active_regions: active_regions,
      winner: nil,
      round_plants_bought: 0,
      step3_pending: false,
      final_round: false,
      static: build_static(map, deck_data, rules, config, active_regions)
    }

    events = [
      {:game_started,
       %{turn_order: turn_order, active_regions: Enum.sort(active_regions), round: 1}}
    ]

    {state, events}
  end

  @doc """
  還原持久化快照時重建 static——由 Data、人數與 active_regions 決定性導出，
  所以快照不必攜帶這份唯讀數據（GridMaster.Store 序列化前會拆掉它）。
  """
  @spec rebuild_static(State.t()) :: State.t()
  def rebuild_static(%State{} = state) do
    rules = Data.rules()
    config = Map.fetch!(rules["player_counts"], Integer.to_string(map_size(state.players)))

    %{
      state
      | static: build_static(Data.map(), Data.deck(), rules, config, state.active_regions)
    }
  end

  defp build_static(map, deck_data, rules, config, active_regions) do
    city_region = Map.new(map["cities"], &{&1["id"], &1["region"]})
    active_city? = fn city -> MapSet.member?(active_regions, city_region[city]) end

    adjacency =
      Enum.reduce(map["edges"], %{}, fn %{"between" => [a, b], "cost" => cost}, acc ->
        if active_city?.(a) and active_city?.(b) do
          acc
          |> Map.update(a, [{b, cost}], &[{b, cost} | &1])
          |> Map.update(b, [{a, cost}], &[{a, cost} | &1])
        else
          acc
        end
      end)

    %{
      map: map,
      rules: rules,
      config: config,
      plants: Map.new(deck_data["plants"], &{&1["number"], &1}),
      city_region: city_region,
      adjacency: adjacency,
      active_cities:
        map["cities"] |> Enum.map(& &1["id"]) |> Enum.filter(active_city?) |> MapSet.new()
    }
  end

  # 隨機抽選相鄰叢集組合：從隨機起點沿叢集鄰接圖隨機擴張
  defp pick_regions(map, count, rng) do
    city_region = Map.new(map["cities"], &{&1["id"], &1["region"]})

    region_adjacency =
      Enum.reduce(map["edges"], %{}, fn %{"between" => [a, b]}, acc ->
        {ra, rb} = {city_region[a], city_region[b]}

        if ra == rb do
          acc
        else
          acc
          |> Map.update(ra, MapSet.new([rb]), &MapSet.put(&1, rb))
          |> Map.update(rb, MapSet.new([ra]), &MapSet.put(&1, ra))
        end
      end)

    {start, rng} = Shuffle.pick(Enum.map(map["regions"], & &1["id"]), rng)
    grow(MapSet.new([start]), count, region_adjacency, rng)
  end

  defp grow(selected, count, region_adjacency, rng) do
    if MapSet.size(selected) >= count do
      {selected, rng}
    else
      frontier =
        selected
        |> Enum.flat_map(&Map.get(region_adjacency, &1, []))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(selected, &1))

      {next, rng} = Shuffle.pick(frontier, rng)
      grow(MapSet.put(selected, next), count, region_adjacency, rng)
    end
  end
end
