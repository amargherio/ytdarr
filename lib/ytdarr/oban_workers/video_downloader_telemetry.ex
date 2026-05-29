defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetry do
  @moduledoc """
  Telemetry handler for VideoDownloader Oban jobs.

  Resets video download state to `:available` when a job reaches a terminal
  failure state (cancelled or discarded). Retryable failures are NOT reset
  because the job will be retried automatically by Oban.

  This handles videos in both `:queued` and `:downloading` states, since a job
  could be cancelled before it starts executing (while still queued) or while
  actively downloading.
  """
  require Logger
  alias Ytdarr.Content

  def handle_event([:oban, :job, :exception], measurements, meta, _config) do
    handle_failure(measurements, meta)
  end

  def handle_event([:oban, :job, :stop], measurements, meta, _config) do
    # Only reset on terminal states (cancelled/discarded), not retryable failures
    if meta.state in [:cancelled, :discarded] do
      handle_failure(measurements, meta)
    else
      :ok
    end
  end

  # Handle case where worker is passed as an Atom (standard Oban behavior)
  defp handle_failure(_measurements, %{
         worker: Ytdarr.ObanWorkers.VideoDownloader,
         args: %{"video_id" => video_id}
       }) do
    reset_video_state(video_id)
  end

  # Handle case where worker is passed as a String (just in case/legacy)
  defp handle_failure(_measurements, %{
         worker: "Ytdarr.ObanWorkers.VideoDownloader",
         args: %{"video_id" => video_id}
       }) do
    reset_video_state(video_id)
  end

  defp handle_failure(_, _), do: :ok

  defp reset_video_state(video_id) do
    Logger.info(
      "VideoDownloader job failed/cancelled/discarded for video #{video_id}. Resetting state."
    )

    case Content.get_video(video_id) do
      {:ok, video} ->
        Content.update_video(video, %{
          download_state: :available,
          is_downloaded: false
        })

      _ ->
        :ok
    end
  end
end
