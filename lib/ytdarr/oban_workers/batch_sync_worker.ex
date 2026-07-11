defmodule Ytdarr.ObanWorkers.BatchSyncWorker do
  @moduledoc """
  Oban worker for scheduled batch synchronization of all monitored content.

  Runs on a configurable interval (default 60 minutes) and syncs every
  monitored channel and playlist in a single job, using batched and
  incremental API calls to minimize YouTube quota consumption.

  ## Quota Optimization Strategies

  1. **Pre-flight check:** Before starting, estimates the total cost via
     `QuotaTracker.estimate_batch_cost/2` and aborts if the remaining
     daily budget is insufficient.

  2. **Batched metadata refresh:** All monitored channel metadata is fetched
     in a single `Client.get_channels_batch/1` call (1 unit per 50 channels)
     instead of N individual calls.

  3. **Incremental uploads sync:** Uses `Client.check_uploads_for_new_videos/2`
     with the channel's `last_checked_at` timestamp, stopping pagination early
     once it encounters old items.

  4. **Incremental playlist sync:** Uses `Client.check_playlist_for_new_videos/3`
     with the playlist's `last_checked_at`, applying the same early-termination
     strategy.

  5. **Video cache threading:** During full channel syncs, the uploads video
     cache is threaded through to playlist syncs to avoid redundant detail
     fetches (handled by `Content.sync_channel_content/1`).

  ## Scheduling

  After each run, the worker schedules its next execution based on the
  `sync_interval_minutes` setting. Manual runs can be triggered with
  `force_full_sync: true` to bypass incremental mode.

  See `docs/youtube-api-integration.md` for the full integration guide.
  """

  use Oban.Worker,
    queue: :batch_sync,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing, :retryable, :suspended]]

  alias Ytdarr.Content
  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.Services.YouTube.QuotaTracker

  require Logger

  @doc """
  Schedules a batch sync job to run at the configured interval.
  """
  def schedule_next_sync do
    interval_minutes = Ytdarr.Settings.get_setting_value(:sync_interval_minutes, 60)

    %{}
    |> __MODULE__.new(schedule_in: {interval_minutes, :minutes})
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("[BatchSyncWorker] Starting batch sync of all monitored content")

    force_full_sync = Map.get(args, "force_full_sync", false)

    # Pre-flight quota check: estimate cost and verify we have enough budget
    channels = Content.list_monitored_channels!()
    playlists = Content.list_monitored_playlists!()

    estimated_cost =
      QuotaTracker.estimate_batch_cost(:channel_sync, length(channels)) +
        QuotaTracker.estimate_batch_cost(:playlist_sync, length(playlists))

    result =
      if QuotaTracker.can_afford?(:read, estimated_cost) do
        with :ok <- sync_monitored_channels(force_full_sync),
             :ok <- sync_monitored_playlists(force_full_sync) do
          Logger.info("[BatchSyncWorker] Batch sync completed successfully")
          :ok
        end
      else
        %{remaining: remaining} = QuotaTracker.get_usage()

        Logger.warning(
          "[BatchSyncWorker] Insufficient quota for batch sync. " <>
            "Estimated cost: #{estimated_cost}, remaining: #{remaining}. Skipping this run."
        )

        :ok
      end

    # Schedule the next sync (unless this was a manual one-off)
    unless Map.get(args, "one_off", false) do
      schedule_next_sync()
    end

    result
  end

  defp sync_monitored_channels(force_full_sync) do
    channels = Content.list_monitored_channels!()

    if channels == [] do
      Logger.info("[BatchSyncWorker] No monitored channels to sync")
      :ok
    else
      Logger.info("[BatchSyncWorker] Syncing #{length(channels)} monitored channels")

      # For incremental syncs, batch-refresh channel metadata upfront (1 API call per 50 channels)
      # instead of N individual calls. Full syncs refresh metadata inline.
      channel_metadata =
        if not force_full_sync do
          batch_refresh_channel_metadata(channels)
        else
          %{}
        end

      errors =
        channels
        |> Task.async_stream(
          fn channel -> sync_single_channel(channel, force_full_sync, channel_metadata) end,
          max_concurrency: 2,
          timeout: :timer.minutes(5)
        )
        |> Enum.filter(fn
          {:ok, :ok} -> false
          {:ok, {:error, _}} -> true
          {:exit, _} -> true
        end)
        |> Enum.map(fn
          {:ok, {:error, reason}} -> reason
          {:exit, reason} -> {:task_exit, reason}
        end)

      if errors == [] do
        Logger.info("[BatchSyncWorker] All #{length(channels)} channels synced successfully")
        :ok
      else
        Logger.warning(
          "[BatchSyncWorker] Completed with #{length(errors)} errors: #{inspect(errors)}"
        )

        # Return ok even with partial failures - we don't want to retry the whole batch
        :ok
      end
    end
  end

  defp sync_single_channel(channel, force_full_sync, channel_metadata) do
    Logger.debug("[BatchSyncWorker] Syncing channel: #{channel.name} (#{channel.external_id})")

    try do
      # Use incremental sync if not forced and we have a last_checked_at
      since_datetime =
        if force_full_sync or is_nil(channel.last_checked_at) do
          nil
        else
          channel.last_checked_at
        end

      # Use the optimized check_uploads_for_new_videos for incremental sync
      result =
        if since_datetime do
          # Incremental sync — apply pre-fetched metadata and refresh images
          apply_batched_metadata(channel, channel_metadata)

          Client.check_uploads_for_new_videos(channel.external_id, since_datetime)
        else
          # Full sync via existing content sync (which already refreshes metadata)
          Content.sync_channel_content(channel.external_id)
          {:ok, :full_sync}
        end

      # Mark channel as checked
      Content.mark_channel_checked(channel)

      case result do
        {:ok, videos} when is_list(videos) ->
          Logger.info("[BatchSyncWorker] Found #{length(videos)} new videos for #{channel.name}")

          # Process new videos
          process_new_videos(videos, channel)
          :ok

        {:ok, :full_sync} ->
          :ok

        {:partial, videos} when is_list(videos) ->
          Logger.warning(
            "[BatchSyncWorker] Partial sync for #{channel.name}, got #{length(videos)} videos with some errors"
          )

          process_new_videos(videos, channel)
          :ok

        {:error, reason} ->
          Logger.error(
            "[BatchSyncWorker] Failed to sync channel #{channel.name}: #{inspect(reason)}"
          )

          {:error, {:channel_sync_failed, channel.id, reason}}
      end
    rescue
      e ->
        Logger.error(
          "[BatchSyncWorker] Exception syncing channel #{channel.name}: #{Exception.message(e)}"
        )

        {:error, {:channel_exception, channel.id, Exception.message(e)}}
    end
  end

  # Batch-fetch metadata for all channels with a single API call (per 50 channels)
  # instead of one API call per channel. Returns a map of %{external_id => yt_channel}.
  defp batch_refresh_channel_metadata(channels) do
    channel_ids = Enum.map(channels, & &1.external_id)

    case Client.get_channels_batch(channel_ids) do
      {:ok, yt_channels} ->
        Map.new(yt_channels, fn ch -> {ch.external_id, ch} end)

      {:partial, yt_channels, _errors} ->
        Map.new(yt_channels, fn ch -> {ch.external_id, ch} end)

      {:error, reason} ->
        Logger.warning(
          "[BatchSyncWorker] Batch channel metadata fetch failed: #{inspect(reason)}"
        )

        %{}
    end
  end

  # Apply pre-fetched channel metadata and refresh images.
  # Falls back to per-channel fetch if metadata wasn't available in the batch result.
  defp apply_batched_metadata(channel, channel_metadata) do
    case Map.get(channel_metadata, channel.external_id) do
      nil ->
        refresh_channel_metadata(channel)

      yt_channel ->
        updates =
          %{}
          |> maybe_put(:avatar_url, yt_channel.avatar_url, channel.avatar_url)
          |> maybe_put(:banner_url, yt_channel.banner_url, channel.banner_url)

        if map_size(updates) > 0 do
          Content.update_channel(channel, updates)
        end

        Content.refresh_channel_images(channel)
    end
  end

  # Per-channel metadata refresh fallback (1 API call per channel).
  defp refresh_channel_metadata(channel) do
    case Client.get_channel(channel.external_id) do
      {:ok, yt_channel} ->
        updates =
          %{}
          |> maybe_put(:avatar_url, yt_channel.avatar_url, channel.avatar_url)
          |> maybe_put(:banner_url, yt_channel.banner_url, channel.banner_url)

        if map_size(updates) > 0 do
          Content.update_channel(channel, updates)
        end

        Content.refresh_channel_images(channel)

      {:error, reason} ->
        Logger.warning(
          "[BatchSyncWorker] Failed to refresh metadata for #{channel.name}: #{inspect(reason)}"
        )
    end
  end

  defp maybe_put(map, key, new_val, old_val) when new_val != old_val and not is_nil(new_val) do
    Map.put(map, key, new_val)
  end

  defp maybe_put(map, _key, _new_val, _old_val), do: map

  defp sync_monitored_playlists(force_full_sync) do
    playlists = Content.list_monitored_playlists!()

    if playlists == [] do
      Logger.info("[BatchSyncWorker] No monitored playlists to sync")
      :ok
    else
      Logger.info("[BatchSyncWorker] Syncing #{length(playlists)} monitored playlists")

      errors =
        playlists
        |> Task.async_stream(
          fn playlist -> sync_single_playlist(playlist, force_full_sync) end,
          max_concurrency: 2,
          timeout: :timer.minutes(5)
        )
        |> Enum.filter(fn
          {:ok, :ok} -> false
          {:ok, {:error, _}} -> true
          {:exit, _} -> true
        end)
        |> Enum.map(fn
          {:ok, {:error, reason}} -> reason
          {:exit, reason} -> {:task_exit, reason}
        end)

      if errors == [] do
        Logger.info("[BatchSyncWorker] All #{length(playlists)} playlists synced successfully")
        :ok
      else
        Logger.warning("[BatchSyncWorker] Playlist sync completed with #{length(errors)} errors")

        :ok
      end
    end
  end

  defp sync_single_playlist(playlist, force_full_sync) do
    Logger.debug("[BatchSyncWorker] Syncing playlist: #{playlist.name} (#{playlist.external_id})")

    try do
      since_datetime =
        if not force_full_sync and playlist.last_checked_at do
          playlist.last_checked_at
        end

      if since_datetime do
        # Incremental sync: only fetch videos added since last check
        Logger.info(
          "[BatchSyncWorker] Incremental sync for playlist #{playlist.name} since #{since_datetime}"
        )

        case Client.check_playlist_for_new_videos(playlist.external_id, since_datetime) do
          {:ok, []} ->
            Logger.debug("[BatchSyncWorker] No new items in playlist #{playlist.name}")
            Content.mark_playlist_checked(playlist)
            :ok

          {status, entries} when status in [:ok, :partial] ->
            Logger.info(
              "[BatchSyncWorker] Found #{length(entries)} new items in playlist #{playlist.name}"
            )

            process_playlist_entries(playlist, entries)
            Content.mark_playlist_checked(playlist)
            :ok

          {:error, reason} ->
            Logger.error(
              "[BatchSyncWorker] Error in incremental sync for #{playlist.name}: #{inspect(reason)}"
            )

            {:error, {:playlist_sync, playlist.id, reason}}
        end
      else
        # Full sync: fetch all playlist items with details
        Logger.info("[BatchSyncWorker] Full sync for playlist #{playlist.name}")

        case Client.get_playlist_items_detailed(playlist.external_id) do
          {status, %{videos: entries}} when status in [:ok, :partial] ->
            Logger.info(
              "[BatchSyncWorker] Fetched #{length(entries)} items for playlist #{playlist.name}"
            )

            process_playlist_entries(playlist, entries)
            Content.mark_playlist_checked(playlist)
            :ok
        end
      end
    rescue
      e ->
        Logger.error(
          "[BatchSyncWorker] Exception syncing playlist #{playlist.name}: #{Exception.message(e)}"
        )

        {:error, {:playlist_exception, playlist.id, Exception.message(e)}}
    end
  end

  defp process_playlist_entries(playlist, entries) do
    Content.upsert_and_link_playlist_entries(playlist, entries)
  end

  defp process_new_videos(videos, channel) do
    Enum.each(videos, fn video ->
      Content.upsert_video(channel.id, %{
        external_id: video.id,
        title: video.title,
        description: video.description,
        url: video.url,
        thumbnail_url: video.thumbnail_url,
        upload_date: video.published_at,
        duration: video.duration,
        discovered_from: "uploads"
      })
    end)
  end
end
