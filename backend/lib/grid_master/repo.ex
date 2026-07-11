defmodule GridMaster.Repo do
  use Ecto.Repo,
    otp_app: :grid_master,
    adapter: Ecto.Adapters.Postgres
end
