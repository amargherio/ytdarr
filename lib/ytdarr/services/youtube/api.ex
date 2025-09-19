defmodule Ytdarr.Services.YouTube.API do
  @moduledoc """
  Low-level wrapper implementation for the YouTube v3 Data API
  """

  alias VideoDownloader.Services.YouTube.ClientSupervisor

  def search_channels(query) do
    # TODO: Differentiate between channel IDs and search terms here
    params = [
        part: "snippet",
        q: query,
        type: "channel"
      ]

    client = get_yt_client()


    case client |> Req.get(url: "/search", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Models.APIResponse.from_api(body)}
      {:ok, %{
        status: status,
        body: body
      }} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel(query) do
    # Determine if it's a channel ID or a username
    params = if String.starts_with?(query, "UC") do
      [part: "id,snippet,status,brandingSettings", id: query]
    else
      [part: "id,snippet,status,brandingSettings", forUsername: query]
    end

    client = get_yt_client()
    case client |> Req.get(url: "/channels", params: params) do
      {:ok, %{status: 200, body: body}} ->
        case body["items"] do
          [first | _] -> {:ok, Models.Channel.from_api(first)}
          [] -> {:error, :not_found}
        end
      {:ok, %{
        status: status,
        body: body
      }} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlists_by_channel(channel_id, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 50)
    params = [
      part: "snippet,contentDetails",
      channelId: channel_id,
      maxResults: max_results
    ]

    client = get_yt_client()
    case client |> Req.get(url: "/playlists", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Models.APIResponse.from_api(body)}
      {:ok, %{
        status: status,
        body: body
      }} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlist_items(playlist_id, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 50)
    params = [
      part: "id,snippet,contentDetails",
      playlistId: playlist_id,
      maxResults: max_results
    ]

    client = get_yt_client()
    case client |> Req.get(url: "/playlistItems", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Models.APIResponse.from_api(body)}
      {:ok, %{
        status: status,
        body: body
      }} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_videos_by_ids(video_ids) when is_binary(video_ids) do
    client = get_yt_client()

    case client |> Req.get(url: "/videos", params: %{
      part: "snippet,contentDetails,statistics",
      id: video_ids
    }) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Models.APIResponse.from_api(body)}
      {:ok, %{
        status: status,
        body: body
      }} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_videos_by_ids(video_ids) when is_list(video_ids) do
    get_videos_by_ids(Enum.join(video_ids, ","))
  end

  defp get_yt_client do
    ClientSupervisor.get_client()
  end

end
