defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetryTest do
  use Ytdarr.DataCase

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.VideoDownloaderTelemetry

  test "resets a downloading video from terminal Oban failure metadata" do
    {video, job} = downloading_video()

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :exception],
               %{},
               %{job: job, state: :failure, reason: :download_failed},
               %{}
             )

    assert_available(video.id)
  end

  test "resets a queued video when a downloader job is cancelled before execution" do
    {video, job} = queued_video()

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :job, :stop],
               %{},
               %{job: job, state: :cancelled},
               %{}
             )

    assert_available(video.id)
  end

  test "resets a scheduled video when its downloader job is deleted" do
    {video, job} = queued_video()

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :delete_job, :stop],
               %{},
               %{job: %{job | state: "scheduled"}},
               %{}
             )

    assert_available(video.id)
  end

  test "resets every queued downloader video from bulk cancellation and deletion metadata" do
    {cancelled_video, cancelled_job} = queued_video()
    {deleted_video, deleted_job} = queued_video()

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :cancel_all_jobs, :stop],
               %{},
               %{jobs: [%{id: cancelled_job.id, queue: "video_downloader", state: "available"}]},
               %{}
             )

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :delete_all_jobs, :stop],
               %{},
               %{jobs: [%{id: deleted_job.id, queue: "video_downloader", state: "scheduled"}]},
               %{}
             )

    assert_available(cancelled_video.id)
    assert_available(deleted_video.id)
  end

  test "does not downgrade a completed download or newer job from stale telemetry" do
    {video, job} = downloading_video()

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
               %{job: job, state: :cancelled},
               %{}
             )

    assert {:ok, fresh_video} = Content.get_video(downloaded.id)
    assert fresh_video.download_state == :downloaded
    assert fresh_video.download_path == "/tmp/downloaded.mp4"
    assert is_nil(fresh_video.download_job_id)

    {newer_video, newer_job} = queued_video()
    stale_job = %{newer_job | id: newer_job.id - 1}

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :delete_all_jobs, :stop],
               %{},
               %{jobs: [%{id: stale_job.id, queue: "video_downloader", state: "available"}]},
               %{}
             )

    assert {:ok, untouched_video} = Content.get_video(newer_video.id)
    assert untouched_video.download_state == :queued
    assert untouched_video.download_job_id == newer_job.id
  end

  test "ignores other workers, queues, and executing engine jobs" do
    {video, job} = queued_video()
    other_job = %{job | worker: "SomeOtherWorker"}

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :cancel_job, :stop],
               %{},
               %{job: other_job},
               %{}
             )

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :delete_all_jobs, :stop],
               %{},
               %{jobs: [%{id: job.id, queue: "default", state: "available"}]},
               %{}
             )

    assert :ok =
             VideoDownloaderTelemetry.handle_event(
               [:oban, :engine, :cancel_all_jobs, :stop],
               %{},
               %{jobs: [%{id: job.id, queue: "video_downloader", state: "executing"}]},
               %{}
             )

    assert {:ok, untouched_video} = Content.get_video(video.id)
    assert untouched_video.download_state == :queued
    assert untouched_video.download_job_id == job.id
  end

  defp queued_video do
    video = video_fixture()
    assert {:ok, queued} = Content.begin_video_download(video)
    job = downloader_job(queued.id)
    assert {:ok, linked} = Content.set_video_download_job(queued, %{download_job_id: job.id})
    {linked, job}
  end

  defp downloading_video do
    {queued, job} = queued_video()
    assert {:ok, downloading} = Content.start_video_download(queued)
    {downloading, job}
  end

  defp assert_available(video_id) do
    assert {:ok, updated_video} = Content.get_video(video_id)
    assert updated_video.download_state == :available
    refute updated_video.is_downloaded
    assert is_nil(updated_video.download_job_id)
  end

  defp downloader_job(video_id) do
    %Oban.Job{
      id: System.unique_integer([:positive]),
      worker: "Ytdarr.ObanWorkers.VideoDownloader",
      args: %{"video_id" => video_id}
    }
  end
end
