defmodule GridMaster.Rooms do
  @moduledoc """
  房間進程管理：Registry 查找＋DynamicSupervisor 隨需啟動。
  任何合法房號隨需開房（白名單在 RoomChannel），閒置房間自行關閉。
  """

  @doc "全站活動概況：房間數與進行中牌局數（/api/activity）。"
  @spec activity() :: %{rooms: non_neg_integer(), in_game: non_neg_integer()}
  def activity do
    ids = room_ids()

    in_game =
      Enum.count(ids, fn id ->
        case fetch_view(id) do
          %{status: :in_game} -> true
          _closed_or_other -> false
        end
      end)

    %{rooms: length(ids), in_game: in_game}
  end

  @doc "活躍房間列表（/api/rooms）：房號、狀態、入座數、在線真人數。main 排最前。"
  def list do
    room_ids()
    |> Enum.map(&fetch_view/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn view ->
      %{
        id: view.id,
        status: view.status,
        seated: length(view.seats),
        online: Enum.count(view.users, fn {_id, u} -> u.online and u.role != "npc" end)
      }
    end)
    |> Enum.sort_by(fn room -> {room.id != "main", room.id} end)
  end

  defp room_ids do
    Registry.select(GridMaster.RoomRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  defp fetch_view(id) do
    GridMaster.Room.snapshot(GridMaster.Room.via(id))
  catch
    # 房間剛好關閉的競態：略過
    :exit, _reason -> nil
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
