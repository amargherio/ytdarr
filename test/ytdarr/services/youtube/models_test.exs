defmodule Ytdarr.Services.YouTube.ModelsTest do
  @moduledoc """
  Tests for the YouTube Models module - data structure parsing.
  """
  use ExUnit.Case, async: true

  alias Ytdarr.Services.YouTube.Models
  alias Ytdarr.YouTubeMocks

  describe "APIResponse.from_api/1" do
    test "parses basic response structure" do
      data = %{
        "kind" => "youtube#playlistItemListResponse",
        "nextPageToken" => "NEXT_TOKEN",
        "prevPageToken" => "PREV_TOKEN",
        "pageInfo" => %{"totalResults" => 100, "resultsPerPage" => 50},
        "items" => [%{"id" => "item1"}, %{"id" => "item2"}]
      }

      result = Models.APIResponse.from_api(data)

      assert result.kind == "youtube#playlistItemListResponse"
      assert result.next_page_token == "NEXT_TOKEN"
      assert result.prev_page_token == "PREV_TOKEN"
      assert result.page_info == %{"totalResults" => 100, "resultsPerPage" => 50}
      assert length(result.items) == 2
    end

    test "handles missing optional fields" do
      data = %{
        "kind" => "youtube#videoListResponse",
        "items" => []
      }

      result = Models.APIResponse.from_api(data)

      assert result.kind == "youtube#videoListResponse"
      assert result.next_page_token == nil
      assert result.prev_page_token == nil
      assert result.items == []
    end

    test "handles nil items" do
      data = %{
        "kind" => "youtube#searchListResponse"
      }

      result = Models.APIResponse.from_api(data)
      assert result.items == []
    end
  end

  describe "Channel.from_api/1" do
    test "parses full channel data" do
      channel_id = "UC7X2IY5-ZHKU83nyb6KejgQ"
      data = YouTubeMocks.channel_response(channel_id, title: "Test Channel")
      item = List.first(data["items"])

      channel = Models.Channel.from_api(item)

      assert channel.id == channel_id
      assert channel.title == "Test Channel"
      assert channel.description == "Test channel description"
      assert channel.custom_url == "@testchannel"
      assert channel.url == "https://www.youtube.com/@testchannel"
      assert channel.uploads_playlist_id == "UU7X2IY5-ZHKU83nyb6KejgQ"
    end

    test "handles channel without custom URL" do
      channel_id = "UC7X2IY5-ZHKU83nyb6KejgQ"

      item = %{
        "id" => channel_id,
        "snippet" => %{
          "title" => "Channel Without Custom URL",
          "description" => "Description",
          "thumbnails" => %{}
        },
        "contentDetails" => %{
          "relatedPlaylists" => %{"uploads" => "UU7X2IY5-ZHKU83nyb6KejgQ"}
        }
      }

      channel = Models.Channel.from_api(item)
      assert channel.url == "https://www.youtube.com/channel/#{channel_id}"
      assert channel.custom_url == nil
    end

    test "parses subscriber count as integer" do
      item = %{
        "id" => "UC123",
        "snippet" => %{
          "title" => "Test",
          "thumbnails" => %{}
        },
        "statistics" => %{
          "subscriberCount" => "50000",
          "videoCount" => "100",
          "viewCount" => "1000000"
        }
      }

      channel = Models.Channel.from_api(item)
      assert channel.subscriber_count == 50000
      assert channel.video_count == 100
      assert channel.view_count == 1_000_000
    end

    test "accepts integer statistics already parsed" do
      item = %{
        "id" => "UCIntStats",
        "snippet" => %{"title" => "Int Stats", "thumbnails" => %{}},
        "statistics" => %{
          "subscriberCount" => 7_500,
          "videoCount" => 12,
          "viewCount" => 999_999
        }
      }

      channel = Models.Channel.from_api(item)
      assert channel.subscriber_count == 7_500
      assert channel.video_count == 12
      assert channel.view_count == 999_999
    end

    test "parses search-result id format with channelId" do
      item = %{
        "id" => %{"channelId" => "UCSearchHit"},
        "snippet" => %{"title" => "Search Hit", "thumbnails" => %{}}
      }

      channel = Models.Channel.from_api(item)
      assert channel.id == "UCSearchHit"
      assert channel.title == "Search Hit"
    end
  end

  describe "Video.from_api/1" do
    test "parses video with string ID" do
      video_id = "TestVid0001"
      video_data = YouTubeMocks.video(video_id, "UC123", 0)

      video = Models.Video.from_api(video_data)

      assert video.id == video_id
      assert video.title == "Test Video Title 1"
      assert video.url == "https://www.youtube.com/watch?v=#{video_id}"
      assert video.channel_id == "UC123"
    end

    test "parses video with nested ID map (search result format)" do
      video_data = %{
        "id" => %{"videoId" => "SearchVid01"},
        "snippet" => %{
          "title" => "Search Result Video",
          "description" => "Found via search",
          "channelId" => "UCSearchChannel",
          "publishedAt" => "2025-01-15T10:00:00Z",
          "thumbnails" => %{"high" => %{"url" => "https://example.com/thumb.jpg"}}
        }
      }

      video = Models.Video.from_api(video_data)
      assert video.id == "SearchVid01"
      assert video.title == "Search Result Video"
    end

    test "parses video from playlist item format (resourceId)" do
      video_data = %{
        "snippet" => %{
          "resourceId" => %{"videoId" => "PlaylistVid"},
          "title" => "Playlist Video",
          "description" => "From a playlist",
          "channelId" => "UCPlaylistOwner",
          "publishedAt" => "2025-01-10T08:00:00Z",
          "thumbnails" => %{}
        }
      }

      video = Models.Video.from_api(video_data)
      assert video.id == "PlaylistVid"
      assert video.title == "Playlist Video"
    end
  end

  describe "Playlist.from_api/1" do
    test "parses playlist data" do
      playlist_data = %{
        "id" => "PLTest123",
        "snippet" => %{
          "title" => "My Playlist",
          "description" => "A great playlist",
          "channelId" => "UCOwner123",
          "thumbnails" => %{
            "high" => %{"url" => "https://example.com/playlist_thumb.jpg"}
          }
        },
        "contentDetails" => %{
          "itemCount" => 42
        }
      }

      playlist = Models.Playlist.from_api(playlist_data)

      assert playlist.id == "PLTest123"
      assert playlist.title == "My Playlist"
      assert playlist.description == "A great playlist"
      assert playlist.url == "https://www.youtube.com/playlist?list=PLTest123"
      assert playlist.video_count == 42
      assert playlist.channel_id == "UCOwner123"
    end

    test "handles missing content details" do
      playlist_data = %{
        "id" => "PLEmpty",
        "snippet" => %{
          "title" => "Empty Playlist",
          "description" => "",
          "channelId" => "UC123",
          "thumbnails" => %{}
        }
      }

      playlist = Models.Playlist.from_api(playlist_data)
      assert playlist.video_count == nil
    end

    test "parses search-result id format with playlistId" do
      playlist_data = %{
        "id" => %{"playlistId" => "PLSearchHit"},
        "snippet" => %{
          "title" => "Playlist Search Hit",
          "channelId" => "UCSearchOwner",
          "thumbnails" => %{}
        }
      }

      playlist = Models.Playlist.from_api(playlist_data)
      assert playlist.id == "PLSearchHit"
      assert playlist.title == "Playlist Search Hit"
      assert playlist.url == "https://www.youtube.com/playlist?list=PLSearchHit"
    end
  end

  describe "PlaylistItem.from_api/1" do
    test "parses full playlist item" do
      playlist_id = "UUTestPlaylist"
      video_ids = YouTubeMocks.generate_video_ids(1)
      response = YouTubeMocks.playlist_items_response(playlist_id, video_ids)
      item_data = List.first(response["items"])

      item = Models.PlaylistItem.from_api(item_data)

      assert item.playlist_id == playlist_id
      assert item.video_id == List.first(video_ids)
      assert item.position == 0
      assert String.contains?(item.url, "watch?v=")
      assert String.contains?(item.url, "list=")
    end

    test "returns nil for invalid data" do
      assert Models.PlaylistItem.from_api(%{}) == nil
      assert Models.PlaylistItem.from_api("invalid") == nil
    end

    test "yields a nil url when neither resourceId nor contentDetails.videoId is present" do
      data = %{
        "id" => "PLITEM-NOVID",
        "snippet" => %{
          "title" => "Orphan Item",
          "playlistId" => "PLHost",
          "channelId" => "UCHost",
          "position" => 3,
          "thumbnails" => %{}
        }
      }

      item = Models.PlaylistItem.from_api(data)
      assert item.video_id == nil
      assert item.url == nil
      assert item.position == 3
    end
  end

  describe "PlaylistImages.from_api/1" do
    test "parses all thumbnail sizes" do
      thumbnails = %{
        "default" => %{"url" => "https://example.com/default.jpg", "width" => 120, "height" => 90},
        "medium" => %{"url" => "https://example.com/medium.jpg", "width" => 320, "height" => 180},
        "high" => %{"url" => "https://example.com/high.jpg", "width" => 480, "height" => 360},
        "standard" => %{
          "url" => "https://example.com/standard.jpg",
          "width" => 640,
          "height" => 480
        },
        "maxres" => %{"url" => "https://example.com/maxres.jpg", "width" => 1280, "height" => 720}
      }

      images = Models.PlaylistImages.from_api(thumbnails)

      assert images.default["url"] == "https://example.com/default.jpg"
      assert images.high["width"] == 480
      assert images.maxres["height"] == 720
    end

    test "handles nil input" do
      images = Models.PlaylistImages.from_api(nil)
      assert %Models.PlaylistImages{} = images
      assert images.default == nil
    end

    test "handles non-map input" do
      images = Models.PlaylistImages.from_api("invalid")
      assert %Models.PlaylistImages{} = images
    end
  end

  describe "DownloadInfo.from_json/1" do
    test "parses download info from yt-dlp output" do
      data = %{
        "webpage_url" => "https://www.youtube.com/watch?v=abc123",
        "title" => "Test Video",
        "duration" => 600,
        "formats" => [
          %{
            "format_id" => "22",
            "ext" => "mp4",
            "height" => 720,
            "vcodec" => "avc1",
            "filesize" => 50_000_000
          },
          %{
            "format_id" => "18",
            "ext" => "mp4",
            "height" => 360,
            "vcodec" => "avc1",
            "filesize" => 20_000_000
          },
          %{
            "format_id" => "140",
            "ext" => "m4a",
            "vcodec" => "none",
            "filesize" => 5_000_000
          }
        ]
      }

      info = Models.DownloadInfo.from_json(data)

      assert info.url == "https://www.youtube.com/watch?v=abc123"
      assert info.title == "Test Video"
      assert info.duration == 600
      # Only video formats should be included
      assert length(info.formats) == 2
      assert info.file_size == 50_000_000
    end

    test "handles empty formats" do
      data = %{
        "webpage_url" => "https://example.com",
        "title" => "No Formats",
        "formats" => []
      }

      info = Models.DownloadInfo.from_json(data)
      assert info.formats == []
      assert info.file_size == nil
    end

    test "handles missing formats key" do
      data = %{
        "webpage_url" => "https://example.com",
        "title" => "Missing Formats"
      }

      info = Models.DownloadInfo.from_json(data)
      assert info.formats == []
      assert info.file_size == nil
    end
  end
end
