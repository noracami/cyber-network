defmodule GridMaster.Engine.Capacity do
  @moduledoc """
  資源儲存容量與燃燒可行性（engine-design.md §6.3）。

  容量 = 各設施燃料需求 ×2；hybrid 容量可裝水力或火力。
  資源記在玩家層級，購買時驗證總量約束（與原版「可自由搬移」等價）。
  """

  @empty %{hydro: 0, thermal: 0, waste: 0, quantum: 0, hybrid: 0}

  @doc "由持有設施計算各類型容量。"
  def caps(plants) do
    Enum.reduce(plants, @empty, fn plant, acc ->
      add(acc, plant["type"], 2 * plant["fuel"])
    end)
  end

  @doc "持有量 resources 是否裝得進容量 caps。"
  def fits?(caps, res) do
    res["waste"] <= caps.waste and
      res["quantum"] <= caps.quantum and
      res["hydro"] <= caps.hydro + caps.hybrid and
      res["thermal"] <= caps.thermal + caps.hybrid and
      res["hydro"] + res["thermal"] <= caps.hydro + caps.thermal + caps.hybrid
  end

  @doc """
  棄卡後容量縮水時的自動修剪：優先丟便宜資源
  （水力 → 火力 → 廢料 → 算力），保留貴的（engine-design.md §6.4）。
  """
  def trim(caps, res) do
    cond do
      fits?(caps, res) -> res
      res["waste"] > caps.waste -> trim(caps, Map.update!(res, "waste", &(&1 - 1)))
      res["quantum"] > caps.quantum -> trim(caps, Map.update!(res, "quantum", &(&1 - 1)))
      res["hydro"] > 0 -> trim(caps, Map.update!(res, "hydro", &(&1 - 1)))
      res["thermal"] > 0 -> trim(caps, Map.update!(res, "thermal", &(&1 - 1)))
      true -> res
    end
  end

  @doc """
  啟動 selected_plants 所需資源的燃燒。hybrid 先燒水力（較便宜）再燒火力。
  回 {:ok, 燃燒後持有量} 或 :error（資源不足）。
  """
  def burn(res, selected_plants) do
    need =
      Enum.reduce(selected_plants, @empty, fn plant, acc ->
        add(acc, plant["type"], plant["fuel"])
      end)

    leftover_hydro = res["hydro"] - need.hydro
    leftover_thermal = res["thermal"] - need.thermal

    if res["waste"] >= need.waste and res["quantum"] >= need.quantum and
         leftover_hydro >= 0 and leftover_thermal >= 0 and
         leftover_hydro + leftover_thermal >= need.hybrid do
      hybrid_hydro = min(leftover_hydro, need.hybrid)
      hybrid_thermal = need.hybrid - hybrid_hydro

      {:ok,
       %{
         "hydro" => leftover_hydro - hybrid_hydro,
         "thermal" => leftover_thermal - hybrid_thermal,
         "waste" => res["waste"] - need.waste,
         "quantum" => res["quantum"] - need.quantum
       }}
    else
      :error
    end
  end

  defp add(acc, "hybrid", amount), do: %{acc | hybrid: acc.hybrid + amount}
  defp add(acc, "hydro", amount), do: %{acc | hydro: acc.hydro + amount}
  defp add(acc, "thermal", amount), do: %{acc | thermal: acc.thermal + amount}
  defp add(acc, "waste", amount), do: %{acc | waste: acc.waste + amount}
  defp add(acc, "quantum", amount), do: %{acc | quantum: acc.quantum + amount}
  # self / fusion 免燃料，無容量
  defp add(acc, _type, _amount), do: acc
end
