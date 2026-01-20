defmodule Ytdarr.Services.YouTube.ClientSupervisor do
  @moduledoc """
  Manages the YouTube API client, dynamically fetching the API key from Settings.

  The API key is fetched from the database on each client creation, ensuring
  that updates to the API key in Settings are reflected without restart.
  """

  @base_url "https://www.googleapis.com/youtube/v3"

  use GenServer

  alias Ytdarr.Settings

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current API key from settings.
  """
  def get_api_key do
    Settings.get_setting_value("youtube.primary_api_key")
  end

  def get_client do
    case Registry.lookup(Ytdarr.Services.Registry, :youtube_client) do
      [{pid, _client}] when is_pid(pid) ->
        # Always create a fresh client to pick up any API key changes
        create_client()

      [] ->
        create_client()
    end
  end

  @doc """
  Refreshes the client with the current API key from Settings.
  Call this after changing the API key to ensure the new key is used.
  """
  def refresh_client do
    GenServer.call(__MODULE__, :refresh_client)
  end

  def init(_opts) do
    client = create_client()
    Registry.register(Ytdarr.Services.Registry, :youtube_client, client)
    {:ok, %{client: client}}
  end

  def handle_call(:refresh_client, _from, state) do
    client = create_client()

    # Update the registry with the new client
    Registry.update_value(Ytdarr.Services.Registry, :youtube_client, fn _ -> client end)

    {:reply, :ok, %{state | client: client}}
  end

  defp create_client do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning(
        "[YouTube.ClientSupervisor] No API key configured. YouTube API calls will fail."
      )
    end

    Req.new(
      base_url: @base_url,
      headers: %{
        accept: "application/json",
        user_agent: "Ytdarr/1.0"
      },
      params: [key: api_key || ""],
      finch: Ytdarr.Finch
    )
  end
end
