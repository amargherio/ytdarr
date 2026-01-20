defmodule Ytdarr.YouTubeMocks do
  @moduledoc """
  Mock data generators for YouTube API responses.
  Used in tests to simulate YouTube Data API v3 responses.
  """

  @doc """
  Generates a mock channel API response.
  """
  def channel_response(channel_id, opts \\ []) do
    title = Keyword.get(opts, :title, "Test Channel")
    custom_url = Keyword.get(opts, :custom_url, "@testchannel")
    uploads_playlist_id = "UU" <> String.slice(channel_id, 2..-1//1)

    %{
      "kind" => "youtube#channelListResponse",
      "etag" => "test-etag-#{:erlang.unique_integer()}",
      "pageInfo" => %{
        "totalResults" => 1,
        "resultsPerPage" => 1
      },
      "items" => [
        %{
          "kind" => "youtube#channel",
          "etag" => "channel-etag-#{:erlang.unique_integer()}",
          "id" => channel_id,
          "snippet" => %{
            "title" => title,
            "description" => "Test channel description",
            "customUrl" => custom_url,
            "publishedAt" => "2022-01-01T00:00:00Z",
            "thumbnails" => %{
              "default" => %{
                "url" => "https://example.com/thumb_default.jpg",
                "width" => 88,
                "height" => 88
              },
              "high" => %{
                "url" => "https://example.com/thumb_high.jpg",
                "width" => 800,
                "height" => 800
              }
            },
            "country" => "US"
          },
          "contentDetails" => %{
            "relatedPlaylists" => %{
              "likes" => "",
              "uploads" => uploads_playlist_id
            }
          },
          "status" => %{
            "privacyStatus" => "public",
            "isLinked" => true,
            "madeForKids" => false
          },
          "brandingSettings" => %{
            "channel" => %{
              "title" => title,
              "description" => "Test channel description"
            },
            "image" => %{
              "bannerExternalUrl" => "https://example.com/banner.jpg"
            }
          },
          "statistics" => %{
            "subscriberCount" => "10000",
            "videoCount" => "100",
            "viewCount" => "1000000"
          }
        }
      ]
    }
  end

  @doc """
  Generates a mock playlist items API response.
  """
  def playlist_items_response(playlist_id, video_ids, opts \\ []) do
    next_page_token = Keyword.get(opts, :next_page_token)
    channel_id = Keyword.get(opts, :channel_id, "UCTestChannelId123456")

    items =
      video_ids
      |> Enum.with_index()
      |> Enum.map(fn {video_id, index} ->
        playlist_item(playlist_id, video_id, channel_id, index)
      end)

    response = %{
      "kind" => "youtube#playlistItemListResponse",
      "etag" => "playlist-etag-#{:erlang.unique_integer()}",
      "pageInfo" => %{
        "totalResults" => length(video_ids),
        "resultsPerPage" => 50
      },
      "items" => items
    }

    if next_page_token do
      Map.put(response, "nextPageToken", next_page_token)
    else
      response
    end
  end

  @doc """
  Generates a single playlist item.
  """
  def playlist_item(playlist_id, video_id, channel_id, position \\ 0) do
    item_id = Base.encode64("#{playlist_id}-#{video_id}")

    %{
      "kind" => "youtube#playlistItem",
      "etag" => "item-etag-#{:erlang.unique_integer()}",
      "id" => item_id,
      "snippet" => %{
        "publishedAt" => "2025-01-#{String.pad_leading("#{position + 1}", 2, "0")}T12:00:00Z",
        "channelId" => channel_id,
        "title" => "Test Video #{position + 1}",
        "description" => "Description for test video #{position + 1}",
        "thumbnails" => %{
          "default" => %{
            "url" => "https://i.ytimg.com/vi/#{video_id}/default.jpg",
            "width" => 120,
            "height" => 90
          },
          "high" => %{
            "url" => "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg",
            "width" => 480,
            "height" => 360
          }
        },
        "channelTitle" => "Test Channel",
        "playlistId" => playlist_id,
        "position" => position,
        "resourceId" => %{
          "kind" => "youtube#video",
          "videoId" => video_id
        },
        "videoOwnerChannelTitle" => "Test Channel",
        "videoOwnerChannelId" => channel_id
      },
      "contentDetails" => %{
        "videoId" => video_id,
        "videoPublishedAt" => "2025-01-#{String.pad_leading("#{position + 1}", 2, "0")}T12:00:00Z"
      },
      "status" => %{
        "privacyStatus" => "public"
      }
    }
  end

  @doc """
  Generates a mock videos API response.
  """
  def videos_response(video_ids, opts \\ []) do
    channel_id = Keyword.get(opts, :channel_id, "UCTestChannelId123456")

    items =
      video_ids
      |> Enum.with_index()
      |> Enum.map(fn {video_id, index} ->
        video(video_id, channel_id, index)
      end)

    %{
      "kind" => "youtube#videoListResponse",
      "etag" => "videos-etag-#{:erlang.unique_integer()}",
      "pageInfo" => %{
        "totalResults" => length(video_ids),
        "resultsPerPage" => 50
      },
      "items" => items
    }
  end

  @doc """
  Generates a single video item.
  """
  def video(video_id, channel_id, index \\ 0) do
    %{
      "kind" => "youtube#video",
      "etag" => "video-etag-#{:erlang.unique_integer()}",
      "id" => video_id,
      "snippet" => %{
        "publishedAt" => "2025-01-#{String.pad_leading("#{index + 1}", 2, "0")}T12:00:00Z",
        "channelId" => channel_id,
        "title" => "Test Video Title #{index + 1}",
        "description" => "Full description for test video #{index + 1}",
        "thumbnails" => %{
          "default" => %{
            "url" => "https://i.ytimg.com/vi/#{video_id}/default.jpg",
            "width" => 120,
            "height" => 90
          },
          "high" => %{
            "url" => "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg",
            "width" => 480,
            "height" => 360
          }
        },
        "channelTitle" => "Test Channel",
        "tags" => ["test", "video", "tag#{index}"],
        "categoryId" => "22"
      },
      "contentDetails" => %{
        "duration" => "PT#{10 + index}M#{30 + index}S",
        "dimension" => "2d",
        "definition" => "hd"
      },
      "statistics" => %{
        "viewCount" => "#{1000 * (index + 1)}",
        "likeCount" => "#{100 * (index + 1)}",
        "commentCount" => "#{10 * (index + 1)}"
      }
    }
  end

  @doc """
  Generates a list of video IDs for testing.
  """
  def generate_video_ids(count) do
    1..count
    |> Enum.map(fn i ->
      # Generate realistic-looking YouTube video IDs (11 characters)
      base = "TestVid"
      suffix = String.pad_leading("#{i}", 4, "0")
      base <> suffix
    end)
  end

  @doc """
  Generates an error response.
  """
  def error_response(status_code, reason) do
    %{
      "error" => %{
        "code" => status_code,
        "message" => reason,
        "errors" => [
          %{
            "message" => reason,
            "domain" => "youtube.api",
            "reason" => "quotaExceeded"
          }
        ]
      }
    }
  end
end
