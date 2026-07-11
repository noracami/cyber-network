defmodule GridMasterWeb.Router do
  use GridMasterWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", GridMasterWeb do
    pipe_through :api

    get "/static", StaticDataController, :show
  end
end
