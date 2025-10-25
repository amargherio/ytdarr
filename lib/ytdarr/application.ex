defmodule Ytdarr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      YtdarrWeb.Telemetry,
      Ytdarr.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ytdarr, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ytdarr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ytdarr.PubSub},
      # Starting the HTTP client for Req
      {Finch, name: Ytdarr.Finch},
      # Registry used for caching/storing singleton service processes (e.g. YouTube client)
      {Registry, keys: :unique, name: Ytdarr.Services.Registry},
      Ytdarr.Services.YouTube.ClientSupervisor,
      # Start Oban for background job processing
      # {Oban, Application.fetch_env!(:ytdarr, Oban)},
      # Start a worker by calling: Ytdarr.Worker.start_link(arg)
      # {Ytdarr.Worker, arg},
      # Start to serve requests, typically the last entry
      YtdarrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ytdarr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YtdarrWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
