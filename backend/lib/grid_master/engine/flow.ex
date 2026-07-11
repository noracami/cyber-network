defmodule GridMaster.Engine.Flow do
  @moduledoc """
  跨階段流轉。每個階段結束時檢查 Step 3 是否待生效
  （原版：Step 3 卡於「被抽出的那個階段」結束時生效）。
  """

  alias GridMaster.Engine.{Auction, Building, Bureaucracy, Market, Resources, TurnOrder}

  def end_auction(state) do
    # 第 1 回合特規：競標結束後立即以卡號重算順位
    {state, order_events} =
      if state.round == 1 do
        order = TurnOrder.compute(state.players, state.turn_order)
        {%{state | turn_order: order}, [{:turn_order_changed, %{turn_order: order}}]}
      else
        {state, []}
      end

    {state, step3_events} = maybe_begin_step3(state)
    state = %{state | phase: :resources, phase_state: Resources.new(state.turn_order)}
    {state, order_events ++ step3_events ++ [{:phase_changed, %{phase: :resources}}]}
  end

  def end_resources(state) do
    {state, step3_events} = maybe_begin_step3(state)
    state = %{state | phase: :building, phase_state: Building.new(state.turn_order)}
    {state, step3_events ++ [{:phase_changed, %{phase: :building}}]}
  end

  def end_building(state) do
    max_cities =
      state.players |> Map.values() |> Enum.map(&MapSet.size(&1.cities)) |> Enum.max()

    final? = max_cities >= state.static.config["game_end"]
    state = %{state | final_round: final?}

    {state, step3_events} = maybe_begin_step3(state)
    state = %{state | phase: :bureaucracy, phase_state: Bureaucracy.new()}

    events =
      step3_events ++
        [{:phase_changed, %{phase: :bureaucracy}}] ++
        if final?, do: [{:final_round, %{}}], else: []

    {state, events}
  end

  def next_round(state) do
    order = TurnOrder.compute(state.players, state.turn_order)

    state = %{
      state
      | round: state.round + 1,
        round_plants_bought: 0,
        turn_order: order,
        phase: :auction,
        phase_state: Auction.new(order)
    }

    {state,
     [
       {:round_started, %{round: state.round, turn_order: order}},
       {:phase_changed, %{phase: :auction}}
     ]}
  end

  def maybe_begin_step3(%{step3_pending: true, step: step} = state) when step < 3,
    do: Market.begin_step3(state)

  def maybe_begin_step3(state), do: {state, []}
end
