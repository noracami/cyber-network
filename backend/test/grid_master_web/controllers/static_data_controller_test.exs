defmodule GridMasterWeb.StaticDataControllerTest do
  use GridMasterWeb.ConnCase, async: true

  test "GET /api/static 回傳地圖、牌庫與規則", %{conn: conn} do
    body = conn |> get(~p"/api/static") |> json_response(200)

    assert length(body["map"]["cities"]) == 42
    assert length(body["deck"]["plants"]) == 42
    assert body["rules"]["starting_credits"] == 50
  end
end
