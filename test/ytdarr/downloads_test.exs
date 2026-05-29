defmodule Ytdarr.DownloadsTest do
  use YtdarrWeb.ConnCase
  use Oban.Testing, repo: Ytdarr.Repo

  import Ytdarr.ContentFixtures

  alias Ytdarr.Downloads
  alias Ytdarr.ObanWorkers.{SyncWorker, VideoDownloader}
  alias Ytdarr.Repo

  describe "list_active_downloads/0" do
    test "returns empty list when no download jobs are executing" do
      assert Downloads.list_active_downloads() == []
    end

    test "returns executing download jobs with video metadata" do
      %{channel: channel, video: video} = create_video_with_channel()

      {:ok, job} =
        VideoDownloader.new(%{"video_id" => video.id, "channel_id" => channel.id})
        |> Oban.insert()

      started_at = utc_now()
      job = update_job(job, state: "executing", attempted_at: started_at)

      {:ok, other_job} =
        VideoDownloader.new(%{"video_id" => video.id, "channel_id" => channel.id})
        |> Oban.insert()

      update_job(other_job, state: "available")

      {:ok, sync_job} =
        SyncWorker.new(%{"source_type" => "channel", "source_id" => channel.id})
        |> Oban.insert()

      update_job(sync_job, state: "executing", attempted_at: started_at)

      assert [
               %{
                 job_id: job_id,
                 video_id: video_id,
                 channel_id: channel_id,
                 video_title: video_title,
                 channel_name: channel_name,
                 thumbnail_url: thumbnail_url,
                 started_at: ^started_at
               }
             ] = Downloads.list_active_downloads()

      assert job_id == job.id
      assert video_id == video.id
      assert channel_id == channel.id
      assert video_title == video.title
      assert channel_name == channel.name
      assert thumbnail_url == video.thumbnail_url
    end
  end

  describe "list_pending_downloads/0" do
    test "returns empty list when no pending jobs exist" do
      assert Downloads.list_pending_downloads() == []
    end

    test "returns available, scheduled, and retryable jobs with metadata in queue order" do
      first = create_video_with_channel()
      second = create_video_with_channel()
      third = create_video_with_channel()

      base_time = utc_now()

      available_job =
        first.video
        |> insert_download_job(first.channel)
        |> update_job(state: "available", priority: 0, scheduled_at: DateTime.add(base_time, 30))

      scheduled_job =
        second.video
        |> insert_download_job(second.channel)
        |> update_job(state: "scheduled", priority: 1, scheduled_at: base_time)

      retryable_job =
        third.video
        |> insert_download_job(third.channel)
        |> update_job(state: "retryable", priority: 1, scheduled_at: DateTime.add(base_time, 60))

      {:ok, sync_job} =
        SyncWorker.new(%{"source_type" => "channel", "source_id" => first.channel.id})
        |> Oban.insert()

      update_job(sync_job, state: "available")

      pending = Downloads.list_pending_downloads()

      assert Enum.map(pending, & &1.job_id) == [
               available_job.id,
               scheduled_job.id,
               retryable_job.id
             ]

      [available, scheduled, retryable] = pending

      assert available.job_id == available_job.id
      assert available.state == "available"
      assert available.video_title == first.video.title

      assert scheduled.job_id == scheduled_job.id
      assert scheduled.state == "scheduled"
      assert scheduled.video_title == second.video.title
      assert scheduled.channel_name == second.channel.name

      assert retryable.job_id == retryable_job.id
      assert retryable.state == "retryable"
      assert retryable.video_title == third.video.title
    end

    test "falls back to unknown metadata when the related video no longer exists" do
      {:ok, job} =
        VideoDownloader.new(%{"video_id" => 999_001, "channel_id" => 999_002})
        |> Oban.insert()

      [download] = Downloads.list_pending_downloads()

      assert download.job_id == job.id
      assert download.video_id == 999_001
      assert download.channel_id == 999_002
      assert download.video_title == "Unknown"
      assert download.channel_name == "Unknown"
      assert download.thumbnail_url == nil
    end
  end

  describe "active_count/0" do
    test "returns 0 when no jobs are executing" do
      assert Downloads.active_count() == 0
    end

    test "counts only executing video downloader jobs" do
      %{channel: channel, video: video} = create_video_with_channel()

      executing_job =
        video
        |> insert_download_job(channel)
        |> update_job(state: "executing", attempted_at: utc_now())

      available_job =
        video
        |> insert_download_job(channel)
        |> update_job(state: "available")

      {:ok, sync_job} =
        SyncWorker.new(%{"source_type" => "channel", "source_id" => channel.id})
        |> Oban.insert()

      update_job(sync_job, state: "executing")

      assert executing_job.state == "executing"
      assert available_job.state == "available"
      assert Downloads.active_count() == 1
    end
  end

  describe "pending_count/0" do
    test "counts available, scheduled, and retryable download jobs" do
      %{channel: channel, video: video} = create_video_with_channel()

      video
      |> insert_download_job(channel)
      |> update_job(state: "available")

      video
      |> insert_download_job(channel)
      |> update_job(state: "scheduled", scheduled_at: utc_now())

      video
      |> insert_download_job(channel)
      |> update_job(state: "retryable", scheduled_at: utc_now())

      video
      |> insert_download_job(channel)
      |> update_job(state: "executing", attempted_at: utc_now())

      assert Downloads.pending_count() == 3
    end
  end

  describe "queue_concurrency/0" do
    test "returns the configured concurrency limit" do
      concurrency = Downloads.queue_concurrency()

      assert is_integer(concurrency) or is_nil(concurrency)
    end
  end

  describe "queue_status/0" do
    test "returns the active, pending, and concurrency summary" do
      %{channel: channel, video: video} = create_video_with_channel()
      now = utc_now()

      video
      |> insert_download_job(channel)
      |> update_job(state: "executing", attempted_at: now)

      video
      |> insert_download_job(channel)
      |> update_job(state: "available", scheduled_at: now)

      video
      |> insert_download_job(channel)
      |> update_job(state: "scheduled", scheduled_at: DateTime.add(now, 30))

      assert Downloads.queue_status() == %{
               active: 1,
               pending: 2,
               concurrency: Downloads.queue_concurrency()
             }
    end
  end

  describe "subscribe/0 and broadcast/1" do
    test "subscriber receives broadcast events" do
      assert :ok = Downloads.subscribe()
      assert :ok = Downloads.broadcast({:test_event, "hello"})

      assert_receive {:test_event, "hello"}
    end
  end

  defp create_video_with_channel do
    unique = System.unique_integer([:positive])

    channel =
      channel_fixture(%{
        name: "Downloads Channel #{unique}",
        external_id: "downloads-channel-#{unique}",
        is_monitored: false
      })

    video =
      video_fixture(%{
        channel_id: channel.id,
        title: "Downloads Video #{unique}",
        external_id: "downloads-video-#{unique}"
      })

    %{channel: channel, video: video}
  end

  defp insert_download_job(video, channel) do
    {:ok, job} =
      VideoDownloader.new(%{"video_id" => video.id, "channel_id" => channel.id})
      |> Oban.insert()

    job
  end

  defp update_job(job, attrs) do
    job
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  defp utc_now do
    DateTime.utc_now()
  end
end
