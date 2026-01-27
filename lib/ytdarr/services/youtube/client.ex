defmodule Ytdarr.Services.YouTube.Client do
  @moduledoc """
  High-level YouTube API client for fetching channel, playlist, and video data.
  """

  alias Ytdarr.Services.YouTube.{API, Parser, Models}

  require Logger

  def search_channels(query) do
    case API.search_channels(query) do
      {:ok, api_response} ->
        channels =
          api_response.items
          |> Enum.map(&Models.Channel.from_api/1)
          |> Enum.map(&Parser.create_ytdarr_channel/1)

        if channels == [] do
          {:error, :no_results}
        else
          {:ok, channels}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel(channel_identifier) do
    case API.get_channel(channel_identifier) do
      {:ok, api_response} ->
        case api_response.items do
          [first | _] ->
            channel = Models.Channel.from_api(first)
            {:ok, Parser.create_ytdarr_channel(channel)}

          [] ->
            {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets playlists for a given channel ID. The channel ID must be valid and cannot
  be a username.
  """
  def get_channel_playlists(channel_id, opts \\ []) do
    # use the provided channel_id to fetch playlists
    Logger.info("[YouTube.Client] Fetching playlists for channel ID: #{channel_id}")

    case API.get_playlists_by_channel(channel_id, opts) do
      {:ok, api_response} ->
        playlists = Enum.map(api_response.items, &Models.Playlist.from_api/1)
        {:ok, playlists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deprecated: Use get_playlist_items_detailed/2 instead.
  """
  def get_playlist_videos(playlist_id, opts \\ []) do
    case API.get_playlist_items(playlist_id, opts) do
      {:ok, api_response} ->
        case api_response.items do
          [] ->
            {:error, :not_found}

          items ->
            # Extract video IDs from playlist items
            video_ids =
              items
              |> Enum.map(&get_in(&1, ["snippet", "resourceId", "videoId"]))
              |> Enum.filter(&is_binary/1)

            if video_ids == [] do
              {:error, :not_found}
            else
              # Fetch full video details
              case API.get_videos_by_ids(video_ids) do
                {:ok, videos_response} ->
                  videos = Enum.map(videos_response.items, &Models.Video.from_api/1)
                  {:ok, videos}

                {:error, reason} ->
                  {:error, reason}
              end
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel_videos(channel_id, opts \\ []) do
    # Strategy: fetch channel to confirm existence, then use search/list if needed.
    # Placeholder implementation: delegates to uploads playlist detailed fetch.
    uploads_id = get_uploads_playlist_id(channel_id)

    case get_playlist_items_detailed(uploads_id, opts) do
      {status, %{videos: merged}} when status in [:ok, :partial] ->
        videos = Enum.map(merged, &convert_playlist_item_to_video/1) |> Enum.reject(&is_nil/1)
        {status, videos}
    end
  end

  def get_playlist(playlist_id, opts \\ []) do
    # Minimal stub returning playlist videos plus basic playlist metadata if available
    case get_playlist_items_detailed(playlist_id, opts) do
      {status, %{videos: merged, total_results: total, errors: errors}}
      when status in [:ok, :partial] ->
        videos = Enum.map(merged, &convert_playlist_item_to_video/1) |> Enum.reject(&is_nil/1)
        {status, %{id: playlist_id, video_count: total, videos: videos, errors: errors}}
    end
  end

  @doc """
  Gets the uploads playlist ID for a channel
  """
  def get_uploads_playlist_id(channel_id) do
    # Upload playlist ID structure is "UU" + channel_id[2..]
    "UU" <> String.slice(channel_id, 2..-1//1)
  end

  @doc """
  Monitors uploads playlist for new videos since last check.

  When `since_datetime` is provided, uses optimized fetching that stops
  pagination early once it encounters videos older than the threshold.
  This significantly reduces API calls for channels with many videos.
  """
  def check_uploads_for_new_videos(channel_id, since_datetime \\ nil) do
    uploads_playlist_id = get_uploads_playlist_id(channel_id)

    if since_datetime do
      # Use optimized incremental fetch that stops early
      check_uploads_incremental(uploads_playlist_id, since_datetime)
    else
      # Full fetch when no since_datetime provided
      case get_playlist_items_detailed(uploads_playlist_id) do
        {status, %{videos: playlist_items}} when status in [:ok, :partial] ->
          videos =
            playlist_items
            |> Enum.map(&convert_playlist_item_to_video/1)
            |> Enum.reject(&is_nil/1)

          {status, videos}
      end
    end
  end

  # Optimized incremental check that stops pagination when encountering old items.
  # YouTube returns playlist items in reverse chronological order, so once we
  # see an item older than our threshold, we can stop fetching.
  defp check_uploads_incremental(playlist_id, since_datetime) do
    case fetch_playlist_items_until(playlist_id, since_datetime, nil, []) do
      {:ok, new_items} ->
        # Fetch full video details for the new items only
        video_ids =
          new_items
          |> Enum.map(&get_in(&1, ["snippet", "resourceId", "videoId"]))
          |> Enum.filter(&is_binary/1)

        if video_ids == [] do
          {:ok, []}
        else
          {videos_data, errors} = fetch_videos_in_batches(video_ids)
          merged = merge_playlist_and_video_data(new_items, videos_data)

          videos =
            merged
            |> Enum.map(&convert_playlist_item_to_video/1)
            |> Enum.reject(&is_nil/1)

          if errors == [] do
            {:ok, videos}
          else
            {:partial, videos}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetches playlist items, stopping when we encounter items older than since_datetime.
  # Returns {:ok, items} or {:error, reason}
  defp fetch_playlist_items_until(playlist_id, since_datetime, page_token, acc_items) do
    opts = if page_token, do: [page_token: page_token], else: []

    case API.get_playlist_items(playlist_id, opts) do
      {:ok, response} ->
        items = response.items || []

        # Check each item's publish date and stop if we find old ones
        {new_items, should_continue} = partition_new_items(items, since_datetime)
        accumulated = acc_items ++ new_items

        cond do
          # Found old items, stop fetching
          not should_continue ->
            {:ok, accumulated}

          # More pages and all items were new
          response.next_page_token ->
            fetch_playlist_items_until(
              playlist_id,
              since_datetime,
              response.next_page_token,
              accumulated
            )

          # No more pages
          true ->
            {:ok, accumulated}
        end

      {:error, reason} ->
        if acc_items == [] do
          {:error, reason}
        else
          # Return what we have on error
          Logger.warning("Error during incremental fetch, returning #{length(acc_items)} items")
          {:ok, acc_items}
        end
    end
  end

  # Partitions items into new items (published after since_datetime) and returns
  # whether we should continue fetching more pages.
  # Returns {new_items, should_continue}
  defp partition_new_items(items, since_datetime) do
    {new_items, old_items} =
      Enum.split_while(items, fn item ->
        # Get the video published date from contentDetails
        published_at =
          get_in(item, ["contentDetails", "videoPublishedAt"]) ||
            get_in(item, ["snippet", "publishedAt"])

        case DateTime.from_iso8601(published_at || "") do
          {:ok, item_datetime, _} ->
            DateTime.compare(item_datetime, since_datetime) == :gt

          _ ->
            # If we can't parse the date, assume it's new to be safe
            true
        end
      end)

    # If we found any old items, we should stop
    should_continue = old_items == []
    {new_items, should_continue}
  end

  @doc """
  Fetches all playlist items with full video details, paginating through all results.

  Returns:
  - `{:ok, %{videos: merged_items, total_results: count, errors: []}}` on complete success
  - `{:partial, %{videos: partial_items, total_results: count, errors: [...]}}` on partial failure

  Errors are tuples of `{:playlist_page, page_token, reason}` or `{:video_batch, batch_index, reason}`.
  """
  def get_playlist_items_detailed(playlist_id, opts \\ []) do
    max_results = Keyword.get(opts, :limit)

    # Phase 1: Fetch all playlist items with pagination (accumulates errors)
    {playlist_items, playlist_errors} =
      fetch_all_playlist_items(playlist_id, nil, [], [], max_results)

    # Phase 2: Extract video IDs
    video_ids =
      playlist_items
      |> Enum.map(&get_in(&1, ["snippet", "resourceId", "videoId"]))
      |> Enum.filter(&is_binary/1)

    Logger.info("Collected #{length(video_ids)} video IDs for playlist #{playlist_id}")

    if video_ids != [] do
      # Phase 3: Fetch video details in batches of 50 (accumulates errors)
      {all_videos, video_errors} = fetch_videos_in_batches(video_ids)

      # Phase 4: Merge playlist items with video details
      merged_items = merge_playlist_and_video_data(playlist_items, all_videos)

      all_errors = playlist_errors ++ video_errors

      result = %{
        videos: merged_items,
        total_results: length(merged_items),
        errors: all_errors
      }

      if all_errors == [] do
        {:ok, result}
      else
        Logger.warning(
          "Partial failure fetching playlist #{playlist_id}: #{length(all_errors)} errors"
        )

        {:partial, result}
      end
    else
      result = %{videos: [], total_results: 0, errors: playlist_errors}

      if playlist_errors == [] do
        {:ok, result}
      else
        {:partial, result}
      end
    end
  end

  # Recursively fetches all playlist items, following pagination tokens.
  # Accumulates errors instead of failing fast.
  # Returns {items, errors} tuple.
  defp fetch_all_playlist_items(playlist_id, page_token, acc_items, acc_errors, max_results) do
    opts = if page_token, do: [page_token: page_token], else: []

    case API.get_playlist_items(playlist_id, opts) do
      {:ok, response} ->
        items = response.items || []
        accumulated_items = acc_items ++ items

        # Check if we've hit the optional max limit
        cond do
          max_results && length(accumulated_items) >= max_results ->
            {Enum.take(accumulated_items, max_results), acc_errors}

          response.next_page_token ->
            # More pages available, continue fetching
            fetch_all_playlist_items(
              playlist_id,
              response.next_page_token,
              accumulated_items,
              acc_errors,
              max_results
            )

          true ->
            # No more pages
            {accumulated_items, acc_errors}
        end

      {:error, reason} ->
        error = {:playlist_page, page_token || :first_page, reason}
        # Log the error but continue with what we have
        Logger.error("Failed to fetch playlist page: #{inspect(error)}")
        {acc_items, acc_errors ++ [error]}
    end
  end

  # Fetches video details in batches of 50 (YouTube API limit).
  # Accumulates errors instead of failing fast.
  # Returns {videos, errors} tuple.
  defp fetch_videos_in_batches(video_ids, batch_size \\ 50) do
    video_ids
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {batch, batch_index}, {acc_videos, acc_errors} ->
      case API.get_videos_by_ids(batch) do
        {:ok, response} ->
          videos = response.items || []
          {acc_videos ++ videos, acc_errors}

        {:error, reason} ->
          error = {:video_batch, batch_index, reason}
          Logger.error("Failed to fetch video batch #{batch_index}: #{inspect(reason)}")
          {acc_videos, acc_errors ++ [error]}
      end
    end)
  end

  # Builds a Models.Video struct from a merged playlist/video map.
  # Returns nil if required video id is missing.
  defp convert_playlist_item_to_video(merged_item) do
    video_details = merged_item["video_details"] || %{}
    snippet = get_in(video_details, ["snippet"]) || %{}
    statistics = get_in(video_details, ["statistics"]) || %{}

    video_id = video_details["id"]

    if is_nil(video_id) do
      nil
    else
      %Models.Video{
        id: video_id,
        title: snippet["title"],
        description: snippet["description"],
        url: "https://www.youtube.com/watch?v=#{video_id}",
        thumbnail_url:
          get_in(snippet, ["thumbnails", "high", "url"]) ||
            get_in(snippet, ["thumbnails", "default", "url"]),
        published_at: Parser.parse_date(snippet["publishedAt"]),
        # not parsed here (ISO8601 duration not requested in this flow)
        duration: nil,
        view_count: Parser.parse_int(statistics["viewCount"]),
        channel_id: snippet["channelId"]
      }
    end
  end

  defp merge_playlist_and_video_data(playlist_items, videos) do
    video_map = Map.new(videos, &{&1["id"], &1})

    Enum.map(playlist_items, fn item ->
      video_id = get_in(item, ["snippet", "resourceId", "videoId"])
      video_details = Map.get(video_map, video_id, %{})

      %{
        "playlist_details" => item,
        "video_details" => video_details
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Batch Operations for Quota Optimization
  # ---------------------------------------------------------------------------

  @doc """
  Fetches multiple channels by their IDs in batches of 50.

  This is more quota-efficient than calling get_channel/1 multiple times,
  as it costs 1 unit per batch of up to 50 channels instead of 1 unit per channel.

  ## Parameters
    - channel_ids: List of channel external IDs

  ## Returns
    - `{:ok, [%Channel{}, ...]}` on success
    - `{:partial, [%Channel{}, ...], errors}` on partial failure
    - `{:error, reason}` on complete failure
  """
  def get_channels_batch(channel_ids) when is_list(channel_ids) do
    if channel_ids == [] do
      {:ok, []}
    else
      {channels, errors} =
        channel_ids
        |> Enum.chunk_every(50)
        |> Enum.with_index()
        |> Enum.reduce({[], []}, fn {batch, batch_index}, {acc_channels, acc_errors} ->
          case API.get_channels_by_ids(batch) do
            {:ok, response} ->
              parsed = Enum.map(response.items, &Models.Channel.from_api/1)
              {acc_channels ++ parsed, acc_errors}

            {:error, reason} ->
              error = {:channel_batch, batch_index, reason}
              Logger.error("Failed to fetch channel batch #{batch_index}: #{inspect(reason)}")
              {acc_channels, acc_errors ++ [error]}
          end
        end)

      cond do
        errors == [] -> {:ok, channels}
        channels == [] -> {:error, {:all_batches_failed, errors}}
        true -> {:partial, channels, errors}
      end
    end
  end

  @doc """
  Fetches multiple playlists by their IDs in batches of 50.

  This is more quota-efficient than calling individual playlist fetches,
  as it costs 1 unit per batch of up to 50 playlists.

  ## Parameters
    - playlist_ids: List of playlist external IDs

  ## Returns
    - `{:ok, [%Playlist{}, ...]}` on success
    - `{:partial, [%Playlist{}, ...], errors}` on partial failure
    - `{:error, reason}` on complete failure
  """
  def get_playlists_batch(playlist_ids) when is_list(playlist_ids) do
    if playlist_ids == [] do
      {:ok, []}
    else
      {playlists, errors} =
        playlist_ids
        |> Enum.chunk_every(50)
        |> Enum.with_index()
        |> Enum.reduce({[], []}, fn {batch, batch_index}, {acc_playlists, acc_errors} ->
          case API.get_playlists_by_ids(batch) do
            {:ok, response} ->
              parsed = Enum.map(response.items, &Models.Playlist.from_api/1)
              {acc_playlists ++ parsed, acc_errors}

            {:error, reason} ->
              error = {:playlist_batch, batch_index, reason}
              Logger.error("Failed to fetch playlist batch #{batch_index}: #{inspect(reason)}")
              {acc_playlists, acc_errors ++ [error]}
          end
        end)

      cond do
        errors == [] -> {:ok, playlists}
        playlists == [] -> {:error, {:all_batches_failed, errors}}
        true -> {:partial, playlists, errors}
      end
    end
  end

  @doc """
  Checks multiple channels for new uploads since the given datetime.

  Efficiently checks multiple channels by fetching the first page of their
  uploads playlists. This is useful for batch sync operations.

  ## Parameters
    - channel_ids: List of channel external IDs
    - since_datetime: Only return videos published after this datetime (optional)

  ## Returns
    - `{:ok, %{channel_id => [%Video{}, ...]}}` map of channel_id to new videos
    - `{:partial, results, errors}` on partial failure
  """
  def check_multiple_channels_for_updates(channel_ids, since_datetime \\ nil) do
    if channel_ids == [] do
      {:ok, %{}}
    else
      results =
        channel_ids
        |> Task.async_stream(
          fn channel_id ->
            case check_uploads_for_new_videos(channel_id, since_datetime) do
              {:ok, videos} -> {:ok, channel_id, videos}
              {:partial, videos} -> {:partial, channel_id, videos}
              {:error, reason} -> {:error, channel_id, reason}
            end
          end,
          max_concurrency: 5,
          timeout: :timer.seconds(30)
        )
        |> Enum.reduce({%{}, []}, fn result, {acc_map, acc_errors} ->
          case result do
            {:ok, {:ok, channel_id, videos}} ->
              {Map.put(acc_map, channel_id, videos), acc_errors}

            {:ok, {:partial, channel_id, videos}} ->
              {Map.put(acc_map, channel_id, videos), acc_errors}

            {:ok, {:error, channel_id, reason}} ->
              {acc_map, acc_errors ++ [{:channel_check, channel_id, reason}]}

            {:exit, reason} ->
              {acc_map, acc_errors ++ [{:task_exit, reason}]}
          end
        end)

      case results do
        {results_map, []} -> {:ok, results_map}
        {results_map, errors} -> {:partial, results_map, errors}
      end
    end
  end
end
