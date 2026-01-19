defmodule Ytdarr.ObanWorkers.SyncWorker do
  @moduledoc """
  Oban worker for synchronizing content from external sources.

  This worker handles the synchronization of videos, playlists,
  and channels by fetching updates and ensuring local data is
  up-to-date with the source.
  """

  use Oban.Worker, queue: :sync_worker

  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.Content.{Channel, Playlist, Video}
  alias Ytdarr.{Content, Settings}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_type" => source_type, "source_id" => source_id}}) do
    case source_type do
      "channel" ->
        Content.get_channel!(source_id)
        |> sync_channel()

      "playlist" ->
        Content.get_playlist!(source_id)
        |> sync_playlist()

      _ ->
        {:error, :unknown_source_type}
    end
  end

  @doc """
  Syncs channel content, creating any new playlists and videos as needed
  """
  defp sync_channel(%Channel{} = channel) do
    Logger.info("Synchronizing channel: #{channel.name}")
    # Fetch latest videos and update local database
    if channel.is_monitored do
      Logger.info("Channel #{channel.name} is monitored, syncing full channel contents")
      Content.sync_channel_content(channel.external_id)

      # schedule the next check for new content based on user settings
      interval_minutes = Settings.get_setting(:sync_interval_minutes, 60)

      Oban.schedule_in(interval_minutes, __MODULE__, %{
        source_type: "channel",
        source_id: channel.id
      })
    else
      Logger.info("Channel #{channel.name} is not monitored, skipping full sync")
    end

    :ok
  end

  @doc """
  Syncs playlists for a channel, creating any new playlists as needed
  """
  defp sync_playlist(%Playlist{} = playlist) do
    Logger.info(
      "Starting playlist sync task for playlist: #{playlist.name} (ID: #{playlist.external_id})"
    )

    # Fetch latest videos and update local database
    if playlist.is_monitored do
      Logger.info(
        "Playlist #{playlist.name} (Owning channel: #{playlist.channel_id}, playlist ID: #{playlist.external_id}) is monitored, syncing full channel contents"
      )

      Content.sync_playlist_content(playlist.external_id)

      # schedule the next check for new content based on user settings
      interval_minutes = Settings.get_setting(:sync_interval_minutes, 60)

      # Oban.schedule_in(interval_minutes, __MODULE__, %{source_type: "channel", source_id: channel.id})
    else
      Logger.info(
        "Playlist #{playlist.name} (Owning channel: #{playlist.channel_id}, playlist ID: #{playlist.external_id}) is not monitored, skipping full sync"
      )
    end

    :ok
  end
end
