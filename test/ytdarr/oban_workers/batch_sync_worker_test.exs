defmodule Ytdarr.ObanWorkers.BatchSyncWorkerTest do
  @moduledoc """
  Tests for `BatchSyncWorker` paths that do not require live YouTube API access:
  scheduling, no-monitored-content fast path, and the insufficient-quota guard.

  Happy-path execution with monitored channels/playlists exercises HTTP-bound
  code in `Content.sync_channel_content/1` and `Client.*`. Those paths are
  covered in Phase 4 once the Client/Content layer accepts an injectable
  `:client` option.
  """
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ecto.Query

  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.BatchSyncWorker
  alias Ytdarr.Repo
  alias Ytdarr.Services.YouTube.QuotaTracker

  setup do
    QuotaTracker.reset()
    on_exit(fn -> QuotaTracker.reset() end)
    clear_batch_sync_jobs()
    unmonitor_all_seeded()
    :ok
  end

  describe "schedule_next_sync/0" do
    test "enqueues a job in the batch_sync queue" do
      assert {:ok, job} = BatchSyncWorker.schedule_next_sync()
      assert job.queue == "batch_sync"
      assert job.worker == "Ytdarr.ObanWorkers.BatchSyncWorker"
      assert job.scheduled_at != nil
    end
  end

  describe "perform/1" do
    test "returns :ok when no monitored content exists" do
      before = batch_sync_job_count()

      assert :ok = perform_job(BatchSyncWorker, %{})
      assert batch_sync_job_count() == before + 1
    end

    test "does not schedule next sync when one_off is true" do
      before = batch_sync_job_count()
      assert :ok = perform_job(BatchSyncWorker, %{"one_off" => true})
      assert batch_sync_job_count() == before
    end

    test "returns :ok when quota is insufficient" do
      QuotaTracker.record_usage(:read, 10_000)

      before = batch_sync_job_count()

      assert :ok = perform_job(BatchSyncWorker, %{})
      assert batch_sync_job_count() == before + 1
    end

    test "does not schedule next sync when quota is insufficient and one_off is true" do
      QuotaTracker.record_usage(:read, 10_000)

      before = batch_sync_job_count()
      assert :ok = perform_job(BatchSyncWorker, %{"one_off" => true})
      assert batch_sync_job_count() == before
    end
  end

  defp batch_sync_job_count do
    Repo.aggregate(
      from(j in Oban.Job, where: j.worker == "Ytdarr.ObanWorkers.BatchSyncWorker"),
      :count,
      :id
    )
  end

  defp clear_batch_sync_jobs do
    Repo.delete_all(from(j in Oban.Job, where: j.worker == "Ytdarr.ObanWorkers.BatchSyncWorker"))
  end

  # The test DB carries seeded monitored channels/playlists from `mix ash.setup`.
  # Unmonitor them inside the sandboxed transaction so each test starts from
  # a deterministic empty-monitored state without touching real data.
  defp unmonitor_all_seeded do
    Content.list_monitored_channels!()
    |> Enum.each(fn channel ->
      {:ok, _} = Content.unmonitor_channel(channel)
    end)

    Content.list_monitored_playlists!()
    |> Enum.each(fn playlist ->
      {:ok, _} = Content.unmonitor_playlist(playlist)
    end)
  end
end
