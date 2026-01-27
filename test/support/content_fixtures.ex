defmodule Ytdarr.ContentFixtures do
  @moduledoc """
  Test fixtures for Content domain resources.
  """

  alias Ytdarr.Content

  @doc """
  Generate a channel.
  """
  def channel_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Test Channel #{unique_id}",
        external_id: "UC#{unique_id}TESTCHANNEL",
        url: "https://www.youtube.com/channel/UC#{unique_id}TESTCHANNEL",
        description: "A test channel description",
        platform: "YouTube",
        avatar_url: "https://example.com/avatar.jpg",
        is_monitored: false
      })

    {:ok, channel} = Content.create_channel(attrs)
    channel
  end

  @doc """
  Generate a playlist.
  """
  def playlist_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    # Get or create a channel for the playlist
    channel_id = attrs[:channel_id] || channel_fixture().id

    attrs =
      attrs
      |> Map.delete(:channel_id)
      |> Enum.into(%{
        name: "Test Playlist #{unique_id}",
        external_id: "PL#{unique_id}TESTPLAYLIST",
        url: "https://www.youtube.com/playlist?list=PL#{unique_id}TESTPLAYLIST",
        description: "A test playlist description",
        video_count: 10,
        is_monitored: false
      })

    {:ok, playlist} = Content.create_playlist(channel_id, attrs)
    playlist
  end

  @doc """
  Generate a video.
  """
  def video_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    # Get or create a channel for the video
    channel_id = attrs[:channel_id] || channel_fixture().id

    attrs =
      attrs
      |> Map.delete(:channel_id)
      |> Enum.into(%{
        title: "Test Video #{unique_id}",
        external_id: "video#{unique_id}",
        url: "https://www.youtube.com/watch?v=video#{unique_id}",
        description: "A test video description",
        thumbnail_url: "https://example.com/thumbnail.jpg",
        duration: 300,
        upload_date: Date.utc_today()
      })

    {:ok, video} = Content.create_video(channel_id, attrs)
    video
  end
end
