defmodule GridMaster.Engine.View do
  @moduledoc """
  引擎狀態 → 前端可見 JSON 視圖。
  金錢公開（使用者定案）；牌庫只給張數；`static` 與 `rng` 不出引擎。
  viewer 參數保留給未來的個人化需求。
  """

  alias GridMaster.Engine.{Ladder, Market}

  @spec render(GridMaster.Engine.State.t(), String.t() | nil) :: map()
  def render(state, _viewer \\ nil) do
    real = Market.real_plants(state.market)
    {actual, future} = if state.step == 3, do: {real, []}, else: Enum.split(real, 4)
    future = if :step3 in state.market, do: future ++ ["step3"], else: future

    %{
      step: state.step,
      round: state.round,
      phase: Atom.to_string(state.phase),
      final_round: state.final_round,
      turn_order: state.turn_order,
      active_regions: Enum.sort(state.active_regions),
      players:
        Map.new(state.players, fn {id, p} ->
          {id,
           %{
             credits: p.credits,
             plants: p.plants,
             resources: p.resources,
             cities: Enum.sort(p.cities)
           }}
        end),
      market: %{actual: actual, future: future},
      deck_count: Enum.count(state.deck, &is_integer/1),
      resource_market:
        Map.new(state.resource_market, fn {resource, count} ->
          {resource, %{count: count, cheapest: Ladder.cheapest(resource, count)}}
        end),
      city_owners: state.city_owners,
      phase_state: render_phase(state.phase, state.phase_state),
      winner: state.winner
    }
  end

  defp render_phase(:auction, auction) do
    %{
      queue: auction.queue,
      bought: auction.bought,
      bidding:
        auction.bidding && Map.take(auction.bidding, [:plant, :price, :leader, :turn, :active]),
      pending_discard: auction.pending_discard && auction.pending_discard.player
    }
  end

  defp render_phase(:resources, resources), do: %{queue: resources.queue}
  defp render_phase(:building, building), do: %{queue: building.queue}
  defp render_phase(:bureaucracy, bureaucracy), do: %{submitted: Map.keys(bureaucracy.submitted)}
  defp render_phase(:finished, _phase_state), do: nil
end
