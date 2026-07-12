# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :grid_master,
  ecto_repos: [GridMaster.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :grid_master, GridMasterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: GridMasterWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GridMaster.PubSub,
  live_view: [signing_salt: "7iaI+neb"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Admin 身份 token（開發預設值；生產環境由 runtime.exs 以 ADMIN_TOKEN 環境變數覆蓋）
config :grid_master, admin_token: "dev-admin-token"

# 房間持久化（PRD-v1.5 R1）：測試環境換成 no-op Store 並停用管家
config :grid_master, room_store: GridMaster.Store, room_janitor: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
