defmodule Ytdarr.ObanWorkers.VideoImporterTelemetry do
  @moduledoc false

  alias Ytdarr.Imports.Recovery

  require Logger

  @worker "Ytdarr.ObanWorkers.VideoImporter"
  @terminal_states [:success, :cancelled, :discard, :discarded]
  @engine_operations [:cancel_job, :cancel_all_jobs, :delete_job, :delete_all_jobs]

  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{job: %Oban.Job{} = job} = meta,
        config
      ) do
    recover_terminal_job(job, Map.get(meta, :reason, :import_failed), config)
  end

  def handle_event(
        [:oban, :job, :stop],
        _measurements,
        %{job: %Oban.Job{} = job, state: state},
        config
      )
      when state in @terminal_states do
    recover_terminal_job(job, :import_failed, config)
  end

  def handle_event(
        [:oban, :engine, operation, :stop],
        _measurements,
        %{job: %Oban.Job{} = job},
        config
      )
      when operation in @engine_operations do
    if job.state in ["executing", :executing] do
      :ok
    else
      recover_terminal_job(job, :import_failed, config)
    end
  end

  def handle_event(
        [:oban, :engine, operation, :stop],
        _measurements,
        %{jobs: jobs},
        config
      )
      when operation in @engine_operations and is_list(jobs) do
    Enum.each(jobs, fn
      %{id: job_id, state: state} when is_integer(job_id) ->
        if state in ["executing", :executing] do
          :ok
        else
          recover_terminal_job_id(job_id, config)
        end

      _job ->
        :ok
    end)

    :ok
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  defp recover_terminal_job(%Oban.Job{worker: @worker} = job, reason, config) do
    opts = recovery_opts(config, reason)

    case Recovery.recover_job_id(job.id, opts) do
      {:ok, _failed_video} ->
        :ok

      {:error, :not_found} ->
        warn_if_already_imported(job, opts)

      {:error, recovery_reason} ->
        Logger.error(
          "Importer telemetry recovery failed for job #{job.id}: #{inspect(recovery_reason)}"
        )

        warn_if_already_imported(job, opts)
    end
  end

  defp recover_terminal_job(_job, _reason, _config), do: :ok

  defp recover_terminal_job_id(job_id, config) do
    opts = recovery_opts(config, :import_failed)

    case Recovery.recover_job_id(job_id, opts) do
      {:ok, _failed_video} ->
        :ok

      {:error, :not_found} ->
        :ok

      {:error, recovery_reason} ->
        Logger.error(
          "Importer telemetry bulk recovery failed for job #{job_id}: #{inspect(recovery_reason)}"
        )

        :ok
    end
  end

  defp warn_if_already_imported(%Oban.Job{args: %{"video_id" => video_id}}, opts)
       when is_integer(video_id) do
    content = Keyword.fetch!(opts, :content)

    case content.get_video(video_id) do
      {:ok, video} -> Recovery.broadcast_downloaded_warning(video, opts)
      {:error, _reason} -> :ok
    end
  end

  defp warn_if_already_imported(_job, _opts), do: :ok

  defp recovery_opts(config, reason) when is_map(config) do
    [
      content: Map.get(config, :content, Ytdarr.Content),
      imports: Map.get(config, :imports, Ytdarr.Imports),
      video_import: Map.get(config, :video_import, Ytdarr.Media.VideoImport),
      reason: reason
    ]
  end

  defp recovery_opts(_config, reason) do
    [
      content: Ytdarr.Content,
      imports: Ytdarr.Imports,
      video_import: Ytdarr.Media.VideoImport,
      reason: reason
    ]
  end
end
