defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetry do
  @moduledoc """
  Telemetry handler for VideoDownloader Oban jobs.
  Resets video state if the job is cancelled or discarded.
  """
  require Logger
  alias Ytdarr.Content

  def handle_event([:oban, :job, :exception], measurements, meta, _config) do
    handle_failure(measurements, meta)
  end

  def handle_event([:oban, :job, :stop], measurements, meta, _config) do
    # Check if state is cancelled or discarded
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
