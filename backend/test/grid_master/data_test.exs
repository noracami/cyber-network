defmodule GridMaster.DataTest do
  use ExUnit.Case, async: true

  alias GridMaster.Data
  alias GridMaster.Data.Validator

  describe "usa_map.json" do
    test "載入成功且結構正確" do
      map = Data.map()
      assert length(map["regions"]) == 6
      assert length(map["cities"]) == 42
      assert length(map["edges"]) == 87
    end

    test "抽查連線費用（防轉錄錯誤）" do
      costs = edge_costs(Data.map())

      assert costs[{"portland", "seattle"}] == 3
      assert costs[{"cheyenne", "denver"}] == 0
      assert costs[{"new_york", "philadelphia"}] == 0
      assert costs[{"jacksonville", "savannah"}] == 0
      assert costs[{"salt_lake_city", "santa_fe"}] == 28
      assert costs[{"salt_lake_city", "san_francisco"}] == 27
      # 查證時發現他源有誤的三處，特別釘住正確值
      assert costs[{"las_vegas", "salt_lake_city"}] == 18
      assert costs[{"atlanta", "birmingham"}] == 3
      assert costs[{"jacksonville", "tampa"}] == 4
    end

    test "全表費用總和快照（誤改任何一條連線都會被抓到）" do
      assert Data.map()["edges"] |> Enum.map(& &1["cost"]) |> Enum.sum() == 907
    end
  end

  describe "cyber_decks.json" do
    test "載入成功且結構正確" do
      deck = Data.deck()
      assert length(deck["plants"]) == 42
      assert deck["setup"]["initial_market"] == [3, 4, 5, 6]
      assert deck["setup"]["initial_future"] == [7, 8, 9, 10]
      assert deck["setup"]["top_of_deck"] == 13
    end

    test "各類型設施數量與原版一致" do
      counts = Data.deck()["plants"] |> Enum.frequencies_by(& &1["type"])

      assert counts == %{
               "hydro" => 9,
               "thermal" => 8,
               "waste" => 6,
               "quantum" => 6,
               "hybrid" => 5,
               "self" => 7,
               "fusion" => 1
             }
    end

    test "抽查卡牌數值（防轉錄錯誤）" do
      plants = Map.new(Data.deck()["plants"], &{&1["number"], &1})

      assert %{"type" => "thermal", "fuel" => 2, "powers" => 1} = plants[3]
      assert %{"type" => "self", "fuel" => 0, "powers" => 1} = plants[13]
      assert %{"type" => "hybrid", "fuel" => 1, "powers" => 4} = plants[29]
      # 查證時特別確認過的高編號卡
      assert %{"type" => "thermal", "fuel" => 2, "powers" => 6} = plants[40]
      assert %{"type" => "hydro", "fuel" => 2, "powers" => 6} = plants[42]
      assert %{"type" => "self", "fuel" => 0, "powers" => 5} = plants[44]
      assert %{"type" => "hybrid", "fuel" => 3, "powers" => 7} = plants[46]
      assert %{"type" => "fusion", "fuel" => 0, "powers" => 6} = plants[50]
    end
  end

  describe "game_rules.json" do
    test "載入成功且關鍵數值正確" do
      rules = Data.rules()

      assert rules["starting_credits"] == 50
      assert rules["city_slot_costs"] == [10, 15, 20]
      # 規則書範例：供電 6 城 = 73
      assert Enum.at(rules["payout"], 6) == 73
      assert Enum.at(rules["payout"], 0) == 10
      assert Enum.at(rules["payout"], 20) == 150
      # 規則書範例：5 人 Step 2 補給 [水力 7, 火力 5, 廢料 3, 算力 3]
      assert rules["resupply"]["5"]["step2"] == [7, 5, 3, 3]
      assert rules["player_counts"]["6"]["game_end"] == 14
      assert rules["player_counts"]["2"]["max_plants"] == 4
    end
  end

  describe "Validator 對壞數據的防禦" do
    test "少一座城市 → raise" do
      map = Data.map()
      broken = %{map | "cities" => tl(map["cities"])}
      assert_raise ArgumentError, ~r/42 城/, fn -> Validator.validate!(:map, broken) end
    end

    test "連線指向不存在的城市 → raise" do
      map = Data.map()
      broken = %{map | "edges" => [%{"between" => ["seattle", "taipei"], "cost" => 1} | tl(map["edges"])]}
      assert_raise ArgumentError, ~r/taipei/, fn -> Validator.validate!(:map, broken) end
    end

    test "免燃料類型卻有燃料需求 → raise" do
      deck = Data.deck()

      broken_plants =
        Enum.map(deck["plants"], fn
          %{"number" => 13} = plant -> %{plant | "fuel" => 2}
          plant -> plant
        end)

      assert_raise ArgumentError, ~r/13 號卡/, fn ->
        Validator.validate!(:deck, %{deck | "plants" => broken_plants})
      end
    end

    test "卡片缺欄位 → 炸 KeyError 而非被靜默跳過" do
      deck = Data.deck()
      broken = %{deck | "plants" => [Map.delete(hd(deck["plants"]), "name") | tl(deck["plants"])]}
      assert_raise KeyError, fn -> Validator.validate!(:deck, broken) end
    end
  end

  defp edge_costs(map) do
    Map.new(map["edges"], fn %{"between" => [a, b], "cost" => cost} ->
      {[a, b] |> Enum.sort() |> List.to_tuple(), cost}
    end)
  end
end
