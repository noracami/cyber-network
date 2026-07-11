defmodule GridMaster.Engine.Bureaucracy do
  @moduledoc """
  官僚階段：全員同時提交供電選擇，到齊即結算。
  結算序：收入 → 資源補給 → 無人買卡移除 → 低卡淘汰 → 市場輪替 →
  Step 3 待生效處理 → 新回合。終局回合只結算收入後直接排名。
  """

  defstruct submitted: %{}

  alias GridMaster.Engine.{Capacity, Flow, Market}

  def new, do: %__MODULE__{}

  def handle(state, player, payload) do
    %__MODULE__{submitted: submitted} = state.phase_state
    numbers = Map.get(payload, :plants, [])
    target = state.players[player]
    owned = Map.new(target.plants, &{&1["number"], &1})

    cond do
      Map.has_key?(submitted, player) ->
        {:error, :already_submitted}

      not is_list(numbers) ->
        {:error, :invalid_plants}

      numbers != Enum.uniq(numbers) ->
        {:error, :duplicate_plants}

      not Enum.all?(numbers, &Map.has_key?(owned, &1)) ->
        {:error, :plant_not_owned}

      match?(:error, Capacity.burn(target.resources, Enum.map(numbers, &owned[&1]))) ->
        {:error, :insufficient_resources}

      true ->
        submitted = Map.put(submitted, player, numbers)
        state = %{state | phase_state: %__MODULE__{submitted: submitted}}
        events = [{:power_submitted, %{player: player}}]

        if map_size(submitted) == map_size(state.players) do
          resolve(state, events)
        else
          {:ok, state, events}
        end
    end
  end

  defp resolve(state, events) do
    %__MODULE__{submitted: submitted} = state.phase_state
    payout = state.static.rules["payout"]

    {state, power_events, powered_by} =
      Enum.reduce(state.turn_order, {state, [], %{}}, fn id, {st, evs, powered_by} ->
        target = st.players[id]

        plants =
          Enum.map(submitted[id], fn n -> Enum.find(target.plants, &(&1["number"] == n)) end)

        {:ok, remaining} = Capacity.burn(target.resources, plants)

        capacity = plants |> Enum.map(& &1["powers"]) |> Enum.sum()
        powered = min(capacity, MapSet.size(target.cities))
        income = Enum.at(payout, min(powered, 20))

        target = %{target | resources: remaining, credits: target.credits + income}

        {%{st | players: Map.put(st.players, id, target)},
         evs ++
           [{:powered, %{player: id, plants: submitted[id], powered: powered, income: income}}],
         Map.put(powered_by, id, powered)}
      end)

    if state.final_round do
      result = final_ranking(state, powered_by)
      state = %{state | phase: :finished, winner: result}
      {:ok, state, events ++ power_events ++ [{:game_ended, result}]}
    else
      {state, resupply_events} = resupply(state)
      {state, unsold_events} = maybe_remove_unsold(state)
      {state, elimination_events} = Market.eliminate_low(state)
      {state, rotation_events} = Market.rotate(state)
      {state, step3_events} = Flow.maybe_begin_step3(state)
      {state, round_events} = Flow.next_round(state)

      {:ok, state,
       events ++
         power_events ++
         resupply_events ++
         unsold_events ++ elimination_events ++ rotation_events ++ step3_events ++ round_events}
    end
  end

  defp final_ranking(state, powered_by) do
    ranking =
      state.players
      |> Enum.map(fn {id, p} ->
        %{player: id, powered: powered_by[id], credits: p.credits, cities: MapSet.size(p.cities)}
      end)
      |> Enum.sort_by(&{-&1.powered, -&1.credits, -&1.cities})

    %{winner: hd(ranking).player, ranking: ranking}
  end

  defp resupply(state) do
    rules = state.static.rules
    row = rules["resupply"][Integer.to_string(map_size(state.players))]["step#{state.step}"]

    {market, added} =
      rules["resupply_order"]
      |> Enum.zip(row)
      |> Enum.reduce({state.resource_market, %{}}, fn {resource, amount}, {market, added} ->
        held =
          state.players |> Map.values() |> Enum.map(& &1.resources[resource]) |> Enum.sum()

        bank = rules["resource_market"][resource]["total"] - market[resource] - held
        actual = amount |> min(bank) |> max(0)
        {Map.put(market, resource, market[resource] + actual), Map.put(added, resource, actual)}
      end)

    {%{state | resource_market: market}, [{:resupplied, %{amounts: added}}]}
  end

  # 原版：本回合無人買卡 → 移除市場最低卡
  defp maybe_remove_unsold(%{round_plants_bought: 0} = state) do
    case Market.real_plants(state.market) do
      [lowest | _] -> Market.remove_and_replace(state, lowest, :unsold)
      [] -> {state, []}
    end
  end

  defp maybe_remove_unsold(state), do: {state, []}
end
