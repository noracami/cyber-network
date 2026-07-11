defmodule GridMaster.Engine.Resources do
  @moduledoc "買資源階段：反序輪流，一次提交整批採購（全 0 即棄買）。"

  defstruct queue: []

  alias GridMaster.Engine.{Capacity, Flow, Ladder}

  @resources ~w(hydro thermal waste quantum)

  def new(turn_order), do: %__MODULE__{queue: Enum.reverse(turn_order)}

  def handle(state, player, payload) do
    %__MODULE__{queue: queue} = state.phase_state

    cond do
      List.first(queue) != player ->
        {:error, :not_your_turn}

      true ->
        case normalize(payload) do
          :error -> {:error, :invalid_quantities}
          quantities -> buy(state, player, quantities)
        end
    end
  end

  defp buy(state, player, quantities) do
    target = state.players[player]

    with {:ok, cost} <- total_cost(state.resource_market, quantities),
         :ok <- affordable(target, cost),
         {:ok, new_resources} <- store(target, quantities) do
      target = %{target | credits: target.credits - cost, resources: new_resources}

      market =
        Map.new(@resources, fn r -> {r, state.resource_market[r] - quantities[r]} end)

      state = %{
        state
        | players: Map.put(state.players, player, target),
          resource_market: market,
          phase_state: %__MODULE__{queue: tl(state.phase_state.queue)}
      }

      events =
        if Enum.all?(@resources, &(quantities[&1] == 0)) do
          [{:resources_skipped, %{player: player}}]
        else
          [{:resources_bought, %{player: player, quantities: quantities, cost: cost}}]
        end

      case state.phase_state.queue do
        [] ->
          {state, flow_events} = Flow.end_resources(state)
          {:ok, state, events ++ flow_events}

        _ ->
          {:ok, state, events}
      end
    end
  end

  defp normalize(payload) do
    quantities =
      Map.new(@resources, fn r -> {r, Map.get(payload, String.to_existing_atom(r), 0)} end)

    if Enum.all?(quantities, fn {_r, qty} -> is_integer(qty) and qty >= 0 end),
      do: quantities,
      else: :error
  end

  defp total_cost(market, quantities) do
    Enum.reduce_while(@resources, {:ok, 0}, fn r, {:ok, acc} ->
      case Ladder.cost(r, market[r], quantities[r]) do
        {:ok, cost} -> {:cont, {:ok, acc + cost}}
        :error -> {:halt, {:error, :insufficient_market}}
      end
    end)
  end

  defp affordable(%{credits: credits}, cost) when credits >= cost, do: :ok
  defp affordable(_target, _cost), do: {:error, :insufficient_credits}

  defp store(target, quantities) do
    new_resources = Map.new(@resources, fn r -> {r, target.resources[r] + quantities[r]} end)

    if Capacity.fits?(Capacity.caps(target.plants), new_resources),
      do: {:ok, new_resources},
      else: {:error, :storage_exceeded}
  end
end
