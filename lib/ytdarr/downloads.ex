defmodule Ytdarr.Downloads do
  @moduledoc """
  Public API for the download queue subsystem.

  This module provides functions to query and observe video downloads managed
  by Oban's `video_downloader` queue. It is the single entry point that the
  LiveView and other consumers should use — callers never need to query
  Oban tables or the tracker directly.

  ## How the queue works

  Video downloads are processed by `Ytdarr.ObanWorkers.VideoDownloader` jobs
  running in the `:video_downloader` Oban queue. The queue has a configurable
  concurrency limit (e.g. 2), meaning at most that many downloads run
  simultaneously. When more jobs are enqueued than slots are available, the
  extras wait in "available" state until a slot frees up.

  ### Job states mapped to UI concepts

  | Oban job state           | UI concept           | Video `download_state` |
  |--------------------------|----------------------|------------------------|
  | `executing`              | Active download      | `:downloading`         |
  | `available`, `scheduled` | Pending in queue     | `:queued`              |
  | `retryable`              | Pending retry        | `:queued`              |
  | `completed`              | Done (not shown)     | `:downloaded`          |
  | `cancelled`, `discarded` | Failed (not shown)   | `:available`           |

  ## PubSub events

  All download lifecycle events are broadcast on the `"downloads"` PubSub
  topic via `Phoenix.PubSub`. Subscribe with:

      Phoenix.PubSub.subscribe(Ytdarr.PubSub, "downloads")

  Events:

  * `{:download_queued, video_id, %{title: String.t(), channel_name: String.t()}}`
  * `{:download_started, job_id, video_id, %{title: String.t(), channel_name: String.t()}}`
  * `{:download_progress, job_id, video_id, %{pct: float(), speed: String.t(), eta: String.t()}}`
  * `{:download_completed, job_id, video_id}`
  * `{:download_failed, job_id, video_id, reason}`
  """

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias Ytdarr.Repo

  @pubsub Ytdarr.PubSub
  @topic "downloads"
  @queue "video_downloader"
  @worker "Ytdarr.ObanWorkers.VideoDownloader"

  # ---------------------------------------------------------------------------
  # PubSub helpers
  # ---------------------------------------------------------------------------

  @doc """
  Subscribe the calling process to download lifecycle events.

  The subscriber will receive messages matching the event tuples documented
  in the module doc.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Broadcast a download event to all subscribers.

  This is called internally by the `VideoDownloader` worker and the
  `DownloadTracker`; you typically don't call it from application code.
  """
  def broadcast(event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, event)
  end

  # ---------------------------------------------------------------------------
  # Queue queries
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of currently executing download jobs with video and channel
  metadata.

  Each item is a map with keys: `:job_id`, `:video_id`, `:channel_id`,
  `:video_title`, `:channel_name`, `:thumbnail_url`, `:started_at`.

  These are the jobs that Oban has picked up and is actively running — at most
  `queue_concurrency/0` of them at any time.
  """
  def list_active_downloads do
    from(j in Oban.Job,
      where: j.queue == @queue and j.worker == @worker and j.state == "executing",
      order_by: [asc: j.attempted_at],
      select: %{
        job_id: j.id,
        args: j.args,
        started_at: j.attempted_at
      }
    )
    |> Repo.all()
    |> enrich_with_video_data()
  end

  @doc """
  Returns the list of pending download jobs (waiting for a concurrency slot).

  Includes jobs in "available", "scheduled", and "retryable" Oban states.
  Results are ordered approximately by Oban's fetch order: priority ascending,
  then scheduled_at ascending, then id ascending.

  Queue position is approximate — Oban may pick jobs in a slightly different
  order depending on timing and node contention.
  """
  def list_pending_downloads do
    from(j in Oban.Job,
      where:
        j.queue == @queue and j.worker == @worker and
          j.state in ["available", "scheduled", "retryable"],
      order_by: [asc: j.priority, asc: j.scheduled_at, asc: j.id],
      select: %{
        job_id: j.id,
        args: j.args,
        scheduled_at: j.scheduled_at,
        state: j.state
      }
    )
    |> Repo.all()
    |> enrich_with_video_data()
  end

  @doc """
  Returns the count of currently executing downloads.
  Useful for sidebar badge display.
  """
  def active_count do
    from(j in Oban.Job,
      where: j.queue == @queue and j.worker == @worker and j.state == "executing",
      select: count(j.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns the configured concurrency limit for the `video_downloader` queue.

  This value is read from `Oban.config()` at runtime, so it reflects any
  changes made via `Oban.scale_queue/2` or config reloads. It determines
  the maximum number of simultaneous downloads.

  Returns `nil` if the queue is not configured (should not happen in normal
  operation).
  """
  def queue_concurrency do
    runtime_limit =
      case Oban.config() do
        %{queues: queues} -> queue_limit(Keyword.get(queues, :video_downloader))
        _ -> nil
      end

    runtime_limit || configured_queue_limit(:video_downloader)
  end

  defp configured_queue_limit(queue) do
    :ytdarr
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Keyword.get(queue)
    |> queue_limit()
  end

  @doc """
  Returns a summary of the download queue status.

  Returns `%{active: integer, pending: integer, concurrency: integer | nil}`.
  This is a convenience function for the UI header showing
  "X of Y download slots in use, Z pending".
  """
  def queue_status do
    %{
      active: active_count(),
      pending: pending_count(),
      concurrency: queue_concurrency()
    }
  end

  @doc false
  def pending_count do
    from(j in Oban.Job,
      where:
        j.queue == @queue and j.worker == @worker and
          j.state in ["available", "scheduled", "retryable"],
      select: count(j.id)
    )
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Enrich Oban job data with video and channel metadata from the database.
  # Falls back gracefully if the video or channel no longer exists.
  defp enrich_with_video_data(jobs) do
    video_ids =
      jobs
      |> Enum.map(fn %{args: args} -> args["video_id"] end)
      |> Enum.reject(&is_nil/1)

    videos =
      if video_ids == [] do
        %{}
      else
        Ytdarr.Content.Video
        |> Ash.Query.filter(id in ^video_ids)
        |> Ash.Query.load([:channel])
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      end

    Enum.map(jobs, fn job ->
      video_id = job.args["video_id"]
      channel_id = job.args["channel_id"]
      video = Map.get(videos, video_id)

      Map.merge(job, %{
        video_id: video_id,
        channel_id: channel_id,
        video_title: if(video, do: video.title, else: "Unknown"),
        channel_name: if(video && video.channel, do: video.channel.name, else: "Unknown"),
        thumbnail_url: if(video, do: video.thumbnail_url)
      })
    end)
  end

  defp queue_limit(nil), do: nil
  defp queue_limit(config) when is_integer(config), do: config
  defp queue_limit(config) when is_list(config), do: Keyword.get(config, :limit)
  defp queue_limit(%{limit: limit}), do: limit
  defp queue_limit(_), do: nil
end
