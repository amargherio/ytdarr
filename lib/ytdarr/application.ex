defmodule Ytdarr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Cachex.Spec

  @impl true
  def start(_type, _args) do
    # Attach Oban telemetry logger (this is not a child spec, just setup)
    :ok = Oban.Telemetry.attach_default_logger()

    # Attach custom telemetry handler for VideoDownloader cancellation/failure
    :ok =
      :telemetry.attach(
        "video-downloader-reset-handler",
        [:oban, :job, :exception],
        &Ytdarr.ObanWorkers.VideoDownloaderTelemetry.handle_event/4,
        %{}
      )

    :ok =
      :telemetry.attach(
        "video-downloader-stop-handler",
        [:oban, :job, :stop],
        &Ytdarr.ObanWorkers.VideoDownloaderTelemetry.handle_event/4,
        %{}
      )

    children = [
      YtdarrWeb.Telemetry,
      Ytdarr.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ytdarr, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ytdarr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ytdarr.PubSub},
      # Starting the HTTP client for Req
      {Finch, name: Ytdarr.Finch},
      # Load settings from environment variables into database (runs once at startup)
      Ytdarr.Settings.StartupLoader,
      # Registry used for caching/storing singleton service processes (e.g. YouTube client)
      {Registry, keys: :unique, name: Ytdarr.Services.Registry},
      Ytdarr.Services.YouTube.ClientSupervisor,
      # YouTube API quota tracker (must start after Repo for persistence)
      Ytdarr.Services.YouTube.QuotaTracker,
      # Download progress tracker (must start before Oban so it's ready for job events)
      Ytdarr.Downloads.Tracker,
      # Start Oban for background job processing
      {Oban, Application.fetch_env!(:ytdarr, Oban)},
      # Image cache (in-memory layer backed by filesystem)
      {Cachex,
       name: :image_cache,
       expiration: Cachex.Spec.expiration(default: :timer.hours(24), interval: :timer.minutes(15))},
      # Start to serve requests, typically the last entry
      YtdarrWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :ytdarr]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ytdarr.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Schedule initial batch sync after all services are started
    schedule_initial_batch_sync()

    result
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

  defp schedule_initial_batch_sync do
    # Schedule the first batch sync with a 2-minute delay to let the app fully boot
    %{}
    |> Ytdarr.ObanWorkers.BatchSyncWorker.new(schedule_in: 120)
    |> Oban.insert()
  end
end
