defmodule GridMaster.Engine.State do
  @moduledoc """
  引擎完整狀態（純資料）。

  - `static`：地圖／卡牌／規則的唯讀數據與預計算索引（依 active_regions 過濾後的
    鄰接表等），不隨動作改變，view 層排除於同步之外。
  - `rng`：`:rand` 狀態。同 seed＋同動作序列必得同結果，整局可重放。
  - `market`：恆保持排序的卡牌市場清單；`:step3` 原子代表 Step 3 卡，排序視為最大。
  - `deck`：牌頂在前。`:step3` 之後可能還有官僚階段塞入牌底的卡（原版規則）。
  """

  defstruct [
    :step,
    :round,
    :phase,
    :phase_state,
    :turn_order,
    :rng,
    :players,
    :market,
    :deck,
    :removed,
    :resource_market,
    :city_owners,
    :active_regions,
    :winner,
    :round_plants_bought,
    :step3_pending,
    :final_round,
    :static
  ]
end

defmodule GridMaster.Engine.Player do
  @moduledoc "單一玩家的遊戲內狀態。資源記在玩家層級（engine-design.md §6.3）。"

  defstruct credits: 0,
            plants: [],
            resources: %{"hydro" => 0, "thermal" => 0, "waste" => 0, "quantum" => 0},
            cities: MapSet.new()
end
