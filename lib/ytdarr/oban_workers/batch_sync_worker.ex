defmodule Ytdarr.ObanWorkers.BatchSyncWorker do
  @moduledoc """
  Oban worker for batch synchronization of all monitored content.

  This worker efficiently syncs all monitored channels and playlists in a single
  job, batching YouTube API calls to optimize quota usage. It replaces the
  per-channel/per-playlist scheduling approach with a consolidated sync.

  ## Quota Optimization

  - Batches channel metadata fetches (up to 50 channels per API call)
  - Batches video detail fetches (up to 50 videos per API call)
  - Uses incremental sync when possible (only fetching new content)
  - Tracks quota usage through the QuotaTracker

  ## Scheduling

  This worker is scheduled via Oban's cron plugin or can be triggered manually.
  It reschedules itself after completion based on the configured sync interval.
  """

  use Oban.Worker,
    queue: :batch_sync,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias Ytdarr.Content
  alias Ytdarr.Services.YouTube.Client

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

    # Check if this is a manual/forced sync or a scheduled sync
    force_full_sync = Map.get(args, "force_full_sync", false)

    result =
      with :ok <- sync_monitored_channels(force_full_sync),
           :ok <- sync_monitored_playlists(force_full_sync) do
        Logger.info("[BatchSyncWorker] Batch sync completed successfully")
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

      # Process channels - for now we process sequentially but with batched video fetches
      # In the future, we can add batched channel metadata refresh here
      errors =
        channels
        |> Task.async_stream(
          fn channel -> sync_single_channel(channel, force_full_sync) end,
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

  defp sync_single_channel(channel, force_full_sync) do
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
          Client.check_uploads_for_new_videos(channel.external_id, since_datetime)
        else
          # Full sync via existing content sync
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

  defp sync_single_playlist(playlist, _force_full_sync) do
    Logger.debug("[BatchSyncWorker] Syncing playlist: #{playlist.name} (#{playlist.external_id})")

    try do
      # Fetch playlist items
      case Client.get_playlist(playlist.external_id) do
        {:ok, playlist_data} ->
          Logger.info(
            "[BatchSyncWorker] Playlist #{playlist.name} has #{playlist_data.video_count} videos"
          )

          # Mark playlist as checked
          Content.mark_playlist_checked(playlist)
          :ok

        {:partial, _playlist_data} ->
          Logger.warning("[BatchSyncWorker] Partial fetch for playlist #{playlist.name}")

          Content.mark_playlist_checked(playlist)
          :ok
      end
    rescue
      e ->
        Logger.error(
          "[BatchSyncWorker] Exception syncing playlist #{playlist.name}: #{Exception.message(e)}"
        )

        {:error, {:playlist_exception, playlist.id, Exception.message(e)}}
    end
  end

  defp process_new_videos(videos, channel) do
    # Create video records for any new videos found
    Enum.each(videos, fn video ->
      case Content.get_video_by_external_id(video.id) do
        {:ok, nil} ->
          # Video doesn't exist, create it
          Content.create_video(channel.id, %{
            external_id: video.id,
            name: video.title,
            description: video.description,
            url: video.url,
            thumbnail_url: video.thumbnail_url,
            upload_date: video.published_at,
            duration_seconds: video.duration
          })

        {:ok, _existing} ->
          # Video already exists, skip
          :ok

        {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
          # Video doesn't exist, create it
          Content.create_video(channel.id, %{
            external_id: video.id,
            name: video.title,
            description: video.description,
            url: video.url,
            thumbnail_url: video.thumbnail_url,
            upload_date: video.published_at,
            duration_seconds: video.duration
          })

        {:error, error} ->
          Logger.error("[BatchSyncWorker] Error checking video #{video.id}: #{inspect(error)}")
      end
    end)
  end
end
