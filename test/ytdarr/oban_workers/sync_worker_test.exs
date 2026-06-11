defmodule Ytdarr.ObanWorkers.SyncWorkerTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ytdarr.ObanWorkers.SyncWorker
  alias Ytdarr.Services.YouTube.QuotaTracker

  setup do
    QuotaTracker.reset()
    on_exit(fn -> QuotaTracker.reset() end)
    :ok
  end

  describe "job creation" do
    test "creates and enqueues channel sync jobs" do
      channel = channel_fixture()

      assert {:ok, job} =
               SyncWorker.new(%{"source_type" => "channel", "source_id" => channel.id})
               |> Oban.insert()

      assert job.queue == "sync_worker"

      assert_enqueued(
        worker: SyncWorker,
        queue: "sync_worker",
        args: %{"source_type" => "channel", "source_id" => channel.id}
      )
    end

    test "creates and enqueues playlist sync jobs" do
      playlist = playlist_fixture()

      assert {:ok, job} =
               SyncWorker.new(%{"source_type" => "playlist", "source_id" => playlist.id})
               |> Oban.insert()

      assert job.queue == "sync_worker"

      assert_enqueued(
        worker: SyncWorker,
        queue: "sync_worker",
        args: %{"source_type" => "playlist", "source_id" => playlist.id}
      )
    end
  end

  describe "perform/1" do
    test "returns an error for an unknown source type" do
      assert {:error, :unknown_source_type} =
               perform_job(SyncWorker, %{"source_type" => "unknown", "source_id" => 123})
    end

    test "raises when required args are missing" do
      assert_raise FunctionClauseError, fn ->
        perform_job(SyncWorker, %{"source_type" => "channel"})
      end
    end

    test "snoozes when quota is insufficient for a channel sync" do
      channel = channel_fixture()
      QuotaTracker.record_usage(:read, 10_000)

      assert {:snooze, seconds} =
               perform_job(SyncWorker, %{
                 "source_type" => "channel",
                 "source_id" => channel.id
               })

      assert is_integer(seconds)
      assert seconds >= 60
    end

    test "snoozes when quota is insufficient for a playlist sync" do
      playlist = playlist_fixture()
      QuotaTracker.record_usage(:read, 10_000)

      assert {:snooze, seconds} =
               perform_job(SyncWorker, %{
                 "source_type" => "playlist",
                 "source_id" => playlist.id
               })

      assert is_integer(seconds)
      assert seconds >= 60
    end
  end
end
