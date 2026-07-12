defmodule GridMaster.NpcTest do
  @moduledoc """
  NPC 策略測試：
  1. 純引擎層——全 NPC 對局用偏好候選清單驅動，必須能推進（不卡死）。
  2. Room 整合——真人＋NPC 混局，NPC 由 :npc_tick 自動出手推進牌局。
  """

  use ExUnit.Case, async: true

  import GridMaster.EngineHelpers

  alias GridMaster.{Engine, Npc, Room}

  @max_steps 3000

  describe "引擎層全 NPC 對局" do
    test "2 NPC 以偏好策略驅動，牌局能實質推進" do
      npcs = [Npc.id(1), Npc.id(2)]
      {state, _events} = new_game(npcs)
      final = drive(state, npcs, 0)

      assert final.phase == :finished or final.round >= 3,
             "NPC 局沒有推進：round=#{final.round} phase=#{final.phase}"
    end

    test "4 NPC 局同樣能推進" do
      npcs = Enum.map(1..4, &Npc.id/1)
      {state, _events} = new_game(npcs, seed: {7, 7, 7})
      final = drive(state, npcs, 0)

      assert final.phase == :finished or final.round >= 3
    end
  end

  defp drive(%{phase: :finished} = state, _npcs, _step), do: state
  defp drive(state, _npcs, @max_steps), do: state

  defp drive(state, npcs, step) do
    npc = Npc.pending(state, npcs)
    assert npc != nil, "沒有待行動 NPC（phase=#{state.phase}）"

    candidates = Npc.candidates(state, npc)
    assert candidates != [], "#{npc} 沒有候選動作（phase=#{state.phase}）"

    state = try_apply(state, npc, candidates)
    drive(state, npcs, step + 1)
  end

  defp try_apply(state, npc, [action | rest]) do
    case Engine.apply_action(state, npc, action) do
      {:ok, new_state, _events} -> new_state
      {:error, _reason} when rest != [] -> try_apply(state, npc, rest)
      {:error, reason} -> flunk("#{npc} 所有候選皆失敗於 #{state.phase}: #{inspect(reason)}")
    end
  end

  describe "Room 整合" do
    defp start_room(opts \\ []) do
      id = "npct#{System.unique_integer([:positive])}"
      pid = start_supervised!({Room, Keyword.merge([id: id, npc_delay: {1, 2}], opts)})
      pid
    end

    defp user(id, role \\ "discord"), do: %{id: id, name: id, role: role}

    test "訪客不能加 NPC；登入者可加可移除" do
      room = start_room()
      Room.join(room, user("g", "guest"), self())
      Room.join(room, user("a"), self())

      assert {:error, :login_required} = Room.lobby_op(room, :npc_add, "g")
      assert {:error, :no_npc} = Room.lobby_op(room, :npc_remove, "a")

      assert :ok = Room.lobby_op(room, :npc_add, "a")
      snapshot = Room.snapshot(room)
      assert "npc_1" in snapshot.seats
      assert snapshot.users["npc_1"].ready
      assert snapshot.users["npc_1"].online

      assert :ok = Room.lobby_op(room, :npc_remove, "a")
      refute "npc_1" in Room.snapshot(room).seats
    end

    test "一位真人＋一個 NPC 即可開局，NPC 自動出手推進牌局" do
      room = start_room()
      Room.join(room, user("a"), self())
      :ok = Room.lobby_op(room, :seat_take, "a")
      :ok = Room.lobby_op(room, :npc_add, "a")
      :ok = Room.lobby_op(room, :ready, "a")
      assert :ok = Room.lobby_op(room, :game_start, "a")

      # 混合驅動：輪到真人就用同一套候選策略代打，NPC 靠 :npc_tick 自動出手
      assert wait_progress(room, "a", 400), "牌局未能推進到第 2 回合"
    end

    test "入座玩家可結束遊戲；旁觀者不行" do
      room = start_room()
      Room.join(room, user("a"), self())
      Room.join(room, user("watcher"), self())
      :ok = Room.lobby_op(room, :seat_take, "a")
      :ok = Room.lobby_op(room, :npc_add, "a")
      :ok = Room.lobby_op(room, :ready, "a")
      :ok = Room.lobby_op(room, :game_start, "a")

      assert {:error, :forbidden} = Room.admin_abort(room, "watcher")
      assert :ok = Room.admin_abort(room, "a")
      assert Room.snapshot(room).status == :lobby
    end
  end

  # 反覆檢查房間狀態：真人回合就代打一手，直到 round >= 2（NPC 出手證明）
  defp wait_progress(_room, _human, 0), do: false

  defp wait_progress(room, human, tries) do
    engine = :sys.get_state(room).engine

    cond do
      engine == nil ->
        # 已終局回大廳（極快速局）——也算推進
        true

      engine.phase == :finished or engine.round >= 2 ->
        true

      Npc.pending(engine, [human]) == human ->
        [{type, payload} | rest] = Npc.candidates(engine, human)

        case Room.game_action(room, human, type, payload) do
          :ok -> :ok
          {:error, _reason} -> fallback_action(room, human, rest)
        end

        wait_progress(room, human, tries - 1)

      true ->
        Process.sleep(10)
        wait_progress(room, human, tries - 1)
    end
  end

  defp fallback_action(_room, _human, []), do: :ok

  defp fallback_action(room, human, [{type, payload} | rest]) do
    case Room.game_action(room, human, type, payload) do
      :ok -> :ok
      {:error, _reason} -> fallback_action(room, human, rest)
    end
  end
end
