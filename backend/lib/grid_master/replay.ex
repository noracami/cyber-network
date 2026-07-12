defmodule GridMaster.Replay do
  @moduledoc """
  對局重播：games.initial_state 依序重套 game_actions，重建任意時間點的
  引擎狀態。引擎純函數＋固定 rng，重播結果與實際對局完全一致
  （store_test 的重播不變量測試守著這條性質）。回放／觀戰 UI 的數據基礎。
  """

  import Ecto.Query

  alias GridMaster.{Engine, Repo, Store}
  alias GridMaster.Store.{Game, GameAction}

  @doc "重播整局（或以 `until_seq:` 停在中途），回傳 {:ok, 引擎狀態}。"
  def run(game_id, opts \\ []) do
    game = Repo.get!(Game, game_id)

    if game.version != Store.snapshot_version() do
      {:error, :version_mismatch}
    else
      # 同 Store.load：blob 出自自家 DB，:safe 會被 lazy loading 誤殺
      initial = Store.unpack_engine(:erlang.binary_to_term(game.initial_state))

      from(a in GameAction, where: a.game_id == ^game_id, order_by: a.seq)
      |> maybe_until(opts[:until_seq])
      |> Repo.all()
      |> Enum.reduce_while({:ok, initial}, fn action, {:ok, engine} ->
        case Engine.apply_action(engine, action.player_id, decode(action)) do
          {:ok, engine, _events} -> {:cont, {:ok, engine}}
          {:error, reason} -> {:halt, {:error, {reason, action.seq}}}
        end
      end)
    end
  end

  defp maybe_until(query, nil), do: query
  defp maybe_until(query, seq), do: where(query, [a], a.seq <= ^seq)

  # jsonb 把 payload 的 atom 鍵存成字串；動作與資源名單有限，existing_atom 安全
  defp decode(action) do
    payload = Map.new(action.payload, fn {k, v} -> {String.to_existing_atom(k), v} end)
    {String.to_existing_atom(action.action), payload}
  end
end
