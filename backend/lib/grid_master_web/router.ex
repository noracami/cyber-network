defmodule GridMasterWeb.Router do
  use GridMasterWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug :fetch_session
  end

  scope "/api", GridMasterWeb do
    pipe_through :api

    get "/static", StaticDataController, :show
    get "/activity", ActivityController, :show
    get "/rooms", RoomController, :index

    post "/auth/register", AccountController, :register
    post "/auth/login", AccountController, :login
  end

  # SPA 入口（生產環境由 Phoenix 服務 Vue dist），不走 :api 的 JSON 協商
  scope "/", GridMasterWeb do
    get "/", PageController, :index
  end

  scope "/auth", GridMasterWeb do
    pipe_through :auth

    get "/discord", AuthController, :request
    get "/discord/callback", AuthController, :callback
  end
end
