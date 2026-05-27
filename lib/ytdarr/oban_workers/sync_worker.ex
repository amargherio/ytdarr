defmodule Ytdarr.ObanWorkers.SyncWorker do
  @moduledoc """
  Oban worker for user-initiated synchronization of individual content.

  This worker handles on-demand synchronization of a single channel or playlist
  when triggered by user action (e.g., "Sync Now" button). It does NOT
  self-reschedule - scheduled syncing is handled by BatchSyncWorker.

  ## Usage

  For user-initiated sync:

      %{source_type: "channel", source_id: channel_id}
      |> SyncWorker.new()
      |> Oban.insert()

  For scheduled batch sync of all monitored content, use BatchSyncWorker instead.
  """

  use Oban.Worker,
    queue: :sync_worker,
    max_attempts: 3

  alias Ytdarr.Content
  alias Ytdarr.Content.{Channel, Playlist}

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
    Logger.info("[SyncWorker] User-initiated sync for channel: #{channel.name}")

    # Always sync when user-initiated, regardless of monitoring status
    Content.sync_channel_content(channel.external_id)
    Content.mark_channel_checked(channel)

    Logger.info("[SyncWorker] Completed sync for channel: #{channel.name}")
    :ok
  end

  defp sync_playlist(%Playlist{} = playlist) do
    Logger.info(
      "[SyncWorker] User-initiated sync for playlist: #{playlist.name} (ID: #{playlist.external_id})"
    )

    Content.sync_playlist_content(playlist.id)
    Content.mark_playlist_checked(playlist)

    Logger.info("[SyncWorker] Completed sync for playlist: #{playlist.name}")
    :ok
  end
end
