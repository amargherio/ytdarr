defmodule Ytdarr.ContentOrchestrationTest do
  use Ytdarr.DataCase, async: false
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content

  test "queue_video_download/2 atomically enqueues a downloader job and marks the video queued" do
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

  test "queue_video_download/2 rejects a mismatched channel without changing the video" do
    channel = channel_fixture()
    other_channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})

    assert {:error, :video_not_importable} =
             Content.queue_video_download(video.id, other_channel.id)

    assert {:ok, unchanged_video} = Content.get_video(video.id)
    assert unchanged_video.download_state == :available
  end

  test "queue_video_download/2 rejects blocklisted videos without enqueueing a job" do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id, is_blocklisted: true})

    assert {:error, :video_blocklisted} = Content.queue_video_download(video.id, channel.id)

    assert {:ok, unchanged_video} = Content.get_video(video.id)
    assert unchanged_video.download_state == :available
    assert [] == all_enqueued(worker: Ytdarr.ObanWorkers.VideoDownloader)
  end

  test "a second download request cannot enqueue a second incomplete job" do
    channel = channel_fixture()
    video = video_fixture(%{channel_id: channel.id})

    assert {:ok, _job} = Content.queue_video_download(video.id, channel.id)
    assert {:error, _reason} = Content.queue_video_download(video.id, channel.id)

    assert [job] = all_enqueued(worker: Ytdarr.ObanWorkers.VideoDownloader)
    assert job.args["video_id"] == video.id
  end

  test "delete_video_file/1 removes every regular same-stem artifact before resetting state" do
    channel = channel_fixture()
    scratch_dir = scratch_dir("delete-video")
    file_path = Path.join(scratch_dir, "video.mp4")
    nfo_path = Path.rootname(file_path) <> ".nfo"
    subtitle_path = Path.rootname(file_path) <> ".en.srt"
    unrelated_path = Path.join(scratch_dir, "other.mp4")

    File.mkdir_p!(scratch_dir)
    File.write!(file_path, "fake video content")
    File.write!(nfo_path, "fake nfo content")
    File.write!(subtitle_path, "fake subtitle content")
    File.write!(unrelated_path, "other")

    on_exit(fn -> File.rm_rf(scratch_dir) end)

    video = video_fixture(%{channel_id: channel.id})
    assert {:ok, queued} = Content.begin_video_download(video)
    assert {:ok, downloading} = Content.start_video_download(queued)

    assert {:ok, downloaded} =
             Content.mark_video_downloaded(downloading, %{
               download_path: file_path,
               file_size: 18,
               download_quality: "1080p"
             })

    assert {:ok, updated_video} = Content.delete_video_file(downloaded.id)

    refute File.exists?(file_path)
    refute File.exists?(nfo_path)
    refute File.exists?(subtitle_path)
    assert File.exists?(unrelated_path)
    assert updated_video.download_state == :available
    refute updated_video.is_downloaded
    assert is_nil(updated_video.download_path)
    assert is_nil(updated_video.downloaded_at)
  end

  defp scratch_dir(prefix) do
    Path.join(File.cwd!(), "scratch-output/#{prefix}-#{System.unique_integer([:positive])}")
  end
end
