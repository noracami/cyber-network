defmodule GridMasterWeb.ActivityController do
  @moduledoc "全站活動概況——部署腳本以此判斷是否有進行中牌局、可否安全重啟。"

  use GridMasterWeb, :controller

  def show(conn, _params) do
    json(conn, GridMaster.Rooms.activity())
  end
end
