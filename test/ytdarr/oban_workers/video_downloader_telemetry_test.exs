defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetryTest do
  use Ytdarr.DataCase

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.VideoDownloaderTelemetry

  test "resets a downloading video from real Oban exception metadata" do
    video = downloading_video()
    job = downloader_job(video.id)

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :exception],
               %{},
               %{job: job, state: :failure, reason: :download_failed},
               %{}
             )

    assert {:ok, updated_video} = Content.get_video(video.id)
    assert updated_video.download_state == :available
    refute updated_video.is_downloaded
  end

  test "resets a queued video when a downloader job is cancelled before execution" do
    video = video_fixture()
    assert {:ok, queued} = Content.begin_video_download(video)

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: downloader_job(queued.id), state: :cancelled},
               %{}
             )

    assert {:ok, updated_video} = Content.get_video(queued.id)
    assert updated_video.download_state == :available
  end

  test "does not downgrade an already downloaded video from stale terminal telemetry" do
    video = downloading_video()

    assert {:ok, downloaded} =
             Content.mark_video_downloaded(video, %{
               download_path: "/tmp/downloaded.mp4",
               file_size: 1,
               download_quality: "720p"
             })

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: downloader_job(downloaded.id), state: :cancelled},
               %{}
             )

    assert {:ok, fresh_video} = Content.get_video(downloaded.id)
    assert fresh_video.download_state == :downloaded
    assert fresh_video.download_path == "/tmp/downloaded.mp4"
  end

  test "ignores other workers and non-terminal stops" do
    other_job = %Oban.Job{worker: "SomeOtherWorker", args: %{"video_id" => 123}}

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: other_job, state: :cancelled},
               %{}
             )

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: downloader_job(123), state: :success},
               %{}
             )
  end

  defp downloading_video do
    video = video_fixture()
    assert {:ok, queued} = Content.begin_video_download(video)
    assert {:ok, downloading} = Content.start_video_download(queued)
    downloading
  end

  defp downloader_job(video_id) do
    %Oban.Job{
      id: System.unique_integer([:positive]),
      worker: "Ytdarr.ObanWorkers.VideoDownloader",
      args: %{"video_id" => video_id}
    }
  end
end
