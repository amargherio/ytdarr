defmodule Ytdarr.ContentOrchestrationTest do
  use Ytdarr.DataCase, async: false
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content

  test "queue_video_download/2 enqueues a downloader job and marks the video as queued" do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})

    assert {:ok, _job} = Content.queue_video_download(video.id, channel.id)

    assert {:ok, updated_video} = Content.get_video(video.id)
    assert updated_video.download_state == :queued

    assert_enqueued(
      worker: Ytdarr.ObanWorkers.VideoDownloader,
      args: %{"video_id" => video.id, "channel_id" => channel.id}
    )
  end

  test "delete_video_file/1 deletes files and resets download fields" do
    channel = channel_fixture()
    scratch_dir = scratch_dir("delete-video")
    file_path = Path.join(scratch_dir, "video.mp4")
    nfo_path = Path.rootname(file_path) <> ".nfo"

    File.mkdir_p!(scratch_dir)
    File.write!(file_path, "fake video content")
    File.write!(nfo_path, "fake nfo content")

    on_exit(fn -> File.rm_rf(scratch_dir) end)

    video =
      video_fixture(%{
        channel_id: channel.id,
        download_path: file_path,
        is_downloaded: true,
        download_state: :downloaded
      })

    assert {:ok, updated_video} = Content.delete_video_file(video.id)

    refute File.exists?(file_path)
    refute File.exists?(nfo_path)
    assert updated_video.download_state == :available
    assert updated_video.is_downloaded == false
    assert updated_video.download_path == nil
    assert updated_video.downloaded_at == nil
  end

  test "sync_content/2 enqueues a sync worker job for channels" do
    channel = channel_fixture()

    assert {:ok, _job} = Content.sync_content("channel", channel.id)

    assert_enqueued(
      worker: Ytdarr.ObanWorkers.SyncWorker,
      args: %{"source_type" => "channel", "source_id" => channel.id}
    )
  end

  test "sync_content/2 enqueues a sync worker job for playlists" do
    playlist = playlist_fixture()

    assert {:ok, _job} = Content.sync_content("playlist", playlist.id)

    assert_enqueued(
      worker: Ytdarr.ObanWorkers.SyncWorker,
      args: %{"source_type" => "playlist", "source_id" => playlist.id}
    )
  end

  test "sync_content/2 rejects unknown target types" do
    assert {:error, :unknown_target_type} = Content.sync_content("unknown", 123)
  end

  @tag skip:
         "sync_playlist_content requires a live YouTube client and cannot be isolated without adding an injection point"
  test "sync_playlist_content/1 syncs and links playlist videos" do
    playlist = playlist_fixture()

    assert {:ok, :synced} = Content.sync_playlist_content(playlist.id)
  end

  defp scratch_dir(prefix) do
    Path.join(File.cwd!(), "scratch-output/#{prefix}-#{System.unique_integer([:positive])}")
  end
end
