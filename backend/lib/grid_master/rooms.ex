defmodule GridMaster.Rooms do
  @moduledoc """
  房間進程管理：Registry 查找＋DynamicSupervisor 隨需啟動。
  MVP 只用單一房間 `main`，但架構天然支援多房。
  """

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
