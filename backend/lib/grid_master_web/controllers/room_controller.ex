defmodule GridMasterWeb.RoomController do
  @moduledoc """
  房間列表 API（PRD-v1.5 R2）：main 大廳側欄輪詢用。
  只列活躍進程——閒置關閉但快照仍在的房間，有人循連結回來會自動復活。
  """

  use GridMasterWeb, :controller

  def index(conn, _params) do
    json(conn, %{rooms: GridMaster.Rooms.list()})
  end
end
