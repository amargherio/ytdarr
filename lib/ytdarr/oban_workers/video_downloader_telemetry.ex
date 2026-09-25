defmodule Ytdarr.ObanWorkers.VideoDownloaderTelemetry do
  @moduledoc false

  alias Ytdarr.Content

  @worker "Ytdarr.ObanWorkers.VideoDownloader"
  @queue "video_downloader"
  @terminal_states [:cancelled, :discard, :discarded]
  @engine_operations [:cancel_job, :cancel_all_jobs, :delete_job, :delete_all_jobs]

  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{job: %Oban.Job{} = job, state: :discard},
        _config
      ) do
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

  def handle_event(
        [:oban, :engine, operation, :stop],
        _measurements,
        %{job: %Oban.Job{} = job},
        _config
      )
      when operation in @engine_operations do
    reset_nonexecuting_job(job)
  end

  def handle_event(
        [:oban, :engine, operation, :stop],
        _measurements,
        %{jobs: jobs},
        config
      )
      when operation in @engine_operations and is_list(jobs) do
    Enum.each(jobs, &reset_nonexecuting_bulk_job(&1, config))
    :ok
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  defp reset_nonexecuting_job(%Oban.Job{state: state}) when state in ["executing", :executing],
    do: :ok

  defp reset_nonexecuting_job(job), do: reset_video_state(job)

  defp reset_nonexecuting_bulk_job(%Oban.Job{} = job, _config), do: reset_nonexecuting_job(job)

  defp reset_nonexecuting_bulk_job(%{id: _job_id, state: state}, _config)
       when state in ["executing", :executing],
       do: :ok

  defp reset_nonexecuting_bulk_job(%{id: job_id, queue: @queue}, _config)
       when is_integer(job_id) do
    reset_video_state_by_job_id(job_id)
  end

  defp reset_nonexecuting_bulk_job(_job, _config), do: :ok

  defp reset_video_state_by_job_id(job_id) do
    case Content.get_video_by_download_job_id(job_id) do
      {:ok, video} -> reset_video_state(video)
      {:error, _not_found} -> :ok
    end
  end

  defp reset_video_state(%Oban.Job{worker: @worker, id: job_id, args: %{"video_id" => video_id}})
       when is_integer(job_id) and is_integer(video_id) do
    case Content.get_video_by_download_job_id(job_id) do
      {:ok, %{id: ^video_id} = video} -> reset_video_state(video)
      {:ok, _different_video} -> :ok
      {:error, _not_found} -> :ok
    end
  end

  defp reset_video_state(%{download_job_id: _job_id} = video) do
    case Content.reset_video_download(video) do
      {:ok, _reset_video} -> :ok
      {:error, _stale_or_invalid} -> :ok
    end
  end

  defp reset_video_state(_job), do: :ok
end
