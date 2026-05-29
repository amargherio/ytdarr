defmodule Ytdarr.Services.YouTube.API do
  @moduledoc """
  Low-level wrapper for the YouTube Data API v3.

  Each public function maps to a single YouTube API endpoint, accepts raw
  parameters, and returns parsed `Models.APIResponse` structs. All calls
  automatically record quota usage via `QuotaTracker` unless the caller
  passes `skip_quota_tracking: true` (useful in tests).

  ## Dependency Injection

  Every function accepts an optional `:client` keyword for injecting a
  custom `Req` client (e.g., a Req test plug). When omitted, the default
  `ClientSupervisor` pool is used.

  ## Endpoints and Quota Costs

  | Function                  | YouTube Endpoint        | Quota Cost |
  |---------------------------|-------------------------|------------|
  | `search_channels/2`       | `search.list`           | 100 units  |
  | `get_channel/2`           | `channels.list`         | 1 unit     |
  | `get_channels_by_ids/2`   | `channels.list` (batch) | 1 unit / 50 IDs |
  | `get_playlists_by_channel/2` | `playlists.list`     | 1 unit     |
  | `get_playlists_by_ids/2`  | `playlists.list` (batch)| 1 unit / 50 IDs |
  | `get_playlist_items/2`    | `playlistItems.list`    | 1 unit     |
  | `get_videos_by_ids/2`     | `videos.list` (batch)   | 1 unit / 50 IDs |

  See `docs/youtube-api-integration.md` for the full quota optimization guide.
  """

  alias Ytdarr.Services.YouTube.{ClientSupervisor, Models, QuotaTracker}
  require Logger

  def search_channels(query, opts \\ []) do
    params = [
      part: "snippet",
      q: query,
      type: "channel"
    ]

    client = get_client(opts)

    case client |> Req.get(url: "/search", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:search, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok,
       %{
         status: status,
         body: body
       }} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channel(query, opts \\ []) do
    base_parts = "id,snippet,status,brandingSettings,contentDetails"

    params =
      cond do
        String.starts_with?(query, "UC") ->
          [part: base_parts, id: query]

        String.starts_with?(query, "@") ->
          [part: base_parts, forHandle: query]

        true ->
          [part: base_parts, forUsername: query]
      end

    client = get_client(opts)

    case client |> Req.get(url: "/channels", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)

        case body["items"] do
          [_ | _] -> {:ok, Models.APIResponse.from_api(body)}
          [] -> {:error, :not_found}
        end

      {:ok,
       %{
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

    client = get_client(opts)

    case client |> Req.get(url: "/playlists", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok,
       %{
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
    page_token = Keyword.get(opts, :page_token)

    params =
      [
        part: "id,snippet,contentDetails",
        playlistId: playlist_id,
        maxResults: max_results
      ]
      |> maybe_add_page_token(page_token)

    client = get_client(opts)

    case client |> Req.get(url: "/playlistItems", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok,
       %{
         status: status,
         body: body
       }} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_videos_by_ids(video_ids, opts \\ [])

  def get_videos_by_ids(video_ids, opts) when is_binary(video_ids) do
    client = get_client(opts)

    case client
         |> Req.get(
           url: "/videos",
           params: [
             part: "snippet,contentDetails,statistics",
             id: video_ids
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok,
       %{
         status: status,
         body: body
       }} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_videos_by_ids(video_ids, opts) when is_list(video_ids) do
    get_videos_by_ids(Enum.join(video_ids, ","), opts)
  end

  @doc """
  Fetches multiple channels by their IDs in a single API call.

  YouTube API supports up to 50 channel IDs per request.
  Cost: 1 quota unit per call.

  ## Parameters
    - channel_ids: List of channel IDs (max 50)
    - opts: Optional keyword list with :client for testing

  ## Returns
    - `{:ok, %APIResponse{}}` with items containing channel data
    - `{:error, reason}` on failure
  """
  def get_channels_by_ids(channel_ids, opts \\ [])

  def get_channels_by_ids(channel_ids, opts)
      when is_list(channel_ids) and length(channel_ids) > 0 do
    # YouTube API accepts comma-separated IDs, max 50 per request
    ids_string = Enum.take(channel_ids, 50) |> Enum.join(",")

    params = [
      part: "id,snippet,status,brandingSettings,contentDetails",
      id: ids_string
    ]

    client = get_client(opts)

    case client |> Req.get(url: "/channels", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_channels_by_ids([], _opts), do: {:ok, %Models.APIResponse{items: []}}

  @doc """
  Fetches multiple playlists by their IDs in a single API call.

  YouTube API supports up to 50 playlist IDs per request.
  Cost: 1 quota unit per call.

  ## Parameters
    - playlist_ids: List of playlist IDs (max 50)
    - opts: Optional keyword list with :client for testing

  ## Returns
    - `{:ok, %APIResponse{}}` with items containing playlist data
    - `{:error, reason}` on failure
  """
  def get_playlists_by_ids(playlist_ids, opts \\ [])

  def get_playlists_by_ids(playlist_ids, opts)
      when is_list(playlist_ids) and length(playlist_ids) > 0 do
    # YouTube API accepts comma-separated IDs, max 50 per request
    ids_string = Enum.take(playlist_ids, 50) |> Enum.join(",")

    params = [
      part: "snippet,contentDetails",
      id: ids_string
    ]

    client = get_client(opts)

    case client |> Req.get(url: "/playlists", params: params) do
      {:ok, %{status: 200, body: body}} ->
        track_quota(:read, opts)
        {:ok, Models.APIResponse.from_api(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlists_by_ids([], _opts), do: {:ok, %Models.APIResponse{items: []}}

  # Gets the client from opts or falls back to ClientSupervisor
  defp get_client(opts) do
    Keyword.get_lazy(opts, :client, &ClientSupervisor.get_client/0)
  end

  defp maybe_add_page_token(params, nil), do: params
  defp maybe_add_page_token(params, token), do: Keyword.put(params, :pageToken, token)

  # Tracks quota usage unless explicitly skipped
  defp track_quota(operation_type, opts) do
    unless Keyword.get(opts, :skip_quota_tracking, false) do
      # Only track if QuotaTracker is running (may not be in tests)
      if Process.whereis(QuotaTracker) do
        QuotaTracker.record_usage(operation_type)
      end
    end
  end
end
