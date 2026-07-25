defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetry do
  @moduledoc false

  alias Ytdarr.Content

  @worker "Ytdarr.ObanWorkers.VideoDownloader"
  @terminal_states [:cancelled, :discard, :discarded]

  def handle_event([:oban, :job, :exception], _measurements, %{job: %Oban.Job{} = job}, _config) do
    reset_video_state(job)
  end

  def handle_event(
        [:oban, :job, :stop],
        _measurements,
        %{job: %Oban.Job{} = job, state: state},
        _config
      )
      when state in @terminal_states do
    reset_video_state(job)
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  defp reset_video_state(%Oban.Job{worker: @worker, args: %{"video_id" => video_id}})
       when is_integer(video_id) do
    case Content.get_video(video_id) do
      {:ok, video} ->
        case Content.reset_video_download(video) do
          {:ok, _reset_video} -> :ok
          {:error, _stale_or_invalid} -> :ok
        end

      {:error, _not_found} ->
        :ok
    end
  end

  defp reset_video_state(_job), do: :ok
end
