defmodule GridMaster.Engine.Auction do
  @moduledoc """
  競標階段子狀態機。

  - `queue`：尚未買到／棄權者（順位序），隊頭是提名人。
  - `bidding.active`：本輪競價仍在場者（循環出價順序）；`turn` 是輪到出價者
    （永遠不是現任領先者）。
  - `pending_discard`：買超上限者必須先棄卡，全階段暫停等待。
  """

  defstruct queue: [], bought: %{}, bidding: nil, pending_discard: nil

  alias GridMaster.Engine.{Capacity, Flow, Market}

  def new(turn_order), do: %__MODULE__{queue: turn_order}

  def handle(state, player, :auction_choose, payload) do
    auction = state.phase_state
    plant = payload[:plant]
    bid = payload[:bid]

    cond do
      auction.pending_discard != nil ->
        {:error, :discard_pending}

      auction.bidding != nil ->
        {:error, :bidding_in_progress}

      List.first(auction.queue) != player ->
        {:error, :not_your_turn}

      not is_integer(plant) or plant not in Market.purchasable(state) ->
        {:error, :plant_not_available}

      not is_integer(bid) or bid < plant ->
        {:error, :bid_too_low}

      state.players[player].credits < bid ->
        {:error, :insufficient_credits}

      true ->
        events = [{:auction_opened, %{player: player, plant: plant, bid: bid}}]

        case auction.queue do
          [^player] ->
            # 只剩一人：以開價直接成交
            {:ok, state, win_events} = win(state, auction, plant, player, bid)
            {:ok, state, events ++ win_events}

          queue ->
            active = rotate_to(queue, player)
            turn = next_eligible(active, player, player)
            bidding = %{plant: plant, price: bid, leader: player, active: active, turn: turn}
            {:ok, put_phase(state, %{auction | bidding: bidding}), events}
        end
    end
  end

  def handle(state, player, :auction_bid, payload) do
    auction = state.phase_state
    amount = payload[:amount]

    case auction.bidding do
      nil ->
        {:error, :no_bidding_in_progress}

      bidding ->
        cond do
          bidding.turn != player ->
            {:error, :not_your_turn}

          not is_integer(amount) or amount <= bidding.price ->
            {:error, :bid_too_low}

          state.players[player].credits < amount ->
            {:error, :insufficient_credits}

          true ->
            turn = next_eligible(bidding.active, player, player)
            bidding = %{bidding | price: amount, leader: player, turn: turn}

            {:ok, put_phase(state, %{auction | bidding: bidding}),
             [{:bid_placed, %{player: player, amount: amount}}]}
        end
    end
  end

  def handle(state, player, :auction_fold, _payload) do
    auction = state.phase_state

    case auction.bidding do
      nil ->
        {:error, :no_bidding_in_progress}

      bidding ->
        if bidding.turn != player do
          {:error, :not_your_turn}
        else
          active = List.delete(bidding.active, player)
          events = [{:bid_folded, %{player: player}}]

          case active do
            [winner] ->
              {:ok, state, win_events} =
                win(state, %{auction | bidding: nil}, bidding.plant, winner, bidding.price)

              {:ok, state, events ++ win_events}

            _ ->
              turn = next_after_removal(bidding.active, player, active, bidding.leader)
              bidding = %{bidding | active: active, turn: turn}
              {:ok, put_phase(state, %{auction | bidding: bidding}), events}
          end
        end
    end
  end

  def handle(state, player, :auction_pass, _payload) do
    auction = state.phase_state

    cond do
      auction.pending_discard != nil ->
        {:error, :discard_pending}

      auction.bidding != nil ->
        {:error, :bidding_in_progress}

      List.first(auction.queue) != player ->
        {:error, :not_your_turn}

      state.round == 1 ->
        {:error, :must_buy_first_round}

      true ->
        state = put_phase(state, %{auction | queue: tl(auction.queue)})
        maybe_end(state, [{:auction_passed, %{player: player}}])
    end
  end

  def handle(state, player, :auction_discard, payload) do
    auction = state.phase_state

    case auction.pending_discard do
      %{player: ^player, new_plant: new_plant} ->
        number = payload[:plant]
        target = state.players[player]
        owned = Enum.map(target.plants, & &1["number"])

        cond do
          number == new_plant ->
            {:error, :cannot_discard_new_plant}

          number not in owned ->
            {:error, :plant_not_owned}

          true ->
            plants = Enum.reject(target.plants, &(&1["number"] == number))
            resources = Capacity.trim(Capacity.caps(plants), target.resources)
            lost = total_units(target.resources) - total_units(resources)
            target = %{target | plants: plants, resources: resources}

            state = %{
              state
              | players: Map.put(state.players, player, target),
                removed: [number | state.removed]
            }

            state = put_phase(state, %{auction | pending_discard: nil})

            maybe_end(state, [
              {:plant_discarded, %{player: player, plant: number, resources_lost: lost}}
            ])
        end

      _ ->
        {:error, :no_discard_pending}
    end
  end

  # --- 成交 ---

  defp win(state, auction, plant, winner, price) do
    plant_data = state.static.plants[plant]
    target = state.players[winner]
    target = %{target | credits: target.credits - price, plants: target.plants ++ [plant_data]}

    state = %{
      state
      | players: Map.put(state.players, winner, target),
        round_plants_bought: state.round_plants_bought + 1
    }

    {state, market_events} = Market.take_bought(state, plant)

    auction = %{
      auction
      | bidding: nil,
        bought: Map.put(auction.bought, winner, plant),
        queue: List.delete(auction.queue, winner)
    }

    events = [{:plant_bought, %{player: winner, plant: plant, price: price}} | market_events]

    if length(target.plants) > state.static.config["max_plants"] do
      auction = %{auction | pending_discard: %{player: winner, new_plant: plant}}
      {:ok, put_phase(state, auction), events ++ [{:discard_required, %{player: winner}}]}
    else
      maybe_end(put_phase(state, auction), events)
    end
  end

  defp maybe_end(state, events) do
    auction = state.phase_state

    if auction.queue == [] and auction.pending_discard == nil do
      {state, flow_events} = Flow.end_auction(state)
      {:ok, state, events ++ flow_events}
    else
      {:ok, state, events}
    end
  end

  # --- 循環順序輔助 ---

  defp put_phase(state, auction), do: %{state | phase_state: auction}

  defp rotate_to(list, element) do
    index = Enum.find_index(list, &(&1 == element))
    Enum.drop(list, index) ++ Enum.take(list, index)
  end

  # element 之後（循環序）第一位非 leader 的在場者
  defp next_eligible(active, element, leader) do
    active |> rotate_to(element) |> tl() |> Enum.find(&(&1 != leader))
  end

  # 退出者的下一位：沿退出前的循環序找仍在場且非 leader 者
  defp next_after_removal(old_active, removed, new_active, leader) do
    old_active
    |> rotate_to(removed)
    |> tl()
    |> Enum.find(&(&1 in new_active and &1 != leader))
  end

  defp total_units(resources), do: resources |> Map.values() |> Enum.sum()
end
