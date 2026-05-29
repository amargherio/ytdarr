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
  alias Ytdarr.Services.YouTube.QuotaTracker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_type" => source_type, "source_id" => source_id}}) do
    estimated_cost =
      case source_type do
        "channel" -> QuotaTracker.estimate_batch_cost(:channel_sync, 1)
        "playlist" -> QuotaTracker.estimate_batch_cost(:playlist_sync, 1)
        _ -> 0
      end

    if QuotaTracker.can_afford?(:read, estimated_cost) do
      perform_sync(source_type, source_id)
    else
      %{remaining: remaining} = QuotaTracker.get_usage()

      Logger.warning(
        "[SyncWorker] Insufficient quota for #{source_type} sync. " <>
          "Estimated cost: #{estimated_cost}, remaining: #{remaining}. Deferring."
      )

      {:snooze, seconds_until_quota_reset()}
    end
  end

  defp perform_sync(source_type, source_id) do
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

  # Calculates seconds until the YouTube API quota resets (midnight PT).
  defp seconds_until_quota_reset do
    now = DateTime.utc_now()
    # YouTube resets at midnight Pacific Time (UTC-8 / UTC-7 DST)
    # Use UTC-8 as worst case (longest wait)
    pt_offset_hours = -8
    pt_now = DateTime.add(now, pt_offset_hours * 3600, :second)
    midnight_pt = %{pt_now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    next_midnight_pt =
      if DateTime.compare(pt_now, midnight_pt) == :gt do
        DateTime.add(midnight_pt, 86_400, :second)
      else
        midnight_pt
      end

    # Convert back to UTC and calculate diff
    next_midnight_utc = DateTime.add(next_midnight_pt, -pt_offset_hours * 3600, :second)
    max(DateTime.diff(next_midnight_utc, now, :second), 60)
  end
end
