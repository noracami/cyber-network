defmodule GridMaster.Engine.Market do
  @moduledoc """
  卡牌市場操作：補牌、排序、輪替、淘汰。
  `:step3` 原子代表 Step 3 卡，排序永遠最大、不可購買、不參與輪替。
  """

  alias GridMaster.Engine.Shuffle

  def sort(market), do: Enum.sort_by(market, &sort_key/1)

  defp sort_key(:step3), do: 1_000
  defp sort_key(number), do: number

  @doc "可競標的卡：Step 1/2 取實卡最低 4 張（現行市場）；Step 3 全部實卡。"
  def purchasable(state) do
    real = real_plants(state.market)
    if state.step == 3, do: real, else: Enum.take(real, 4)
  end

  def real_plants(market), do: Enum.reject(market, &(&1 == :step3))

  @doc "從牌庫補一張進市場。抽到 Step 3 卡：置入市場、重洗剩餘牌庫、標記 pending。"
  def draw(state) do
    case state.deck do
      [] ->
        {state, []}

      [:step3 | rest] ->
        {shuffled, rng} = Shuffle.shuffle(rest, state.rng)

        state = %{
          state
          | deck: shuffled,
            rng: rng,
            market: sort([:step3 | state.market]),
            step3_pending: true
        }

        {state, [{:step3_revealed, %{}}]}

      [card | rest] ->
        {%{state | deck: rest, market: sort([card | state.market])}, []}
    end
  end

  @doc "移除市場一張卡（進 removed）並從牌庫補一張。"
  def remove_and_replace(state, plant, reason) do
    state = %{state | market: List.delete(state.market, plant), removed: [plant | state.removed]}
    {state, events} = draw(state)
    {state, [{:plant_removed, %{plant: plant, reason: reason}} | events]}
  end

  @doc "取走被買下的卡並補牌（不進 removed）。"
  def take_bought(state, plant) do
    state = %{state | market: List.delete(state.market, plant)}
    draw(state)
  end

  @doc "淘汰卡號 ≤ 全場最大城市數的卡（原版持續規則，於擴建後與官僚階段檢查）。"
  def eliminate_low(state) do
    max_cities =
      state.players |> Map.values() |> Enum.map(&MapSet.size(&1.cities)) |> Enum.max(fn -> 0 end)

    do_eliminate(state, max_cities, [])
  end

  defp do_eliminate(state, max_cities, events) do
    case real_plants(state.market) do
      [lowest | _] when lowest <= max_cities ->
        {state, new_events} = remove_and_replace(state, lowest, :city_count)
        do_eliminate(state, max_cities, events ++ new_events)

      _ ->
        {state, events}
    end
  end

  @doc """
  官僚階段市場輪替。
  Step 1/2：最高實卡收進牌庫最底（原版：塞到 Step 3 卡之下），補牌。
  Step 3：移除最低實卡（出局），補牌。
  """
  def rotate(%{deck: []} = state), do: {state, []}

  def rotate(%{step: 3} = state) do
    case real_plants(state.market) do
      [lowest | _] -> remove_and_replace(state, lowest, :rotation)
      [] -> {state, []}
    end
  end

  def rotate(state) do
    case real_plants(state.market) |> List.last() do
      nil ->
        {state, []}

      highest ->
        state = %{
          state
          | market: List.delete(state.market, highest),
            deck: state.deck ++ [highest]
        }

        {state, events} = draw(state)
        {state, [{:plant_tucked, %{plant: highest}} | events]}
    end
  end

  @doc "Step 3 正式開始：移除 Step 3 卡與最低實卡，市場縮為 6 張全可競標。"
  def begin_step3(state) do
    state = %{state | market: List.delete(state.market, :step3), step3_pending: false, step: 3}

    {state, events} =
      case real_plants(state.market) do
        [lowest | _] -> remove_and_replace(state, lowest, :step3_start)
        [] -> {state, []}
      end

    {state, [{:step_changed, %{step: 3}} | events]}
  end
end
