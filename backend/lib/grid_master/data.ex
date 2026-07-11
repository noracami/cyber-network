defmodule GridMaster.Data do
  @moduledoc """
  載入並快取 `priv/data/` 的靜態遊戲數據（地圖／牌庫／規則表）。

  首次存取時讀檔、驗證並寫入 `:persistent_term`；數據不合法會直接 raise，
  讓壞數據在啟動或測試階段立刻現形，而不是在牌局中途。
  """

  alias GridMaster.Data.Validator

  @files %{map: "usa_map.json", deck: "cyber_decks.json", rules: "game_rules.json"}

  @spec map() :: map()
  def map, do: fetch(:map)

  @spec deck() :: map()
  def deck, do: fetch(:deck)

  @spec rules() :: map()
  def rules, do: fetch(:rules)

  @doc "清除快取，讓下次存取重新讀檔（測試用）。"
  @spec reset_cache() :: :ok
  def reset_cache do
    Enum.each(Map.keys(@files), &:persistent_term.erase({__MODULE__, &1}))
    :ok
  end

  defp fetch(key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil ->
        data = load!(key)
        :persistent_term.put({__MODULE__, key}, data)
        data

      data ->
        data
    end
  end

  defp load!(key) do
    path = Application.app_dir(:grid_master, ["priv", "data", Map.fetch!(@files, key)])
    data = path |> File.read!() |> Jason.decode!()
    :ok = Validator.validate!(key, data)
    data
  end
end
