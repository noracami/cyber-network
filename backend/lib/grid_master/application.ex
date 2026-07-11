defmodule GridMaster.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GridMasterWeb.Telemetry,
      GridMaster.Repo,
      {DNSCluster, query: Application.get_env(:grid_master, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GridMaster.PubSub},
      # Start a worker by calling: GridMaster.Worker.start_link(arg)
      # {GridMaster.Worker, arg},
      # Start to serve requests, typically the last entry
      GridMasterWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GridMaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GridMasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
