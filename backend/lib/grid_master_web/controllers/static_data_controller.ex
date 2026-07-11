defmodule GridMasterWeb.StaticDataController do
  @moduledoc "提供前端渲染所需的靜態遊戲數據（地圖／卡牌／規則表），單一數據源。"

  use GridMasterWeb, :controller

  alias GridMaster.Data

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(%{map: Data.map(), deck: Data.deck(), rules: Data.rules()})
  end
end
