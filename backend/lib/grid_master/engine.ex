defmodule GridMaster.Engine do
  @moduledoc """
  引擎公開介面（純函數）。

      {state, events} = Engine.new(["p1", "p2"], seed: {1, 2, 3})
      {:ok, state, events} = Engine.apply_action(state, "p1", {:auction_choose, %{plant: 3, bid: 3}})

  所有動作回 `{:ok, new_state, events}` 或 `{:error, reason}`（state 不變）。
  """

  alias GridMaster.Engine.{Auction, Building, Bureaucracy, Resources, Setup, State}

  @auction_actions [:auction_choose, :auction_bid, :auction_fold, :auction_pass, :auction_discard]
  @building_actions [:build, :build_done]

  defdelegate new(player_ids, opts), to: Setup
  defdelegate rebuild_static(state), to: Setup

  @spec apply_action(State.t(), String.t(), {atom(), map()}) ::
          {:ok, State.t(), [tuple()]} | {:error, atom()}
  def apply_action(%State{} = state, player_id, action) do
    cond do
      state.phase == :finished -> {:error, :game_finished}
      not Map.has_key?(state.players, player_id) -> {:error, :unknown_player}
      true -> route(state, player_id, action)
    end
  end

  defp route(%State{phase: :auction} = state, player, {type, payload})
       when type in @auction_actions,
       do: Auction.handle(state, player, type, payload)

  defp route(%State{phase: :resources} = state, player, {:resources_buy, payload}),
    do: Resources.handle(state, player, payload)

  defp route(%State{phase: :building} = state, player, {type, payload})
       when type in @building_actions,
       do: Building.handle(state, player, type, payload)

  defp route(%State{phase: :bureaucracy} = state, player, {:power_submit, payload}),
    do: Bureaucracy.handle(state, player, payload)

  defp route(_state, _player, _action), do: {:error, :invalid_action}
end
