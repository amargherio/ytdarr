defmodule Ytdarr.Services.YouTube.API do
  @moduledoc """
  Low-level wrapper implementation for the YouTube v3 Data API.

  All functions accept an optional `:client` option for dependency injection
  during testing. If not provided, uses the default ClientSupervisor client.
  """

  alias Ytdarr.Services.YouTube.{ClientSupervisor, Models}
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
    # Determine if it's a channel ID or a username
    params =
      if String.starts_with?(query, "UC") do
        [part: "id,snippet,status,brandingSettings,contentDetails,statistics", id: query]
      else
        [part: "id,snippet,status,brandingSettings,contentDetails,statistics", forUsername: query]
      end

    client = get_client(opts)

    case client |> Req.get(url: "/channels", params: params) do
      {:ok, %{status: 200, body: body}} ->
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

  # Gets the client from opts or falls back to ClientSupervisor
  defp get_client(opts) do
    Keyword.get_lazy(opts, :client, &ClientSupervisor.get_client/0)
  end

  defp maybe_add_page_token(params, nil), do: params
  defp maybe_add_page_token(params, token), do: Keyword.put(params, :pageToken, token)
end
