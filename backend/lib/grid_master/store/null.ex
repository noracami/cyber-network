defmodule GridMaster.Store.Null do
  @moduledoc """
  no-op 儲存（測試環境預設）：房間測試不觸資料庫。
  持久化測試以 `store: GridMaster.Store` 明確換回真實實作。
  """

  def save(_room), do: :ok
  def load(_room_id), do: :none
  def delete(_room_id), do: :ok
  def create_game(_room_id, _engine), do: {:ok, nil}
  def record_action(_game_id, _seq, _round, _player_id, _type, _payload), do: :ok
  def finish_game(_game_id, _attrs), do: :ok
  def abort_game(_game_id), do: :ok
end
