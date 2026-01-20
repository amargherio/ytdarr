defmodule Ytdarr.Services.YouTube.Client do
  @moduledoc """
  High-level YouTube API client for fetching channel, playlist, and video data.
  """

  alias Ytdarr.Services.YouTube.{API, Parser, Models}
  alias Ytdarr.Content

  require Logger

  def search_channels(query) do
    case API.search_channels(query) do
      {:ok, api_response} ->
        data = Enum.map(api_response.items, &Models.Channel.from_api/1)

        if data == [] do
          {:error, :no_results}
        else
          channels =
            Enum.reduce(data, [], fn item, acc ->
              case Content.get_channel_by_external_id(item.id) do
                {:ok, nil} ->
                  # not already monitored, so create a Ytdarr.Content.Channel struct
                  channel = Parser.create_ytdarr_channel(item)
                  [channel | acc]

                {:ok, _existing} ->
                  # already monitored, skip
                  Logger.info("Channel #{item.id} is already monitored, skipping")
                  acc

                {:error, _} ->
                  # error occurred, treat as new
                  channel = Parser.create_ytdarr_channel(item)
                  [channel | acc]
              end
            end)

          {:ok, Enum.reverse(channels)}
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

  @deprecated
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlist(playlist_id, opts \\ []) do
    # Minimal stub returning playlist videos plus basic playlist metadata if available
    case get_playlist_items_detailed(playlist_id, opts) do
      {status, %{videos: merged, total_results: total, errors: errors}}
      when status in [:ok, :partial] ->
        videos = Enum.map(merged, &convert_playlist_item_to_video/1) |> Enum.reject(&is_nil/1)
        {status, %{id: playlist_id, video_count: total, videos: videos, errors: errors}}

      {:error, reason} ->
        {:error, reason}
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
  """
  def check_uploads_for_new_videos(channel_id, since_datetime \\ nil) do
    uploads_playlist_id = get_uploads_playlist_id(channel_id)

    case get_playlist_items_detailed(uploads_playlist_id) do
      {status, %{videos: playlist_items}} when status in [:ok, :partial] ->
        new_items = filter_new_items(playlist_items, since_datetime)

        videos =
          new_items
          |> Enum.map(&convert_playlist_item_to_video/1)
          |> Enum.reject(&is_nil/1)

        {status, videos}

      {:error, reason} ->
        {:error, reason}
    end
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

    Logger.info(
      "Collected #{length(video_ids)} video IDs for playlist #{playlist_id}"
    )

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

  defp filter_new_items(items, nil), do: items

  defp filter_new_items(items, since_datetime) do
    Enum.filter(items, fn item ->
      published_at = get_in(item, ["video_details", "snippet", "publishedAt"])

      case DateTime.from_iso8601(published_at || "") do
        {:ok, item_datetime, _} -> DateTime.compare(item_datetime, since_datetime) == :gt
        _ -> false
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
end
