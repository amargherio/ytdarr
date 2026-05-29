defmodule Ytdarr.Content do
  @moduledoc """
  The Content domain handles channels, videos, and playlists.
  """
  use Ash.Domain,
    otp_app: :ytdarr,
    extensions: [AshAdmin.Domain, AshPhoenix]

  alias Ytdarr.Content.{Channel, Video, Playlist}
  alias Ytdarr.Services.YouTube.Client

  require Ash.Query
  require Logger

  admin do
    show? true
  end

  resources do
    resource Channel do
      define :list_channels, action: :read
      define :list_monitored_channels, action: :monitored
      define :get_channel, action: :read, get_by: [:id]
      define :get_channel_by_external_id, action: :read, get_by: [:external_id]
      define :create_channel, action: :create
      define :update_channel, action: :update
      define :monitor_channel, action: :monitor
      define :unmonitor_channel, action: :unmonitor
      define :toggle_channel_monitor, action: :toggle_monitor
      define :mark_channel_checked, action: :mark_checked
      define :destroy_channel, action: :destroy
    end

    resource Video do
      define :list_videos, action: :read
      define :get_video, action: :read, get_by: [:id]
      define :get_video_by_external_id, action: :read, get_by: [:external_id]
      define :create_video, action: :create, args: [:channel_id]
      define :upsert_video, action: :upsert, args: [:channel_id]
      define :update_video, action: :update
      define :mark_video_downloaded, action: :mark_downloaded
      define :destroy_video, action: :destroy
    end

    resource Playlist do
      define :list_playlists, action: :read
      define :list_monitored_playlists, action: :monitored
      define :get_playlist, action: :read, get_by: [:id]
      define :get_playlist_by_external_id, action: :read, get_by: [:external_id]
      define :create_playlist, action: :create, args: [:channel_id]
      define :upsert_playlist, action: :upsert, args: [:channel_id]
      define :update_playlist, action: :update
      define :monitor_playlist, action: :monitor
      define :unmonitor_playlist, action: :unmonitor
      define :toggle_playlist_monitor, action: :toggle_monitor
      define :mark_playlist_checked, action: :mark_checked
      define :destroy_playlist, action: :destroy
    end

    resource Ytdarr.Content.PlaylistVideo do
      define :create_playlist_video, action: :create
      define :upsert_playlist_video, action: :upsert
    end
  end

  ## Complex operations that orchestrate syncing

  @doc """
  Creates an AshPhoenix form for creating a new channel.
  """
  def form_to_create_channel do
    AshPhoenix.Form.for_create(Channel, :create, domain: __MODULE__, as: "channel")
  end

  @doc """
  Creates an AshPhoenix form for updating an existing channel.
  """
  def form_to_update_channel(channel) do
    AshPhoenix.Form.for_update(channel, :update, domain: __MODULE__, as: "channel")
  end

  @doc """
  Searches channels, playlists, and videos in the local database.

  Returns a map with `:channels`, `:playlists`, and `:videos` keys,
  each containing at most 5 matching results. Returns empty lists
  when the query is shorter than 2 characters.
  """
  def omnisearch(query) when is_binary(query) and byte_size(query) >= 2 do
    like = query

    channels =
      Channel
      |> Ash.Query.filter(contains(name, ^like) or contains(platform_username, ^like))
      |> Ash.Query.sort(name: :asc)
      |> Ash.Query.limit(5)
      |> Ash.read!()

    playlists =
      Playlist
      |> Ash.Query.filter(contains(name, ^like))
      |> Ash.Query.sort(name: :asc)
      |> Ash.Query.limit(5)
      |> Ash.Query.load([:channel])
      |> Ash.read!()

    videos =
      Video
      |> Ash.Query.filter(contains(title, ^like))
      |> Ash.Query.sort(title: :asc)
      |> Ash.Query.limit(5)
      |> Ash.Query.load([:channel])
      |> Ash.read!()

    %{channels: channels, playlists: playlists, videos: videos}
  end

  def omnisearch(_query), do: %{channels: [], playlists: [], videos: []}

  @doc """
  Search for channels via YouTube API and check monitoring status.
  """
  def search_for_channels(query) do
    case Client.search_channels(query) do
      {:ok, channels} ->
        enriched_channels =
          Enum.map(channels, fn channel ->
            case get_channel_by_external_id(channel.external_id) do
              {:ok, %Channel{} = existing_channel} ->
                # If channel exists in DB, use its monitored status
                %{channel | is_monitored: existing_channel.is_monitored}

              _ ->
                # Otherwise, it's not monitored (default is already false in struct)
                channel
            end
          end)

        {:ok, enriched_channels}

      error ->
        error
    end
  end

  @doc """
  Search for playlists from monitored channels via YouTube API.
  Fetches playlists for each monitored channel and filters by query string.
  """
  def search_for_playlists(query) do
    channels = list_channels!(query: [filter: [is_monitored: true]])

    if channels == [] do
      {:ok, []}
    else
      monitored_playlist_ids =
        list_playlists!() |> Enum.map(& &1.external_id) |> MapSet.new()

      playlists =
        channels
        |> Task.async_stream(
          fn channel ->
            case Client.get_channel_playlists(channel.external_id) do
              {:ok, yt_playlists} ->
                Enum.map(yt_playlists, fn pl ->
                  %{
                    external_id: pl.id,
                    name: pl.title,
                    url: pl.url,
                    video_count: pl.video_count,
                    channel_id: channel.id,
                    channel_name: channel.name,
                    is_monitored: MapSet.member?(monitored_playlist_ids, pl.id)
                  }
                end)

              _ ->
                []
            end
          end,
          timeout: :infinity,
          max_concurrency: 5
        )
        |> Enum.flat_map(fn
          {:ok, results} -> results
          _ -> []
        end)
        |> filter_playlists_by_query(query)

      {:ok, playlists}
    end
  end

  defp filter_playlists_by_query(playlists, query) do
    query_lower = String.downcase(query)

    Enum.filter(playlists, fn pl ->
      String.contains?(String.downcase(pl.name), query_lower)
    end)
  end

  @doc """
  Sync channel or playlist content with the latest from the source.
  Queues an Oban job to perform the actual sync.
  """
  def sync_content(target_type, target_id) do
    case target_type do
      "channel" ->
        %{"source_type" => "channel", "source_id" => target_id}
        |> Ytdarr.ObanWorkers.SyncWorker.new()
        |> Oban.insert()

      "playlist" ->
        %{"source_type" => "playlist", "source_id" => target_id}
        |> Ytdarr.ObanWorkers.SyncWorker.new()
        |> Oban.insert()

      _ ->
        {:error, :unknown_target_type}
    end
  end

  @doc """
  Fetch latest content from external API (e.g., YouTube).
  Creates/updates videos and playlists for a channel, then links them via PlaylistVideo.

  Flow:
  1. Fetch channel metadata from API, update DB record
  2. Refresh channel images
  3. Fetch ALL videos from uploads playlist → upsert each into DB
  4. Fetch channel playlists from API → upsert each into DB
  5. For each playlist: fetch items, upsert videos, create PlaylistVideo links
  """
  def sync_channel_content(channel_id) do
    with {:ok, db_channel} <- get_channel_by_external_id(channel_id),
         true <- not is_nil(db_channel) do
      # Step 1: Refresh channel metadata from API
      {uploads_playlist_id, db_channel} = sync_channel_metadata(db_channel, channel_id)

      # Step 2: Refresh cached images
      refresh_channel_images(db_channel)

      # Step 3: Sync all videos from uploads playlist, building a video detail cache
      video_cache = sync_uploads(db_channel, uploads_playlist_id)

      # Step 4 & 5: Fetch playlists, then for each playlist fetch items and link videos.
      # Reuses video_cache from uploads to avoid re-fetching the same video details.
      sync_playlists_and_link_videos(db_channel, channel_id, video_cache)

      {:ok, :synced}
    else
      {:ok, nil} -> {:error, :channel_not_found}
      false -> {:error, :channel_not_found}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Sync a single playlist's content from the YouTube API.
  Fetches the playlist's video list, upserts video records,
  and creates playlist↔video associations. Does NOT auto-queue downloads.
  """
  def sync_playlist_content(playlist_id) when is_integer(playlist_id) do
    case get_playlist(playlist_id) do
      {:ok, playlist} -> sync_playlist_content(playlist)
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_playlist_content(playlist) do
    # Load channel for creating video records
    channel =
      case Ash.load(playlist, :channel) do
        {:ok, loaded} -> loaded.channel
        _ -> nil
      end

    if is_nil(channel) do
      Logger.error("[Content] Cannot sync playlist #{playlist.id}: no channel found")
      {:error, :channel_not_found}
    else
      fetch_and_link_playlist_videos(channel, playlist)
      {:ok, :synced}
    end
  end

  @doc """
  Refresh cached images for a channel (avatar and banner) using ETag-based conditional requests.
  """
  def refresh_channel_images(channel) do
    alias Ytdarr.Cache.ImageCache

    Enum.each(~w(avatar banner), fn type ->
      case ImageCache.refresh(channel, type) do
        :refreshed ->
          Logger.info("Refreshed #{type} image for channel #{channel.name}")

        :not_modified ->
          Logger.debug("#{type} image for channel #{channel.name} not modified")

        {:error, reason} ->
          Logger.warning(
            "Failed to refresh #{type} image for channel #{channel.name}: #{inspect(reason)}"
          )
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Internal sync helpers
  # ---------------------------------------------------------------------------

  # Step 1: Fetch channel metadata from API and update DB record
  defp sync_channel_metadata(db_channel, channel_id) do
    case Client.get_channel(channel_id) do
      {:ok, yt_channel} ->
        uploads_playlist_id = yt_channel.uploads_playlist_id

        updates =
          %{}
          |> maybe_put_changed(
            :uploads_playlist_id,
            uploads_playlist_id,
            db_channel.uploads_playlist_id
          )
          |> maybe_put_changed(:avatar_url, yt_channel.avatar_url, db_channel.avatar_url)
          |> maybe_put_changed(:banner_url, yt_channel.banner_url, db_channel.banner_url)

        db_channel =
          if map_size(updates) > 0 do
            case update_channel(db_channel, updates) do
              {:ok, updated} -> updated
              _ -> db_channel
            end
          else
            db_channel
          end

        {uploads_playlist_id, db_channel}

      {:error, reason} ->
        Logger.error("Error fetching channel data for #{channel_id}: #{inspect(reason)}")
        {db_channel.uploads_playlist_id, db_channel}
    end
  end

  defp maybe_put_changed(map, _key, nil, _old), do: map
  defp maybe_put_changed(map, key, new, old) when new != old, do: Map.put(map, key, new)
  defp maybe_put_changed(map, _key, _new, _old), do: map

  # Step 3: Fetch and upsert all videos from the uploads playlist.
  # Returns a video_cache map (%{video_id => raw_api_data}) for reuse by playlist sync.
  defp sync_uploads(_db_channel, nil), do: %{}

  defp sync_uploads(db_channel, uploads_playlist_id) do
    {status, %{videos: entries, video_cache: video_cache}} =
      Client.get_playlist_items_detailed(uploads_playlist_id)

    if status in [:ok, :partial] do
      Logger.info(
        "[Content] Syncing #{length(entries)} upload videos for channel #{db_channel.name}"
      )

      Enum.each(entries, fn entry ->
        upsert_video_from_api_entry(db_channel, entry, "uploads")
      end)

      video_cache
    else
      %{}
    end
  end

  # Step 4 & 5: Fetch playlists from API, upsert them, then for each
  # fetch items and create PlaylistVideo join records.
  # Accepts a video_cache from the uploads sync to avoid redundant video detail fetches.
  defp sync_playlists_and_link_videos(db_channel, channel_id, video_cache) do
    case Client.get_channel_playlists(channel_id) do
      {:ok, yt_playlists} ->
        sync_interval = Ytdarr.Settings.get_setting_value(:sync_interval_minutes, 60)

        Enum.reduce(yt_playlists, video_cache, fn yt_playlist, acc_cache ->
          Logger.info("[Content] Processing playlist #{yt_playlist.id} - #{yt_playlist.title}")

          # Upsert the playlist record
          case upsert_playlist(db_channel.id, %{
                 external_id: yt_playlist.id,
                 name: yt_playlist.title,
                 description: yt_playlist.description,
                 url: yt_playlist.url,
                 video_count: yt_playlist.video_count,
                 is_monitored: false
               }) do
            {:ok, db_playlist} ->
              if should_fetch_playlist_items?(db_playlist, yt_playlist, sync_interval) do
                fetch_and_link_playlist_videos(db_channel, db_playlist, acc_cache)
              else
                Logger.debug(
                  "[Content] Skipping playlist item fetch for #{yt_playlist.title} (unchanged)"
                )

                acc_cache
              end

            {:error, error} ->
              Logger.error(
                "[Content] Error upserting playlist #{yt_playlist.id}: #{inspect(error)}"
              )

              acc_cache
          end
        end)

      {:error, reason} ->
        Logger.error(
          "[Content] Error fetching playlists for channel #{channel_id}: #{inspect(reason)}"
        )
    end
  end

  # Determine whether we need to re-fetch a playlist's items.
  # Skip if video_count is unchanged AND the playlist was checked within the sync interval.
  defp should_fetch_playlist_items?(db_playlist, yt_playlist, sync_interval_minutes) do
    video_count_changed = db_playlist.video_count != yt_playlist.video_count

    recently_checked =
      case db_playlist.last_checked_at do
        nil ->
          false

        last_checked ->
          cutoff = DateTime.add(DateTime.utc_now(), -sync_interval_minutes, :minute)
          DateTime.compare(last_checked, cutoff) == :gt
      end

    video_count_changed or not recently_checked
  end

  # Fetch a playlist's items from the API, upsert any new videos, and create PlaylistVideo links.
  # Accepts an optional video_cache to avoid re-fetching video details already known.
  # Returns the updated video_cache.
  defp fetch_and_link_playlist_videos(db_channel, db_playlist, video_cache \\ %{}) do
    {status, %{videos: entries, video_cache: updated_cache}} =
      Client.get_playlist_items_detailed(db_playlist.external_id, video_cache: video_cache)

    if status in [:ok, :partial] do
      Logger.info("[Content] Linking #{length(entries)} videos to playlist #{db_playlist.name}")

      Enum.with_index(entries, fn entry, index ->
        video_details = entry["video_details"] || %{}
        video_id = video_details["id"]

        if is_binary(video_id) do
          # Upsert the video (may already exist from uploads sync)
          case upsert_video_from_api_entry(
                 db_channel,
                 entry,
                 "playlist:#{db_playlist.external_id}"
               ) do
            {:ok, db_video} ->
              upsert_playlist_video(%{
                playlist_id: db_playlist.id,
                video_id: db_video.id,
                position: index
              })

            {:error, error} ->
              Logger.error(
                "[Content] Error upserting video #{video_id} for playlist link: #{inspect(error)}"
              )
          end
        end
      end)

      # Mark playlist as checked
      mark_playlist_checked(db_playlist)

      updated_cache
    else
      video_cache
    end
  end

  # Upsert a video from a raw API entry (the merged playlist_details/video_details map)
  defp upsert_video_from_api_entry(db_channel, entry, discovered_from) do
    video_details = entry["video_details"] || %{}
    snippet = video_details["snippet"] || %{}
    content_details = video_details["contentDetails"] || %{}

    video_id = video_details["id"]

    if is_binary(video_id) do
      thumbnail_url =
        get_in(snippet, ["thumbnails", "high", "url"]) ||
          get_in(snippet, ["thumbnails", "default", "url"])

      upload_date = parse_upload_date(snippet["publishedAt"])
      duration_seconds = parse_iso8601_duration(content_details["duration"])

      upsert_video(db_channel.id, %{
        external_id: video_id,
        title: snippet["title"],
        description: snippet["description"],
        url: "https://www.youtube.com/watch?v=#{video_id}",
        thumbnail_url: thumbnail_url,
        upload_date: upload_date,
        duration: duration_seconds,
        discovered_from: discovered_from
      })
    else
      {:error, :missing_video_id}
    end
  end

  @doc """
  Upserts videos from raw API entries and links them to a playlist.

  Accepts a playlist (with loaded `:channel` association) and a list of raw API
  entries (maps with `"video_details"` from `Client.get_playlist_items_detailed`
  or `Client.check_playlist_for_new_videos`). Each entry is upserted as a video
  and linked to the playlist via a PlaylistVideo record.
  """
  def upsert_and_link_playlist_entries(playlist, entries) do
    channel =
      case Ash.load(playlist, :channel) do
        {:ok, loaded} -> loaded.channel
        _ -> nil
      end

    if is_nil(channel) do
      Logger.error(
        "[Content] Cannot upsert entries for playlist #{playlist.id}: no channel found"
      )

      {:error, :channel_not_found}
    else
      Enum.with_index(entries, fn entry, index ->
        video_details = entry["video_details"] || %{}
        video_id = video_details["id"]

        if is_binary(video_id) do
          case upsert_video_from_api_entry(
                 channel,
                 entry,
                 "playlist:#{playlist.external_id}"
               ) do
            {:ok, db_video} ->
              upsert_playlist_video(%{
                playlist_id: playlist.id,
                video_id: db_video.id,
                position: index
              })

            {:error, error} ->
              Logger.error(
                "[Content] Error upserting video #{video_id} for playlist link: #{inspect(error)}"
              )
          end
        end
      end)

      :ok
    end
  end

  @doc """
  Queue a video for download via Oban.

  Sets the video's `download_state` to `:queued` (not `:downloading`) to indicate
  it is waiting for an Oban worker slot. The `VideoDownloader.perform/1` callback
  transitions the state to `:downloading` when the job actually begins executing.

  The Oban `video_downloader` queue has a configured concurrency limit (e.g. 2),
  meaning only that many jobs execute simultaneously. Additional jobs remain in
  "available" state until a slot opens.
  """
  def queue_video_download(video_id, channel_id) do
    case get_video(video_id) do
      {:ok, video} ->
        update_video(video, %{download_state: :queued})

        %{"video_id" => video_id, "channel_id" => channel_id}
        |> Ytdarr.ObanWorkers.VideoDownloader.new()
        |> Oban.insert()

      {:error, error} ->
        Logger.error("Failed to find video #{video_id} to queue download: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Deletes the physical video file and updates the database record.
  """
  def delete_video_file(video_id) do
    with {:ok, video} <- get_video(video_id) do
      video_delete_result =
        if video.download_path do
          case File.rm(video.download_path) do
            :ok ->
              Logger.info("Deleted video file: #{video.download_path}")
              :ok

            {:error, :enoent} ->
              Logger.info("Video file not found, treating as deleted: #{video.download_path}")
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        else
          :ok
        end

      case video_delete_result do
        :ok ->
          if video.download_path do
            nfo_path = Path.rootname(video.download_path) <> ".nfo"

            case File.rm(nfo_path) do
              :ok -> Logger.info("Deleted NFO file: #{nfo_path}")
              {:error, _} -> :ok
            end
          end

          update_video(video, %{
            download_state: :available,
            is_downloaded: false,
            download_path: nil,
            downloaded_at: nil
          })

        {:error, reason} ->
          Logger.error("Failed to delete video file #{video.download_path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Parsing helpers
  # ---------------------------------------------------------------------------

  defp parse_upload_date(nil), do: nil

  defp parse_upload_date(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> DateTime.to_date(datetime)
      {:error, _} -> nil
    end
  end

  defp parse_upload_date(_), do: nil

  defp parse_iso8601_duration(nil), do: nil

  defp parse_iso8601_duration(duration_string) when is_binary(duration_string) do
    regex = ~r/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/

    case Regex.run(regex, duration_string) do
      [_, hours, minutes, seconds] ->
        parse_int_or_zero(hours) * 3600 + parse_int_or_zero(minutes) * 60 +
          parse_int_or_zero(seconds)

      [_, hours, minutes] ->
        parse_int_or_zero(hours) * 3600 + parse_int_or_zero(minutes) * 60

      [_, hours] ->
        parse_int_or_zero(hours) * 3600

      _ ->
        Logger.warning("Could not parse duration: #{duration_string}")
        nil
    end
  end

  defp parse_iso8601_duration(_), do: nil

  defp parse_int_or_zero(""), do: 0
  defp parse_int_or_zero(nil), do: 0

  defp parse_int_or_zero(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end
end
