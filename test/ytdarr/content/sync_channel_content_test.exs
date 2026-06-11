defmodule Ytdarr.Content.SyncChannelContentTest do
  @moduledoc """
  Happy-path tests for `Content.sync_channel_content/2` and
  `Content.sync_playlist_content/2`. HTTP is mocked via a TestPlug injected as
  the `:client` opt (now threaded through to `Client.*`).

  These exercise the helper chain: `sync_channel_metadata`, `sync_uploads`,
  `sync_playlists_and_link_videos`, and `fetch_and_link_playlist_videos`.
  """
  use Ytdarr.DataCase, async: false
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.Services.YouTube.QuotaTracker
  alias Ytdarr.YouTubeMocks

  defmodule TestPlug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      handler = Keyword.fetch!(opts, :handler)
      {status, body} = handler.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  setup do
    QuotaTracker.reset()
    on_exit(fn -> QuotaTracker.reset() end)
    :ok
  end

  describe "sync_channel_content/2" do
    test "syncs uploads and playlists end-to-end" do
      channel =
        channel_fixture(%{
          external_id: "UCSyncContent",
          uploads_playlist_id: "UUSyncContent"
        })

      video_id = "vidSync001"
      playlist_id = "PLSyncContent"
      playlist_video_id = "vidSync002"

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/channels") ->
              {200,
               YouTubeMocks.channel_response(channel.external_id, title: "UpdatedName")}

            String.ends_with?(conn.request_path, "/playlistItems") and
                conn.query_string =~ "playlistId=#{channel.uploads_playlist_id}" ->
              {200,
               YouTubeMocks.playlist_items_response(channel.uploads_playlist_id, [video_id])}

            String.ends_with?(conn.request_path, "/playlistItems") and
                conn.query_string =~ "playlistId=#{playlist_id}" ->
              {200, YouTubeMocks.playlist_items_response(playlist_id, [playlist_video_id])}

            String.ends_with?(conn.request_path, "/playlists") ->
              {200,
               %{
                 "kind" => "youtube#playlistListResponse",
                 "pageInfo" => %{"totalResults" => 1},
                 "items" => [
                   %{
                     "id" => playlist_id,
                     "snippet" => %{
                       "title" => "Sync Playlist",
                       "channelId" => channel.external_id,
                       "thumbnails" => %{}
                     },
                     "contentDetails" => %{"itemCount" => 1}
                   }
                 ]
               }}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response([video_id, playlist_video_id])}
          end
        end)

      assert {:ok, :synced} =
               Content.sync_channel_content(channel.external_id,
                 client: client,
                 skip_quota_tracking: true
               )

      # Videos were upserted
      videos = Content.list_videos!()
      external_ids = Enum.map(videos, & &1.external_id)
      assert video_id in external_ids
      assert playlist_video_id in external_ids

      # Playlist was upserted
      assert {:ok, playlist} = Content.get_playlist_by_external_id(playlist_id)
      assert playlist.name == "Sync Playlist"
      assert playlist.channel_id == channel.id
    end

    test "returns an error tuple when the channel is not in the database" do
      assert {:error, %Ash.Error.Invalid{}} =
               Content.sync_channel_content("UC_NEVER_EXISTED_#{System.unique_integer([:positive])}")
    end
  end

  describe "sync_playlist_content/2" do
    test "syncs a playlist's videos with HTTP mocked" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      video_id = "vidPlaylistSync"

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              assert conn.query_string =~ "playlistId=#{playlist.external_id}"
              {200, YouTubeMocks.playlist_items_response(playlist.external_id, [video_id])}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response([video_id])}
          end
        end)

      assert {:ok, :synced} =
               Content.sync_playlist_content(playlist.id,
                 client: client,
                 skip_quota_tracking: true
               )

      videos = Content.list_videos!()
      assert Enum.any?(videos, &(&1.external_id == video_id))
    end
  end

  describe "search_for_channels/2" do
    test "enriches search results with the monitored status of existing records" do
      existing = channel_fixture(%{is_monitored: true})

      client =
        test_client(fn _conn ->
          {200,
           %{
             "kind" => "youtube#searchListResponse",
             "pageInfo" => %{"totalResults" => 2},
             "items" => [
               %{
                 "id" => %{"channelId" => existing.external_id},
                 "snippet" => %{
                   "title" => existing.name,
                   "description" => "monitored",
                   "thumbnails" => %{"high" => %{"url" => "https://example.com/a.jpg"}}
                 }
               },
               %{
                 "id" => %{"channelId" => "UC_FRESH_HIT"},
                 "snippet" => %{
                   "title" => "Fresh",
                   "description" => "new",
                   "thumbnails" => %{"high" => %{"url" => "https://example.com/b.jpg"}}
                 }
               }
             ]
           }}
        end)

      assert {:ok, [first, second]} =
               Content.search_for_channels("anything",
                 client: client,
                 skip_quota_tracking: true
               )

      assert (first.external_id == existing.external_id and first.is_monitored) or
               (second.external_id == existing.external_id and second.is_monitored)

      fresh = Enum.find([first, second], &(&1.external_id == "UC_FRESH_HIT"))
      refute fresh.is_monitored
    end

    test "forwards errors from the Client" do
      client = test_client(fn _conn -> {500, YouTubeMocks.error_response(500, "boom")} end)

      assert {:error, {:http_error, 500, _body}} =
               Content.search_for_channels("anything",
                 client: client,
                 skip_quota_tracking: true
               )
    end
  end

  describe "search_for_playlists/2" do
    test "returns [] when there are no monitored channels" do
      # Seed data may include monitored channels; unmonitor them inside the
      # sandboxed transaction so we get a deterministic empty state.
      Content.list_monitored_channels!()
      |> Enum.each(fn channel ->
        {:ok, _} = Content.unmonitor_channel(channel)
      end)

      assert {:ok, []} = Content.search_for_playlists("anything")
    end
  end

  defp test_client(handler) do
    Req.new(
      base_url: "https://www.googleapis.com/youtube/v3",
      params: [key: "test-api-key"],
      plug: {TestPlug, handler: handler},
      retry: false
    )
  end
end
