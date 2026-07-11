defmodule GridMaster.EngineHelpers do
  @moduledoc "引擎測試共用工具。"

  alias GridMaster.Engine

  @all_regions ~w(nw sw mw sc ne se)

  @doc "建立測試牌局：固定 seed、預設全叢集啟用（消除區域隨機性）。"
  def new_game(player_ids, opts \\ []) do
    opts = Keyword.merge([seed: {42, 42, 42}, active_regions: @all_regions], opts)
    Engine.new(player_ids, opts)
  end

  @doc "執行必須成功的動作。"
  def act!(state, player, action) do
    case Engine.apply_action(state, player, action) do
      {:ok, state, events} -> {state, events}
      {:error, reason} -> raise "動作失敗 #{inspect(action)}: #{inspect(reason)}"
    end
  end

  @doc "取靜態卡牌數據。"
  def plant(state, number), do: state.static.plants[number]

  @doc "讓競價中的玩家依序全部 fold，直到成交。"
  def fold_until_won(state) do
    case state.phase_state.bidding do
      nil ->
        state

      %{turn: turn} ->
        {state, _} = act!(state, turn, {:auction_fold, %{}})
        fold_until_won(state)
    end
  end

  @doc "在事件清單中找指定型別的事件。"
  def find_event(events, type), do: Enum.find(events, fn {t, _} -> t == type end)
end
