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
  end

  scope "/auth", GridMasterWeb do
    pipe_through :auth

    get "/discord", AuthController, :request
    get "/discord/callback", AuthController, :callback
  end
end
