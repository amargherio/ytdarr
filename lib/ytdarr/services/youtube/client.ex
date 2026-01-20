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

  def get_channel_playlists(channel_id, opts \\ []) do
    case API.get_channel(channel_id) do
      {:ok, api_response} ->
        case api_response.items do
          [first | _] ->
            channel = Models.Channel.from_api(first)

            case API.get_playlists_by_channel(channel.id, opts) do
              {:ok, playlists_response} ->
                playlists = Enum.map(playlists_response.items, &Models.Playlist.from_api/1)
                {:ok, playlists}

              {:error, reason} ->
                {:error, reason}
            end

          [] ->
            {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlist_videos(playlist_id, opts \\ []) do
    case API.get_playlist_items(playlist_id, opts) do
      {:ok, api_response} ->
        case api_response.items do
          [] ->
            {:error, :not_found}

          items ->
            videos = Enum.map(items, &Models.Video.from_api/1)
            {:ok, videos}
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
      {:ok, %{videos: merged}} ->
        videos = Enum.map(merged, &convert_playlist_item_to_video/1) |> Enum.reject(&is_nil/1)
        {:ok, videos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlist(playlist_id, opts \\ []) do
    # Minimal stub returning playlist videos plus basic playlist metadata if available
    with {:ok, %{videos: merged, total_results: total}} <-
           get_playlist_items_detailed(playlist_id, opts) do
      videos = Enum.map(merged, &convert_playlist_item_to_video/1) |> Enum.reject(&is_nil/1)
      {:ok, %{id: playlist_id, video_count: total, videos: videos}}
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

    with {:ok, %{videos: playlist_items}} <- get_playlist_items_detailed(uploads_playlist_id) do
      new_items = filter_new_items(playlist_items, since_datetime)

      videos =
        new_items
        |> Enum.map(&convert_playlist_item_to_video/1)
        |> Enum.reject(&is_nil/1)

      {:ok, videos}
    end
  end

  def get_playlist_items_detailed(playlist_id, opts \\ []) do
    _max_results = Keyword.get(opts, :limit, 50)

    # Get the playlist items first
    with {:ok, playlist_response} <- API.get_playlist_items(playlist_id, opts) do
      items = playlist_response["items"] || []

      # Extract video IDs
      video_ids =
        items
        |> Enum.map(&get_in(&1, ["snippet", "resourceId", "videoId"]))
        |> Enum.filter(&is_binary/1)
        |> Enum.join(",")

      if video_ids != "" do
        case API.get_videos_by_ids(video_ids) do
          {:ok, videos_response} ->
            videos = videos_response["items"] || []

            # merge playlist info with video details
            merged_items = merge_playlist_and_video_data(items, videos)

            {:ok,
             %{
               videos: merged_items,
               next_page_token: playlist_response["nextPageToken"],
               total_results: playlist_response["pageInfo"]["totalResults"]
             }}

          {:error, error} ->
            error
        end
      else
        {:ok, %{videos: [], next_page_token: nil, total_results: 0}}
      end
    end
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
