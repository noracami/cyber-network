import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :grid_master, GridMaster.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("PGHOST", "db"),
  database: "grid_master_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :grid_master, GridMasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Zt/G/QWmKgPEhG7aLI6PyW8bcxZBmVf47KbJqod9V0lbGNdF04vbezrhYZle3+vt",
  server: false

# 測試環境降低 argon2 成本（雜湊本身不是被測物，別讓測試變慢）
config :argon2_elixir, t_cost: 1, m_cost: 8

# 房間測試不觸資料庫（sandbox 連線歸測試進程所有）；
# 持久化測試以 store: GridMaster.Store 明確換回真實實作
config :grid_master, room_store: GridMaster.Store.Null, room_janitor: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
