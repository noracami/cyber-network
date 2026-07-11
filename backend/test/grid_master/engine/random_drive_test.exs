defmodule GridMaster.Engine.RandomDriveTest do
  @moduledoc """
  隨機合法動作驅動測試：以固定 seed 隨機打牌，逐步驗證守恆不變量。
  不要求隨機玩家能打完整局（有步數上限），但每一步後狀態必須合法。
  """

  use ExUnit.Case, async: true

  alias GridMaster.Engine
  alias GridMaster.Engine.Shuffle

  @resources ~w(hydro thermal waste quantum)
  @max_steps 4000

  @tag timeout: 120_000
  test "2 人局隨機驅動不變量" do
    for seed <- [{1, 1, 1}, {2, 2, 2}, {3, 3, 3}], do: run(["p1", "p2"], seed)
  end

  @tag timeout: 120_000
  test "4 人局隨機驅動不變量" do
    run(["p1", "p2", "p3", "p4"], {8, 8, 8})
  end

  defp run(players, seed) do
    {state, _} = Engine.new(players, seed: seed)
    final = drive(state, :rand.seed_s(:exsss, seed), 0)

    # 隨機局必須有實質推進：至少進入第 3 回合或直接打完
    assert final.phase == :finished or final.round >= 3,
           "隨機局沒有推進：round=#{final.round} phase=#{final.phase}"
  end

  defp drive(%{phase: :finished} = state, _rng, _step), do: state
  defp drive(state, _rng, @max_steps), do: state

  defp drive(state, rng, step) do
    candidates = candidates(state)
    assert candidates != [], "卡死於 #{state.phase}（第 #{step} 步）"

    {shuffled, rng} = Shuffle.shuffle(candidates, rng)
    state = try_candidates(state, shuffled)
    check_invariants(state)
    drive(state, rng, step + 1)
  end

  defp try_candidates(state, []) do
    flunk("所有候選動作都失敗於 #{state.phase}")
  end

  defp try_candidates(state, [{player, action} | rest]) do
    case Engine.apply_action(state, player, action) do
      {:ok, new_state, _events} -> new_state
      {:error, _reason} -> try_candidates(state, rest)
    end
  end

  # --- 候選動作產生 ---

  defp candidates(%{phase: :auction} = state) do
    auction = state.phase_state

    cond do
      auction.pending_discard != nil ->
        %{player: player, new_plant: new_plant} = auction.pending_discard

        state.players[player].plants
        |> Enum.map(& &1["number"])
        |> Enum.reject(&(&1 == new_plant))
        |> Enum.map(&{player, {:auction_discard, %{plant: &1}}})

      auction.bidding != nil ->
        turn = auction.bidding.turn

        [
          {turn, {:auction_fold, %{}}},
          {turn, {:auction_bid, %{amount: auction.bidding.price + 1}}}
        ]

      true ->
        head = List.first(auction.queue)

        chooses =
          state
          |> GridMaster.Engine.Market.purchasable()
          |> Enum.map(&{head, {:auction_choose, %{plant: &1, bid: &1}}})

        chooses ++ [{head, {:auction_pass, %{}}}]
    end
  end

  defp candidates(%{phase: :resources} = state) do
    head = List.first(state.phase_state.queue)

    buys =
      for r <- @resources do
        {head, {:resources_buy, Map.new([{String.to_existing_atom(r), 1}])}}
      end

    buys ++ [{head, {:resources_buy, %{}}}]
  end

  defp candidates(%{phase: :building} = state) do
    head = List.first(state.phase_state.queue)

    builds =
      state.static.active_cities
      |> Enum.take(12)
      |> Enum.map(&{head, {:build, %{city: &1}}})

    # 偏向擴建，讓隨機局有機會推進大局
    builds ++ builds ++ [{head, {:build_done, %{}}}]
  end

  defp candidates(%{phase: :bureaucracy} = state) do
    pending = Map.keys(state.players) -- Map.keys(state.phase_state.submitted)

    Enum.flat_map(pending, fn player ->
      all = Enum.map(state.players[player].plants, & &1["number"])
      [{player, {:power_submit, %{plants: all}}}, {player, {:power_submit, %{plants: []}}}]
    end)
  end

  # --- 不變量 ---

  defp check_invariants(state) do
    for resource <- @resources do
      held =
        state.players |> Map.values() |> Enum.map(& &1.resources[resource]) |> Enum.sum()

      total = state.static.rules["resource_market"][resource]["total"]
      market = state.resource_market[resource]

      assert market >= 0, "#{resource} 市場為負"
      assert market + held <= total, "#{resource} 超過總量：市場 #{market}＋持有 #{held}"
    end

    in_market = Enum.count(state.market, &is_integer/1)
    in_deck = Enum.count(state.deck, &is_integer/1)
    owned = state.players |> Map.values() |> Enum.map(&length(&1.plants)) |> Enum.sum()
    total_plants = in_market + in_deck + length(state.removed) + owned
    assert total_plants == 42, "卡片守恆破壞：#{total_plants} != 42"

    for {id, player} <- state.players do
      assert player.credits >= 0, "#{id} 金錢為負"
    end

    for {city, owners} <- state.city_owners do
      assert length(owners) <= state.step, "#{city} 佔據數超過 Step 上限"
      assert length(owners) == length(Enum.uniq(owners)), "#{city} 重複佔據"
    end
  end
end
