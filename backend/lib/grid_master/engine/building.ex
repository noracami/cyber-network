defmodule GridMaster.Engine.Building do
  @moduledoc "擴建階段：反序輪流，輪到者可連建多城，`build_done` 收手。"

  defstruct queue: []

  alias GridMaster.Engine.{Flow, Graph, Market}

  def new(turn_order), do: %__MODULE__{queue: Enum.reverse(turn_order)}

  def handle(state, player, :build_done, _payload) do
    %__MODULE__{queue: queue} = state.phase_state

    if List.first(queue) != player do
      {:error, :not_your_turn}
    else
      state = %{state | phase_state: %__MODULE__{queue: tl(queue)}}
      events = [{:build_done, %{player: player}}]

      case state.phase_state.queue do
        [] ->
          {state, flow_events} = Flow.end_building(state)
          {:ok, state, events ++ flow_events}

        _ ->
          {:ok, state, events}
      end
    end
  end

  def handle(state, player, :build, payload) do
    %__MODULE__{queue: queue} = state.phase_state
    city = payload[:city]
    owners = Map.get(state.city_owners, city, [])
    target = state.players[player]

    cond do
      List.first(queue) != player ->
        {:error, :not_your_turn}

      not MapSet.member?(state.static.active_cities, city) ->
        {:error, :city_not_active}

      player in owners ->
        {:error, :already_built_here}

      # Step n 開放每城前 n 格（engine-design.md §2）
      length(owners) >= state.step ->
        {:error, :city_full}

      true ->
        case Graph.min_toll(state.static.adjacency, target.cities, city) do
          :unreachable ->
            {:error, :unreachable}

          toll ->
            slot_cost = Enum.at(state.static.rules["city_slot_costs"], length(owners))
            cost = toll + slot_cost

            if target.credits < cost do
              {:error, :insufficient_credits}
            else
              target = %{
                target
                | credits: target.credits - cost,
                  cities: MapSet.put(target.cities, city)
              }

              state = %{
                state
                | players: Map.put(state.players, player, target),
                  city_owners: Map.put(state.city_owners, city, owners ++ [player])
              }

              events = [{:city_built, %{player: player, city: city, cost: cost, toll: toll}}]

              {state, step2_events} = maybe_step2(state, MapSet.size(target.cities))
              {state, elimination_events} = Market.eliminate_low(state)
              {:ok, state, events ++ step2_events ++ elimination_events}
            end
        end
    end
  end

  # Step 2 觸發（原版：擴建中即時生效——移除市場最低卡並補牌）
  defp maybe_step2(%{step: 1} = state, city_count) do
    if city_count >= state.static.config["step2_trigger"] do
      state = %{state | step: 2}

      {state, removal_events} =
        case Market.real_plants(state.market) do
          [lowest | _] -> Market.remove_and_replace(state, lowest, :step2_start)
          [] -> {state, []}
        end

      {state, [{:step_changed, %{step: 2}} | removal_events]}
    else
      {state, []}
    end
  end

  defp maybe_step2(state, _city_count), do: {state, []}
end
