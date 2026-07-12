defmodule GridMaster.Store.Janitor do
  @moduledoc """
  持久化管家：開機喚醒所有有快照的房間（in_game 房的 NPC 隨還原繼續出手），
  之後每小時清掃逾時快照（24h TTL，main 例外）。測試環境不啟動（config
  `:room_janitor` 為 false）。
  """

  use GenServer

  alias GridMaster.{Rooms, Store}

  @sweep_interval :timer.hours(1)
  @snapshot_ttl_hours 24

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Application.get_env(:grid_master, :room_janitor, true) do
      {:ok, %{}, {:continue, :wake}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:wake, state) do
    Enum.each(Store.list_room_ids(), &Rooms.ensure/1)
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    Store.sweep(@snapshot_ttl_hours)
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end
end
