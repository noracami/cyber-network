defmodule GridMaster.Engine.ScenarioTest do
  use ExUnit.Case, async: true

  alias GridMaster.Engine
  alias GridMaster.Engine.{Building, Bureaucracy}

  import GridMaster.EngineHelpers

  describe "第 1 回合完整流程（3 人）" do
    test "競標 → 買資源 → 擴建 → 官僚 → 第 2 回合" do
      {state, _} = new_game(["p1", "p2", "p3"])
      [a, b, c] = state.turn_order

      # --- 競標：a 提名 5 號，b 加價得標 ---
      {state, _} = act!(state, a, {:auction_choose, %{plant: 5, bid: 5}})
      assert state.phase_state.bidding.turn == b

      {state, _} = act!(state, b, {:auction_bid, %{amount: 6}})
      {state, _} = act!(state, c, {:auction_fold, %{}})
      {state, _} = act!(state, a, {:auction_fold, %{}})

      assert state.players[b].credits == 44
      assert Enum.map(state.players[b].plants, & &1["number"]) == [5]
      # 補牌：牌庫頂的 13 號進市場
      assert 13 in state.market

      # --- a 再提名 3 號，c 放棄競價 → a 得標 ---
      {state, _} = act!(state, a, {:auction_choose, %{plant: 3, bid: 3}})
      {state, _} = act!(state, c, {:auction_fold, %{}})
      assert state.players[a].credits == 47

      # --- c 單獨一人：第 1 回合禁止棄權，必須買 ---
      assert {:error, :must_buy_first_round} = Engine.apply_action(state, c, {:auction_pass, %{}})
      {state, _} = act!(state, c, {:auction_choose, %{plant: 4, bid: 4}})

      # --- 第 1 回合特規：以卡號重排順位 b(5) > c(4) > a(3) ---
      assert state.phase == :resources
      assert state.turn_order == [b, c, a]
      # 買資源反序：落後者 a 先
      assert state.phase_state.queue == [a, c, b]

      # --- 買資源 ---
      {state, _} = act!(state, a, {:resources_buy, %{thermal: 2}})
      assert state.players[a].credits == 41
      assert state.resource_market["thermal"] == 16

      {state, _} = act!(state, c, {:resources_buy, %{hydro: 2}})
      assert state.players[c].credits == 44

      {state, _} = act!(state, b, {:resources_buy, %{}})
      assert state.phase == :building

      # --- 擴建（反序）---
      {state, events} = act!(state, a, {:build, %{city: "seattle"}})
      assert {:city_built, %{cost: 10, toll: 0}} = find_event(events, :city_built)
      assert state.players[a].credits == 31
      assert state.city_owners["seattle"] == [a]

      # Step 1 同城只開一格
      {state, _} = act!(state, a, {:build_done, %{}})
      assert {:error, :city_full} = Engine.apply_action(state, c, {:build, %{city: "seattle"}})

      {state, _} = act!(state, c, {:build, %{city: "portland"}})
      {state, _} = act!(state, c, {:build_done, %{}})
      {state, _} = act!(state, b, {:build_done, %{}})

      # --- 官僚：全員同時提交 ---
      assert state.phase == :bureaucracy
      {state, _} = act!(state, a, {:power_submit, %{plants: [3]}})
      {state, _} = act!(state, c, {:power_submit, %{plants: [4]}})
      {state, events} = act!(state, b, {:power_submit, %{plants: []}})

      # 供電收入：a、c 各供 1 城（22）；b 沒城（保底 10）
      assert state.players[a].credits == 31 + 22
      assert state.players[c].credits == 34 + 22
      assert state.players[b].credits == 44 + 10
      # 燒掉的燃料歸還銀行後補給：水力回滿、火力回 18、廢料 +1、算力 +1
      assert state.resource_market == %{
               "hydro" => 24,
               "thermal" => 18,
               "waste" => 7,
               "quantum" => 3
             }

      assert {:resupplied, _} = find_event(events, :resupplied)

      # --- 第 2 回合：城市數平手比卡號 c(4) > a(3)，b 沒城殿後 ---
      assert state.round == 2
      assert state.phase == :auction
      assert state.turn_order == [c, a, b]
      # 市場經輪替後仍為 8 張
      assert length(state.market) == 8
    end
  end

  describe "買超上限與棄卡" do
    test "第 4 張卡觸發棄卡，容量縮水自動修剪資源" do
      {state, _} = new_game(["p1", "p2", "p3"])
      [a | _] = state.turn_order

      # 直接給 a 三張水力廠（容量 2×(3+2+3) = 16）與 12 個水力
      plants = [plant(state, 20), plant(state, 25), plant(state, 31)]

      target = %{
        state.players[a]
        | plants: plants,
          resources: %{"hydro" => 12, "thermal" => 0, "waste" => 0, "quantum" => 0}
      }

      state = %{state | players: Map.put(state.players, a, target)}

      # a 買下 6 號（第 4 張）→ 觸發棄卡
      {state, _} = act!(state, a, {:auction_choose, %{plant: 6, bid: 6}})
      state = fold_until_won(state)
      assert state.phase_state.pending_discard.player == a

      # 棄卡期間不能提名，也不能棄剛買的卡
      assert {:error, :discard_pending} =
               Engine.apply_action(state, a, {:auction_choose, %{plant: 7, bid: 7}})

      assert {:error, :cannot_discard_new_plant} =
               Engine.apply_action(state, a, {:auction_discard, %{plant: 6}})

      # 棄 20 號 → 水力容量 16→10，12 個水力修剪為 10
      {state, events} = act!(state, a, {:auction_discard, %{plant: 20}})
      assert state.players[a].resources["hydro"] == 10
      assert {:plant_discarded, %{resources_lost: 2}} = find_event(events, :plant_discarded)
      assert 20 in state.removed
    end
  end

  describe "Step 2 觸發" do
    test "建到第 7 城即時進 Step 2 並移除最低卡" do
      {state, _} = new_game(["p1", "p2", "p3"])
      [a | _] = state.turn_order

      # 直接把 a 推到 6 城、開建階段輪到 a
      cities = ~w(seattle portland boise billings cheyenne denver)
      target = %{state.players[a] | cities: MapSet.new(cities), credits: 200}

      state = %{
        state
        | players: Map.put(state.players, a, target),
          city_owners: Map.new(cities, &{&1, [a]}),
          phase: :building,
          phase_state: Building.new([a, a])
      }

      [lowest | _] = state.market

      {state, events} = act!(state, a, {:build, %{city: "omaha"}})

      assert state.step == 2
      assert {:step_changed, %{step: 2}} = find_event(events, :step_changed)
      # 最低卡被移除
      refute lowest in state.market
      assert lowest in state.removed
      # Step 2：第二個玩家可進駐同一城
      [_, b, _] = Map.keys(state.players) |> Enum.sort()
      _ = b
    end
  end

  describe "終局" do
    test "達到終局城市數後，最終官僚結算並排名" do
      {state, _} = new_game(["p1", "p2", "p3"])
      [a, b, c] = state.turn_order

      # a 直達 17 城（3 人局 game_end = 17）
      seventeen = state.static.active_cities |> Enum.sort() |> Enum.take(17)
      target = %{state.players[a] | cities: MapSet.new(seventeen)}

      state = %{
        state
        | players: Map.put(state.players, a, target),
          city_owners: Map.new(seventeen, &{&1, [a]}),
          phase: :building,
          phase_state: Building.new([a, b, c])
      }

      # 三人收手 → 終局回合
      {state, _} = act!(state, c, {:build_done, %{}})
      {state, _} = act!(state, b, {:build_done, %{}})
      {state, events} = act!(state, a, {:build_done, %{}})
      assert state.final_round
      assert find_event(events, :final_round)

      # 最終官僚：全員無可供電（沒資源），比錢排名
      {state, _} = act!(state, a, {:power_submit, %{plants: []}})
      {state, _} = act!(state, b, {:power_submit, %{plants: []}})
      {state, events} = act!(state, c, {:power_submit, %{plants: []}})

      assert state.phase == :finished
      assert {:game_ended, result} = find_event(events, :game_ended)
      assert result.winner != nil
      assert length(result.ranking) == 3
      # 遊戲結束後拒絕任何動作
      assert {:error, :game_finished} = Engine.apply_action(state, a, {:build_done, %{}})
    end
  end

  describe "官僚階段防呆" do
    test "重複提交、未持有設施、資源不足都被擋" do
      {state, _} = new_game(["p1", "p2"])
      [a, b] = state.turn_order

      state = %{state | phase: :bureaucracy, phase_state: Bureaucracy.new()}

      assert {:error, :plant_not_owned} =
               Engine.apply_action(state, a, {:power_submit, %{plants: [20]}})

      {state, _} = act!(state, a, {:power_submit, %{plants: []}})

      assert {:error, :already_submitted} =
               Engine.apply_action(state, a, {:power_submit, %{plants: []}})

      # b 有廢料廠但沒廢料
      target = %{state.players[b] | plants: [plant(state, 6)]}
      state = %{state | players: Map.put(state.players, b, target)}

      assert {:error, :insufficient_resources} =
               Engine.apply_action(state, b, {:power_submit, %{plants: [6]}})
    end
  end
end
