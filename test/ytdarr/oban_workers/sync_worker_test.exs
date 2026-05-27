defmodule Ytdarr.ObanWorkers.SyncWorkerTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo

  import Ytdarr.ContentFixtures

  alias Ytdarr.ObanWorkers.SyncWorker

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
  end
end
