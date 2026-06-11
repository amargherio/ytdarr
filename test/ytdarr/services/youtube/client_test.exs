defmodule Ytdarr.Services.YouTube.ClientTest do
  @moduledoc """
  Tests for the high-level YouTube Client (batching, pagination, caching,
  quota guards). HTTP is mocked via the TestPlug pattern and injected via
  the `:client` option.
  """
  use Ytdarr.DataCase, async: false

  alias Ytdarr.Services.YouTube.{Client, QuotaTracker}
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

  describe "get_uploads_playlist_id/1" do
    test "rewrites UC prefix to UU" do
      assert Client.get_uploads_playlist_id("UC7X2IY5-ZHKU83nyb6KejgQ") ==
               "UU7X2IY5-ZHKU83nyb6KejgQ"

      assert Client.get_uploads_playlist_id("UCabcdefghijklmnop") == "UUabcdefghijklmnop"
      assert Client.get_uploads_playlist_id("UC12") == "UU12"
    end
  end

  describe "search_channels/2" do
    test "returns parsed Ytdarr.Content.Channel structs on success" do
      channel_id = "UCSearchClient123"

      client =
        test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/search")
          assert conn.query_string =~ "q=test+search"

          {200,
           %{
             "kind" => "youtube#searchListResponse",
             "pageInfo" => %{"totalResults" => 1},
             "items" => [
               %{
                 "id" => %{"channelId" => channel_id},
                 "snippet" => %{
                   "title" => "Searched Channel",
                   "description" => "from search",
                   "thumbnails" => %{
                     "high" => %{"url" => "https://example.com/searched.jpg"}
                   }
                 }
               }
             ]
           }}
        end)

      assert {:ok, [channel]} =
               Client.search_channels("test search", client: client, skip_quota_tracking: true)

      assert channel.external_id == channel_id
      assert channel.name == "Searched Channel"
      assert channel.platform == "YouTube"
    end

    test "returns :no_results when API returns an empty list" do
      client =
        test_client(fn _conn ->
          {200,
           %{
             "kind" => "youtube#searchListResponse",
             "pageInfo" => %{"totalResults" => 0},
             "items" => []
           }}
        end)

      assert {:error, :no_results} =
               Client.search_channels("nothing", client: client, skip_quota_tracking: true)
    end

    test "returns :quota_insufficient when QuotaTracker rejects the call" do
      QuotaTracker.record_usage(:read, 9_999)

      assert {:error, :quota_insufficient} = Client.search_channels("anything")
    end

    test "forwards API errors" do
      client =
        test_client(fn _conn ->
          {500, YouTubeMocks.error_response(500, "boom")}
        end)

      assert {:error, {:http_error, 500, _body}} =
               Client.search_channels("anything", client: client, skip_quota_tracking: true)
    end
  end

  describe "get_channel/2" do
    test "returns a parsed Ytdarr.Content.Channel struct on success" do
      channel_id = "UCGetChannelClient"

      client =
        test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/channels")
          {200, YouTubeMocks.channel_response(channel_id, title: "Got It")}
        end)

      assert {:ok, channel} =
               Client.get_channel(channel_id, client: client, skip_quota_tracking: true)

      assert channel.external_id == channel_id
      assert channel.name == "Got It"
    end

    test "returns :not_found when the API returns an empty items list" do
      client =
        test_client(fn _conn ->
          {200, %{"kind" => "youtube#channelListResponse", "items" => []}}
        end)

      assert {:error, :not_found} =
               Client.get_channel("UCMissing", client: client, skip_quota_tracking: true)
    end

    test "forwards HTTP errors" do
      client =
        test_client(fn _conn ->
          {500, YouTubeMocks.error_response(500, "boom")}
        end)

      assert {:error, {:http_error, 500, _body}} =
               Client.get_channel("UCBoom", client: client, skip_quota_tracking: true)
    end
  end

  describe "get_channel_playlists/2" do
    test "returns parsed Models.Playlist structs" do
      channel_id = "UCPlaylistFetch"

      client =
        test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/playlists")
          assert conn.query_string =~ "channelId=#{channel_id}"

          {200,
           %{
             "kind" => "youtube#playlistListResponse",
             "pageInfo" => %{"totalResults" => 1},
             "items" => [
               %{
                 "id" => "PL1",
                 "snippet" => %{
                   "title" => "P1",
                   "channelId" => channel_id,
                   "thumbnails" => %{}
                 },
                 "contentDetails" => %{"itemCount" => 3}
               }
             ]
           }}
        end)

      assert {:ok, [pl]} =
               Client.get_channel_playlists(channel_id, client: client, skip_quota_tracking: true)

      assert pl.id == "PL1"
      assert pl.video_count == 3
    end

    test "forwards errors from the API" do
      client = test_client(fn _conn -> {403, YouTubeMocks.error_response(403, "forbidden")} end)

      assert {:error, {:http_error, 403, _body}} =
               Client.get_channel_playlists("UCAny", client: client, skip_quota_tracking: true)
    end
  end

  describe "get_channels_batch/2" do
    test "returns parsed Models.Channel structs for a list" do
      ids = ["UCBatch1", "UCBatch2"]

      client =
        test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/channels")

          {200,
           %{
             "kind" => "youtube#channelListResponse",
             "pageInfo" => %{"totalResults" => 2},
             "items" =>
               Enum.map(ids, fn id ->
                 YouTubeMocks.channel_response(id, title: "T-#{id}")["items"] |> hd()
               end)
           }}
        end)

      assert {:ok, channels} =
               Client.get_channels_batch(ids, client: client, skip_quota_tracking: true)

      assert length(channels) == 2
    end

    test "returns {:ok, []} for an empty input list" do
      assert {:ok, []} = Client.get_channels_batch([])
    end

    test "returns :all_batches_failed when every batch errors" do
      client = test_client(fn _conn -> {500, YouTubeMocks.error_response(500, "boom")} end)

      assert {:error, {:all_batches_failed, errors}} =
               Client.get_channels_batch(["UCFail1"], client: client, skip_quota_tracking: true)

      assert [{:channel_batch, 0, _}] = errors
    end
  end

  describe "get_playlists_batch/2" do
    test "returns parsed Models.Playlist structs" do
      ids = ["PLBatch1"]

      client =
        test_client(fn _conn ->
          {200,
           %{
             "kind" => "youtube#playlistListResponse",
             "pageInfo" => %{"totalResults" => 1},
             "items" => [
               %{
                 "id" => "PLBatch1",
                 "snippet" => %{"title" => "Batch", "channelId" => "UCo", "thumbnails" => %{}},
                 "contentDetails" => %{"itemCount" => 2}
               }
             ]
           }}
        end)

      assert {:ok, [pl]} =
               Client.get_playlists_batch(ids, client: client, skip_quota_tracking: true)

      assert pl.id == "PLBatch1"
    end

    test "returns {:ok, []} for an empty input list" do
      assert {:ok, []} = Client.get_playlists_batch([])
    end

    test "returns :all_batches_failed when every batch errors" do
      client = test_client(fn _conn -> {500, YouTubeMocks.error_response(500, "boom")} end)

      assert {:error, {:all_batches_failed, errors}} =
               Client.get_playlists_batch(["PLFail"], client: client, skip_quota_tracking: true)

      assert [{:playlist_batch, 0, _}] = errors
    end
  end

  describe "get_playlist_items_detailed/2" do
    test "paginates and merges video details" do
      playlist_id = "UUPagination"
      first_page_ids = YouTubeMocks.generate_video_ids(2)
      second_page_ids = YouTubeMocks.generate_video_ids(2) |> Enum.map(&("X" <> &1))
      all_ids = first_page_ids ++ second_page_ids
      next_token = "TOKEN_NEXT"

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") and
                conn.query_string =~ "pageToken=#{next_token}" ->
              {200, YouTubeMocks.playlist_items_response(playlist_id, second_page_ids)}

            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200,
               YouTubeMocks.playlist_items_response(playlist_id, first_page_ids,
                 next_page_token: next_token
               )}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response(all_ids)}
          end
        end)

      assert {:ok, %{videos: merged, total_results: total, video_cache: cache, errors: []}} =
               Client.get_playlist_items_detailed(
                 playlist_id,
                 client: client,
                 skip_quota_tracking: true
               )

      assert total == 4
      assert length(merged) == 4
      assert Enum.all?(merged, fn item -> item["video_details"]["id"] != nil end)
      assert map_size(cache) == 4
    end

    test "passes through cached videos and only fetches uncached IDs" do
      playlist_id = "UUCached"
      [cached_id, uncached_id] = YouTubeMocks.generate_video_ids(2)

      cached_video = YouTubeMocks.video(cached_id, "UCo", 0)
      video_cache = %{cached_id => cached_video}

      fetch_count = :counters.new(1, [])

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200, YouTubeMocks.playlist_items_response(playlist_id, [cached_id, uncached_id])}

            String.ends_with?(conn.request_path, "/videos") ->
              :counters.add(fetch_count, 1, 1)
              assert conn.query_string =~ uncached_id
              {200, YouTubeMocks.videos_response([uncached_id])}
          end
        end)

      assert {:ok, %{video_cache: updated_cache, videos: merged}} =
               Client.get_playlist_items_detailed(
                 playlist_id,
                 client: client,
                 video_cache: video_cache,
                 skip_quota_tracking: true
               )

      assert :counters.get(fetch_count, 1) == 1
      assert Map.has_key?(updated_cache, cached_id)
      assert Map.has_key?(updated_cache, uncached_id)
      assert length(merged) == 2
    end

    test "returns :partial when fetching pages errors out" do
      playlist_id = "UUFailFetch"

      client = test_client(fn _conn -> {500, YouTubeMocks.error_response(500, "boom")} end)

      assert {:partial, %{videos: [], errors: errors, video_cache: cache}} =
               Client.get_playlist_items_detailed(
                 playlist_id,
                 client: client,
                 skip_quota_tracking: true
               )

      assert cache == %{}
      assert [{:playlist_page, :first_page, _}] = errors
    end

    test "limits results when :limit option is set" do
      playlist_id = "UULimited"
      ids = YouTubeMocks.generate_video_ids(5)

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200, YouTubeMocks.playlist_items_response(playlist_id, ids)}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response(Enum.take(ids, 2))}
          end
        end)

      assert {:ok, %{total_results: total}} =
               Client.get_playlist_items_detailed(
                 playlist_id,
                 client: client,
                 limit: 2,
                 skip_quota_tracking: true
               )

      assert total == 2
    end
  end

  describe "check_uploads_for_new_videos/3" do
    test "without since_datetime: returns all videos via the uploads playlist" do
      channel_id = "UCUploadFull"
      uploads_id = Client.get_uploads_playlist_id(channel_id)
      ids = YouTubeMocks.generate_video_ids(2)

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              assert conn.query_string =~ "playlistId=#{uploads_id}"
              {200, YouTubeMocks.playlist_items_response(uploads_id, ids)}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response(ids)}
          end
        end)

      assert {:ok, videos} =
               Client.check_uploads_for_new_videos(channel_id, nil,
                 client: client,
                 skip_quota_tracking: true
               )

      assert length(videos) == 2
    end

    test "with since_datetime: stops paginating once an older item is seen" do
      channel_id = "UCUploadIncr"
      uploads_id = Client.get_uploads_playlist_id(channel_id)
      since = ~U[2025-01-10T00:00:00Z]
      new_id = "VidNew"
      old_id = "VidOld"

      response = %{
        "kind" => "youtube#playlistItemListResponse",
        "pageInfo" => %{"totalResults" => 2, "resultsPerPage" => 50},
        "items" => [
          playlist_item_at(uploads_id, new_id, "2025-02-01T00:00:00Z"),
          playlist_item_at(uploads_id, old_id, "2025-01-01T00:00:00Z")
        ]
      }

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200, response}

            String.ends_with?(conn.request_path, "/videos") ->
              assert conn.query_string =~ new_id
              {200, YouTubeMocks.videos_response([new_id])}
          end
        end)

      assert {:ok, [video]} =
               Client.check_uploads_for_new_videos(channel_id, since,
                 client: client,
                 skip_quota_tracking: true
               )

      assert video.id == new_id
    end
  end

  describe "check_playlist_for_new_videos/3" do
    test "returns {:ok, []} when no new items are found" do
      playlist_id = "PLIncrEmpty"
      since = ~U[2030-01-01T00:00:00Z]

      response = %{
        "kind" => "youtube#playlistItemListResponse",
        "pageInfo" => %{"totalResults" => 1},
        "items" => [
          playlist_item_at(playlist_id, "OldVid", "2025-01-01T00:00:00Z")
        ]
      }

      client = test_client(fn _conn -> {200, response} end)

      assert {:ok, []} =
               Client.check_playlist_for_new_videos(playlist_id, since,
                 client: client,
                 skip_quota_tracking: true
               )
    end

    test "returns merged entries for new items" do
      playlist_id = "PLIncrNew"
      since = ~U[2025-01-01T00:00:00Z]
      new_id = "NewVidA"

      response = %{
        "kind" => "youtube#playlistItemListResponse",
        "pageInfo" => %{"totalResults" => 1},
        "items" => [playlist_item_at(playlist_id, new_id, "2025-02-15T00:00:00Z")]
      }

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200, response}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response([new_id])}
          end
        end)

      assert {:ok, [merged]} =
               Client.check_playlist_for_new_videos(playlist_id, since,
                 client: client,
                 skip_quota_tracking: true
               )

      assert merged["video_details"]["id"] == new_id
    end
  end

  describe "check_multiple_channels_for_updates/3" do
    test "returns {:ok, %{}} for an empty input list" do
      assert {:ok, %{}} = Client.check_multiple_channels_for_updates([])
    end
  end

  describe "get_channel_videos/2" do
    test "fetches uploads-playlist videos for a channel" do
      channel_id = "UCGetChannelVideos"
      uploads_id = Client.get_uploads_playlist_id(channel_id)
      ids = YouTubeMocks.generate_video_ids(2)

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              assert conn.query_string =~ "playlistId=#{uploads_id}"
              {200, YouTubeMocks.playlist_items_response(uploads_id, ids)}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response(ids)}
          end
        end)

      assert {:ok, videos} =
               Client.get_channel_videos(channel_id, client: client, skip_quota_tracking: true)

      assert length(videos) == 2
    end
  end

  describe "get_playlist/2" do
    test "returns playlist metadata and its videos" do
      playlist_id = "PLGetPlaylist"
      ids = YouTubeMocks.generate_video_ids(2)

      client =
        test_client(fn conn ->
          cond do
            String.ends_with?(conn.request_path, "/playlistItems") ->
              {200, YouTubeMocks.playlist_items_response(playlist_id, ids)}

            String.ends_with?(conn.request_path, "/videos") ->
              {200, YouTubeMocks.videos_response(ids)}
          end
        end)

      assert {:ok, %{id: ^playlist_id, video_count: 2, videos: videos, errors: []}} =
               Client.get_playlist(playlist_id, client: client, skip_quota_tracking: true)

      assert length(videos) == 2
    end
  end

  # --- helpers ---

  defp test_client(handler) do
    Req.new(
      base_url: "https://www.googleapis.com/youtube/v3",
      params: [key: "test-api-key"],
      plug: {TestPlug, handler: handler},
      retry: false
    )
  end

  defp playlist_item_at(playlist_id, video_id, published_at) do
    %{
      "kind" => "youtube#playlistItem",
      "id" => "item-" <> video_id,
      "snippet" => %{
        "playlistId" => playlist_id,
        "publishedAt" => published_at,
        "title" => "Item #{video_id}",
        "channelId" => "UCo",
        "thumbnails" => %{},
        "resourceId" => %{"kind" => "youtube#video", "videoId" => video_id}
      },
      "contentDetails" => %{
        "videoId" => video_id,
        "videoPublishedAt" => published_at
      }
    }
  end
end
