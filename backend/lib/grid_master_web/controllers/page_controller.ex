defmodule GridMasterWeb.PageController do
  @moduledoc """
  SPA 入口。生產映像檔把 Vue dist 放進 priv/static，由 Phoenix 同源服務；
  開發環境沒有這個檔案（前端走 Vite :5173），回一個提示 JSON。
  """

  use GridMasterWeb, :controller

  def index(conn, _params) do
    index_file = Application.app_dir(:grid_master, "priv/static/index.html")

    if File.exists?(index_file) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index_file)
    else
      json(conn, %{app: "grid_master", note: "開發模式請由 Vite（localhost:5173）進入"})
    end
  end
end
