defmodule GridMaster.Rooms do
  @moduledoc """
  房間進程管理：Registry 查找＋DynamicSupervisor 隨需啟動。
  MVP 只用單一房間 `main`，但架構天然支援多房。
  """

  @doc "全站活動概況：房間數與進行中牌局數（部署腳本用來判斷可否重啟）。"
  @spec activity() :: %{rooms: non_neg_integer(), in_game: non_neg_integer()}
  def activity do
    ids = Registry.select(GridMaster.RoomRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

    in_game =
      Enum.count(ids, fn id ->
        try do
          GridMaster.Room.snapshot(GridMaster.Room.via(id)).status == :in_game
        catch
          # 房間剛好關閉的競態：當作不在遊戲中
          :exit, _reason -> false
        end
      end)

    %{rooms: length(ids), in_game: in_game}
  end

  @spec ensure(String.t(), keyword()) :: {:ok, pid()}
  def ensure(room_id, opts \\ []) do
    case Registry.lookup(GridMaster.RoomRegistry, room_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        spec = {GridMaster.Room, Keyword.put(opts, :id, room_id)}

        case DynamicSupervisor.start_child(GridMaster.RoomSupervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
        end
    end
  end
end
