defmodule GridMaster.Npc do
  @moduledoc """
  不求勝 NPC（v1.4）：對引擎狀態產生「偏好排序的候選動作清單」，
  由 Room 依序嘗試執行。每個階段的清單都以必定合法的動作收尾
  （棄權／空買／結束擴建／空供電——與 random_drive_test 相同的模式），
  保證牌局永遠不會卡在 NPC 手上。

  策略概述（樸素貪婪）：提名最便宜的卡、出價不超過「卡號＋3」、
  買齊一輪供電所需燃料、擴建最便宜可達城（保留 15 元）、供電全開。
  """

  alias GridMaster.Engine
  alias GridMaster.Engine.Market

  @names ~w(伏特 安培 歐姆 瓦特 焦耳 法拉)
  @resource_types ~w(hydro thermal waste quantum)
  @build_reserve 15

  def id(n), do: "npc_#{n}"
  def display_name(n), do: "🤖 " <> (Enum.at(@names, n - 1) || "NPC#{n}")
  def npc?(user_id) when is_binary(user_id), do: String.starts_with?(user_id, "npc_")
  def npc?(_user_id), do: false

  @doc "現在輪到哪個 NPC 行動；沒有則回 nil。"
  def pending(state, npc_ids)
  def pending(%{phase: :finished}, _npc_ids), do: nil

  def pending(%{phase: :auction} = state, npc_ids) do
    ps = state.phase_state

    cond do
      ps.pending_discard != nil -> among(ps.pending_discard.player, npc_ids)
      ps.bidding != nil -> among(ps.bidding.turn, npc_ids)
      true -> among(List.first(ps.queue), npc_ids)
    end
  end

  def pending(%{phase: phase} = state, npc_ids) when phase in [:resources, :building] do
    among(List.first(state.phase_state.queue), npc_ids)
  end

  def pending(%{phase: :bureaucracy} = state, npc_ids) do
    waiting = Map.keys(state.players) -- Map.keys(state.phase_state.submitted)
    Enum.find(waiting, &(&1 in npc_ids))
  end

  defp among(actor, npc_ids), do: if(actor in npc_ids, do: actor, else: nil)

  @doc "偏好排序的候選動作清單（清單尾端必為合法動作）。"
  def candidates(%{phase: :auction} = state, npc) do
    ps = state.phase_state
    me = state.players[npc]

    cond do
      ps.pending_discard != nil and ps.pending_discard.player == npc ->
        me.plants
        |> Enum.map(& &1["number"])
        |> Enum.reject(&(&1 == ps.pending_discard.new_plant))
        |> Enum.sort()
        |> Enum.map(&{:auction_discard, %{plant: &1}})

      ps.bidding != nil and ps.bidding.turn == npc ->
        %{plant: plant, price: price} = ps.bidding
        willing = plant + 3

        if price + 1 <= min(willing, me.credits) do
          [{:auction_bid, %{amount: price + 1}}, {:auction_fold, %{}}]
        else
          [{:auction_fold, %{}}]
        end

      true ->
        affordable =
          state
          |> Market.purchasable()
          |> Enum.filter(&(&1 <= me.credits))
          |> Enum.sort()

        chooses = Enum.map(affordable, &{:auction_choose, %{plant: &1, bid: &1}})
        pass = {:auction_pass, %{}}

        # 手上已有兩座以上就傾向觀望（第一回合 pass 不合法，會自然 fallback 到提名）
        if length(me.plants) >= 2 do
          [pass | chooses]
        else
          chooses ++ [pass]
        end
    end
  end

  def candidates(%{phase: :resources} = state, npc) do
    me = state.players[npc]
    desired = desired_purchase(state, me)
    halved = Map.new(desired, fn {type, qty} -> {type, div(qty, 2)} end)

    ([desired, halved, %{}]
     |> Enum.map(&drop_zero/1)
     |> Enum.uniq()
     |> Enum.map(&{:resources_buy, &1})) ++ [{:resources_buy, %{}}]
  end

  def candidates(%{phase: :building} = state, npc) do
    me = state.players[npc]

    best =
      state.static.active_cities
      |> Enum.flat_map(fn city ->
        case Engine.apply_action(state, npc, {:build, %{city: city}}) do
          {:ok, new_state, _events} -> [{me.credits - new_state.players[npc].credits, city}]
          {:error, _reason} -> []
        end
      end)
      |> Enum.min_by(&elem(&1, 0), fn -> nil end)

    case best do
      {cost, city} when cost <= me.credits - @build_reserve ->
        [{:build, %{city: city}}, {:build_done, %{}}]

      _too_expensive_or_none ->
        [{:build_done, %{}}]
    end
  end

  def candidates(%{phase: :bureaucracy} = state, npc) do
    plants = state.players[npc].plants

    # 全開優先，資源不夠就逐次拿掉燃料需求最大的設施，最後保底空供電
    subsets =
      plants
      |> Stream.iterate(fn remaining ->
        without = Enum.max_by(remaining, & &1["fuel"])
        List.delete(remaining, without)
      end)
      |> Enum.take(length(plants) + 1)

    Enum.map(subsets, fn subset ->
      {:power_submit, %{plants: Enum.map(subset, & &1["number"])}}
    end)
  end

  def candidates(_state, _npc), do: []

  # 買齊「所有設施開一輪」還缺的燃料（混合廠偏水力），上限市場存量。
  # 注意：引擎狀態的 resources／resource_market 是字串鍵；
  # resources_buy 的 payload 則吃 atom 鍵（與 Channel 白名單一致）。
  defp desired_purchase(state, me) do
    needs =
      Enum.reduce(me.plants, %{}, fn plant, acc ->
        fuel = plant["fuel"]
        type = plant["type"]

        cond do
          fuel == 0 -> acc
          type == "hybrid" -> Map.update(acc, "hydro", fuel, &(&1 + fuel))
          type in @resource_types -> Map.update(acc, type, fuel, &(&1 + fuel))
          true -> acc
        end
      end)

    Map.new(needs, fn {type, need} ->
      lack = max(0, need - (me.resources[type] || 0))
      {String.to_existing_atom(type), min(lack, state.resource_market[type] || 0)}
    end)
  end

  defp drop_zero(purchase), do: Map.reject(purchase, fn {_type, qty} -> qty <= 0 end)
end
