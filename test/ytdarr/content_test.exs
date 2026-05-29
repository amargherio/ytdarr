defmodule Ytdarr.ContentTest do
  use Ytdarr.DataCase

  alias Ytdarr.Content

  describe "videos" do
    test "queue_video_download updates state to queued" do
      {:ok, channel} =
        Content.create_channel(%{
          external_id: "channel1",
          name: "Test Channel",
          url: "https://youtube.com/channel1"
        })

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "video1",
          title: "Test Video",
          url: "http://example.com/video1",
          download_state: :available
        })

      assert {:ok, _job} = Content.queue_video_download(video.id, channel.id)

      {:ok, updated_video} = Content.get_video(video.id)
      assert updated_video.download_state == :queued
    end

    test "delete_video_file deletes file and resets state" do
      {:ok, channel} =
        Content.create_channel(%{
          external_id: "channel2",
          name: "Test Channel 2",
          url: "https://youtube.com/channel2"
        })

      # Create a dummy file
      file_path = "/tmp/test_video_#{System.unique_integer()}.mp4"
      File.write!(file_path, "dummy content")

      {:ok, video} =
        Content.create_video(channel.id, %{
          external_id: "video2",
          title: "Test Video 2",
          url: "http://example.com/video2",
          download_state: :downloaded,
          is_downloaded: true,
          download_path: file_path
        })

      assert {:ok, updated_video} = Content.delete_video_file(video.id)

      assert updated_video.download_state == :available
      assert updated_video.is_downloaded == false
      assert updated_video.download_path == nil
      refute File.exists?(file_path)
    end
  end
end
