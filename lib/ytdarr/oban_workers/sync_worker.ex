defmodule Ytdarr.ObanWorkers.SyncWorker do
  @moduledoc """
  Oban worker for synchronizing content from external sources.

  This worker handles the synchronization of videos, playlists,
  and channels by fetching updates and ensuring local data is
  up-to-date with the source.
  """

  use Oban.Worker, queue: :sync_worker

  alias Ytdarr.Content
  alias Ytdarr.Content.{Channel, Playlist}
  alias Ytdarr.Settings

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

  defp sync_channel(%Channel{} = channel) do
    Logger.info("Synchronizing channel: #{channel.name}")
    # Fetch latest videos and update local database
    if channel.is_monitored do
      Logger.info("Channel #{channel.name} is monitored, syncing full channel contents")
      Content.sync_channel_content(channel.external_id)

      # schedule the next check for new content based on user settings
      interval_minutes = Settings.get_setting_value(:sync_interval_minutes, 60)

      %{source_type: "channel", source_id: channel.id}
      |> __MODULE__.new(schedule_in: {interval_minutes, :minutes})
      |> Oban.insert()
    else
      Logger.info("Channel #{channel.name} is not monitored, skipping full sync")
    end

    :ok
  end

  defp sync_playlist(%Playlist{} = playlist) do
    Logger.info(
      "Starting playlist sync task for playlist: #{playlist.name} (ID: #{playlist.external_id})"
    )

    # Fetch latest videos and update local database
    if playlist.is_monitored do
      Logger.info(
        "Playlist #{playlist.name} (Owning channel: #{playlist.channel_id}, playlist ID: #{playlist.external_id}) is monitored, syncing"
      )

      # TODO: implement Content.sync_playlist_content/1
      # Content.sync_playlist_content(playlist.external_id)
    else
      Logger.info(
        "Playlist #{playlist.name} (Owning channel: #{playlist.channel_id}, playlist ID: #{playlist.external_id}) is not monitored, skipping"
      )
    end

    :ok
  end
end
