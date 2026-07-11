defmodule GridMasterWeb.PageControllerTest do
  use GridMasterWeb.ConnCase, async: true

  test "GET /：無 SPA 打包時回開發模式提示（生產映像檔則服務 index.html）", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert %{"app" => "grid_master"} = json_response(conn, 200)
  end
end
