defmodule Ytdarr.Services.YouTube.APITest do
  @moduledoc """
  Tests for the YouTube API module with mocked HTTP responses.

  Uses Req's plug option to stub HTTP requests and verify API behavior.
  """
  use ExUnit.Case, async: true

  alias Ytdarr.Services.YouTube.API
  alias Ytdarr.YouTubeMocks

  # Test plug that handles mocked YouTube API requests
  defmodule TestPlug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      response_fn = Keyword.fetch!(opts, :response_fn)
      {status, body} = response_fn.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  describe "get_playlist_items/2" do
    test "returns playlist items on success" do
      playlist_id = "UUTestPlaylist123"
      video_ids = YouTubeMocks.generate_video_ids(3)

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/playlistItems")
          assert conn.query_string =~ "playlistId=#{playlist_id}"
          {200, YouTubeMocks.playlist_items_response(playlist_id, video_ids)}
        end)

      assert {:ok, response} = API.get_playlist_items(playlist_id, client: client)
      assert response.kind == "youtube#playlistItemListResponse"
      assert length(response.items) == 3
    end

    test "includes page token when provided" do
      playlist_id = "UUTestPlaylist123"
      page_token = "NEXT_PAGE_TOKEN_ABC"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "pageToken=#{page_token}"
          {200, YouTubeMocks.playlist_items_response(playlist_id, [])}
        end)

      assert {:ok, _response} =
               API.get_playlist_items(playlist_id, page_token: page_token, client: client)
    end

    test "returns next_page_token when more results available" do
      playlist_id = "UUTestPlaylist123"
      video_ids = YouTubeMocks.generate_video_ids(5)
      next_token = "CONTINUATION_TOKEN_XYZ"

      client =
        create_test_client(fn _conn ->
          {200,
           YouTubeMocks.playlist_items_response(playlist_id, video_ids,
             next_page_token: next_token
           )}
        end)

      assert {:ok, response} = API.get_playlist_items(playlist_id, client: client)
      assert response.next_page_token == next_token
    end

    test "returns error on HTTP failure" do
      playlist_id = "UUTestPlaylist123"

      client =
        create_test_client(fn _conn ->
          {403, YouTubeMocks.error_response(403, "quotaExceeded")}
        end)

      assert {:error, {:http_error, 403, _body}} =
               API.get_playlist_items(playlist_id, client: client)
    end
  end

  describe "get_videos_by_ids/2" do
    test "returns videos for comma-separated IDs" do
      video_ids = YouTubeMocks.generate_video_ids(5)
      video_ids_string = Enum.join(video_ids, ",")

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/videos")
          assert conn.query_string =~ "part=snippet"
          assert conn.query_string =~ "id="
          {200, YouTubeMocks.videos_response(video_ids)}
        end)

      assert {:ok, response} = API.get_videos_by_ids(video_ids_string, client: client)
      assert response.kind == "youtube#videoListResponse"
      assert length(response.items) == 5
    end

    test "returns videos for list of IDs" do
      video_ids = YouTubeMocks.generate_video_ids(3)

      client =
        create_test_client(fn _conn ->
          {200, YouTubeMocks.videos_response(video_ids)}
        end)

      assert {:ok, response} = API.get_videos_by_ids(video_ids, client: client)
      assert length(response.items) == 3
    end

    test "handles empty video list" do
      client =
        create_test_client(fn _conn ->
          {200, %{"kind" => "youtube#videoListResponse", "items" => [], "pageInfo" => %{}}}
        end)

      assert {:ok, response} = API.get_videos_by_ids("", client: client)
      assert response.items == []
    end

    test "returns error on rate limiting" do
      video_ids = YouTubeMocks.generate_video_ids(10)

      client =
        create_test_client(fn _conn ->
          {429, YouTubeMocks.error_response(429, "rateLimitExceeded")}
        end)

      assert {:error, {:http_error, 429, _body}} =
               API.get_videos_by_ids(video_ids, client: client)
    end
  end

  describe "get_channel/2" do
    test "returns channel data for valid channel ID" do
      channel_id = "UC7X2IY5-ZHKU83nyb6KejgQ"

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/channels")
          assert conn.query_string =~ "id=#{channel_id}"
          {200, YouTubeMocks.channel_response(channel_id, title: "Test Channel")}
        end)

      assert {:ok, response} = API.get_channel(channel_id, client: client)
      assert length(response.items) == 1
    end

    test "uses forUsername param for non-channel-ID queries" do
      username = "testuser"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "forUsername=#{username}"
          {200, YouTubeMocks.channel_response("UCGeneratedId12345", title: "Test User Channel")}
        end)

      assert {:ok, _response} = API.get_channel(username, client: client)
    end

    test "returns not_found for empty results" do
      client =
        create_test_client(fn _conn ->
          {200, %{"kind" => "youtube#channelListResponse", "items" => []}}
        end)

      assert {:error, :not_found} = API.get_channel("nonexistent", client: client)
    end

    test "returns error on HTTP failure" do
      client =
        create_test_client(fn _conn ->
          {500, YouTubeMocks.error_response(500, "Internal Server Error")}
        end)

      assert {:error, {:http_error, 500, _body}} =
               API.get_channel("UC123", client: client)
    end
  end

  describe "search_channels/2" do
    test "searches for channels by query" do
      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/search")
          assert conn.query_string =~ "type=channel"
          assert conn.query_string =~ "q=test"

          {200,
           %{
             "kind" => "youtube#searchListResponse",
             "pageInfo" => %{"totalResults" => 1},
             "items" => [
               %{
                 "id" => %{"channelId" => "UC123456789"},
                 "snippet" => %{
                   "title" => "Test Channel",
                   "description" => "A test channel",
                   "thumbnails" => %{"high" => %{"url" => "https://example.com/thumb.jpg"}}
                 }
               }
             ]
           }}
        end)

      assert {:ok, response} = API.search_channels("test", client: client)
      assert length(response.items) == 1
    end
  end

  describe "get_playlists_by_channel/2" do
    test "returns playlists for a channel" do
      channel_id = "UC7X2IY5-ZHKU83nyb6KejgQ"

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/playlists")
          assert conn.query_string =~ "channelId=#{channel_id}"

          {200,
           %{
             "kind" => "youtube#playlistListResponse",
             "pageInfo" => %{"totalResults" => 2},
             "items" => [
               %{
                 "id" => "PLTest1",
                 "snippet" => %{
                   "title" => "Playlist 1",
                   "description" => "First playlist",
                   "channelId" => channel_id,
                   "thumbnails" => %{"high" => %{"url" => "https://example.com/pl1.jpg"}}
                 },
                 "contentDetails" => %{"itemCount" => 10}
               },
               %{
                 "id" => "PLTest2",
                 "snippet" => %{
                   "title" => "Playlist 2",
                   "description" => "Second playlist",
                   "channelId" => channel_id,
                   "thumbnails" => %{"high" => %{"url" => "https://example.com/pl2.jpg"}}
                 },
                 "contentDetails" => %{"itemCount" => 5}
               }
             ]
           }}
        end)

      assert {:ok, response} = API.get_playlists_by_channel(channel_id, client: client)
      assert length(response.items) == 2
    end

    test "respects max_results option" do
      channel_id = "UC7X2IY5-ZHKU83nyb6KejgQ"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "maxResults=10"
          {200, %{"kind" => "youtube#playlistListResponse", "items" => [], "pageInfo" => %{}}}
        end)

      assert {:ok, _response} =
               API.get_playlists_by_channel(channel_id, max_results: 10, client: client)
    end

    test "returns error on HTTP failure" do
      client =
        create_test_client(fn _conn ->
          {500, YouTubeMocks.error_response(500, "Internal Server Error")}
        end)

      assert {:error, {:http_error, 500, _body}} =
               API.get_playlists_by_channel("UC123", client: client)
    end
  end

  describe "get_channels_by_ids/2" do
    test "returns channels for a list of IDs" do
      ids = ["UCBatchA", "UCBatchB", "UCBatchC"]

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/channels")
          assert conn.query_string =~ "id=UCBatchA%2CUCBatchB%2CUCBatchC"

          {200,
           %{
             "kind" => "youtube#channelListResponse",
             "pageInfo" => %{"totalResults" => 3},
             "items" =>
               Enum.map(ids, fn id ->
                 YouTubeMocks.channel_response(id, title: "Channel #{id}")["items"]
                 |> hd()
               end)
           }}
        end)

      assert {:ok, response} = API.get_channels_by_ids(ids, client: client)
      assert length(response.items) == 3
    end

    test "caps the batch at 50 IDs in a single request" do
      ids = Enum.map(1..55, &"UCBatchOver#{&1}")

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "id="
          # The 51st onwards should be dropped
          refute conn.query_string =~ "UCBatchOver55"
          {200, %{"kind" => "youtube#channelListResponse", "items" => [], "pageInfo" => %{}}}
        end)

      assert {:ok, _} = API.get_channels_by_ids(ids, client: client)
    end

    test "returns an empty APIResponse for an empty list" do
      assert {:ok, response} = API.get_channels_by_ids([], client: nil)
      assert response.items == []
    end

    test "returns error on HTTP failure" do
      client =
        create_test_client(fn _conn ->
          {403, YouTubeMocks.error_response(403, "forbidden")}
        end)

      assert {:error, {:http_error, 403, _body}} =
               API.get_channels_by_ids(["UC1"], client: client)
    end
  end

  describe "get_playlists_by_ids/2" do
    test "returns playlists for a list of IDs" do
      ids = ["PLBatchA", "PLBatchB"]

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/playlists")
          assert conn.query_string =~ "id=PLBatchA%2CPLBatchB"

          {200,
           %{
             "kind" => "youtube#playlistListResponse",
             "pageInfo" => %{"totalResults" => 2},
             "items" =>
               Enum.map(ids, fn id ->
                 %{
                   "id" => id,
                   "snippet" => %{
                     "title" => "Playlist #{id}",
                     "channelId" => "UCOwner",
                     "thumbnails" => %{}
                   },
                   "contentDetails" => %{"itemCount" => 1}
                 }
               end)
           }}
        end)

      assert {:ok, response} = API.get_playlists_by_ids(ids, client: client)
      assert length(response.items) == 2
    end

    test "returns an empty APIResponse for an empty list" do
      assert {:ok, response} = API.get_playlists_by_ids([], client: nil)
      assert response.items == []
    end

    test "returns error on HTTP failure" do
      client =
        create_test_client(fn _conn ->
          {500, YouTubeMocks.error_response(500, "Internal Server Error")}
        end)

      assert {:error, {:http_error, 500, _body}} =
               API.get_playlists_by_ids(["PL1"], client: client)
    end
  end

  describe "get_channel/2 identifier shape detection" do
    test "uses id= for UC… channel IDs" do
      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "id=UC7X2IY5-ZHKU83nyb6KejgQ"
          {200, YouTubeMocks.channel_response("UC7X2IY5-ZHKU83nyb6KejgQ")}
        end)

      assert {:ok, _} = API.get_channel("UC7X2IY5-ZHKU83nyb6KejgQ", client: client)
    end

    test "uses forHandle= for @handle identifiers" do
      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "forHandle=%40somehandle"
          {200, YouTubeMocks.channel_response("UCSomehandle")}
        end)

      assert {:ok, _} = API.get_channel("@somehandle", client: client)
    end
  end

  describe "search_channels/2 error path" do
    test "returns error on HTTP failure" do
      client =
        create_test_client(fn _conn ->
          {403, YouTubeMocks.error_response(403, "quotaExceeded")}
        end)

      assert {:error, {:http_error, 403, _body}} =
               API.search_channels("anything", client: client)
    end
  end

  # Helper function for creating test clients without retry behavior
  defp create_test_client(response_fn) do
    Req.new(
      base_url: "https://www.googleapis.com/youtube/v3",
      params: [key: "test-api-key"],
      plug: {TestPlug, response_fn: response_fn},
      retry: false
    )
  end
end
