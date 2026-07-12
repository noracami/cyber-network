defmodule GridMaster.Store do
  @moduledoc """
  房間持久化（PRD-v1.5 R1）。三張表分工：

  - `room_snapshots`：一房一列、每次動作後整份覆寫——重啟後原地續局。
  - `games`：對局表，開局即建列（`initial_state` 為重播起點），
    自然完局補名次、中途結束補 `aborted_at`。
  - `game_actions`：append-only 動作日誌，initial_state 依序重套即可
    重建任意時間點（引擎純函數＋固定 rng）。

  所有寫入都容錯：資料庫故障只記 log，牌局照常進行（狀態仍在記憶體）。
  引擎的 `static`（唯讀數據）與 `rng`（:rand 狀態含 fun，跨版本不穩）
  不直接序列化——static 還原時由 Data 決定性重建、rng 走 export/import。
  """

  import Ecto.Query

  require Logger

  alias GridMaster.{Data, Engine, Repo}
  alias GridMaster.Store.{Game, GameAction, RoomSnapshot}

  # 房間或引擎的狀態結構改變時 bump：舊快照直接棄用（等同重啟前的行為）
  @snapshot_version 1

  def snapshot_version, do: @snapshot_version

  # ── 房間快照 ────────────────────────────────────────────────

  def save(room) do
    payload =
      :erlang.term_to_binary(%{
        status: room.status,
        users: room.users,
        seats: room.seats,
        chat: room.chat,
        engine: pack_engine(room.engine),
        result: room.result,
        game_id: room.game_id,
        action_seq: room.action_seq
      })

    Repo.insert!(
      %RoomSnapshot{
        room_id: room.id,
        version: @snapshot_version,
        payload: payload,
        updated_at: DateTime.utc_now()
      },
      on_conflict: {:replace, [:version, :payload, :updated_at]},
      conflict_target: :room_id
    )

    :ok
  rescue
    e -> log_failure("快照寫入", room.id, e)
  end

  def load(room_id) do
    case Repo.get(RoomSnapshot, room_id) do
      nil ->
        :none

      %{version: @snapshot_version, payload: payload} ->
        # 不用 :safe——快照出自自家 DB（可信），且開機還原時引擎模組尚未
        # lazy load、其 atom 不在 atom table，:safe 會 badarg 誤殺
        saved = :erlang.binary_to_term(payload)
        {:ok, %{saved | engine: unpack_engine(saved.engine)}}

      %{version: version} ->
        Logger.warning("房間 #{room_id} 快照版本不符（v#{version}≠v#{@snapshot_version}），棄用")
        delete(room_id)
        :none
    end
  rescue
    e ->
      log_failure("快照載入", room_id, e)
      :none
  end

  def delete(room_id) do
    Repo.delete_all(from(r in RoomSnapshot, where: r.room_id == ^room_id))
    :ok
  rescue
    e -> log_failure("快照刪除", room_id, e)
  end

  def list_room_ids do
    Repo.all(from(r in RoomSnapshot, select: r.room_id))
  rescue
    e ->
      log_failure("快照列舉", "*", e)
      []
  end

  @doc "清掃逾時快照（斷線棄局等）；main 例外，聊天歷史永遠保留。"
  def sweep(ttl_hours) do
    {count, _} =
      Repo.delete_all(
        from(r in RoomSnapshot,
          where: r.room_id != "main" and r.updated_at < ago(^ttl_hours, "hour")
        )
      )

    if count > 0, do: Logger.info("已清掃 #{count} 份逾時房間快照")
    :ok
  rescue
    e -> log_failure("快照清掃", "*", e)
  end

  # ── 對局表與動作日誌 ────────────────────────────────────────

  def create_game(room_id, engine) do
    game =
      Repo.insert!(%Game{
        room_id: room_id,
        map: Data.map()["id"],
        version: @snapshot_version,
        initial_state: :erlang.term_to_binary(pack_engine(engine)),
        started_at: DateTime.utc_now()
      })

    {:ok, game.id}
  rescue
    e -> log_failure("對局建立", room_id, e)
  end

  def record_action(nil, _seq, _round, _player_id, _type, _payload), do: :ok

  def record_action(game_id, seq, round, player_id, type, payload) do
    Repo.insert!(%GameAction{
      game_id: game_id,
      seq: seq,
      round: round,
      player_id: player_id,
      action: Atom.to_string(type),
      payload: payload,
      inserted_at: DateTime.utc_now()
    })

    :ok
  rescue
    e -> log_failure("動作日誌", "game##{game_id}", e)
  end

  def finish_game(nil, _attrs), do: :ok

  def finish_game(game_id, attrs) do
    Repo.update_all(from(g in Game, where: g.id == ^game_id),
      set: [
        players: attrs.players,
        winner_id: attrs.winner_id,
        winner_name: attrs.winner_name,
        rounds: attrs.rounds,
        finished_at: DateTime.utc_now()
      ]
    )

    :ok
  rescue
    e -> log_failure("對局完局", "game##{game_id}", e)
  end

  def abort_game(nil), do: :ok

  def abort_game(game_id) do
    Repo.update_all(from(g in Game, where: g.id == ^game_id),
      set: [aborted_at: DateTime.utc_now()]
    )

    :ok
  rescue
    e -> log_failure("對局中止", "game##{game_id}", e)
  end

  # ── 引擎打包 ────────────────────────────────────────────────

  @doc "序列化前拆掉 static（可決定性重建）並匯出 rng（原始狀態含 fun）。"
  def pack_engine(nil), do: nil

  def pack_engine(engine),
    do: %{engine | static: nil, rng: {:exported, :rand.export_seed_s(engine.rng)}}

  @doc "還原引擎：rng 匯入、static 由 Data 重建。"
  def unpack_engine(nil), do: nil

  def unpack_engine(engine) do
    {:exported, seed} = engine.rng
    Engine.rebuild_static(%{engine | rng: :rand.seed_s(seed)})
  end

  defp log_failure(what, id, exception) do
    Logger.warning("#{what}失敗（#{id}）：#{Exception.message(exception)}")
    :error
  end
end
