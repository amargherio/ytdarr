defmodule Ytdarr.ObanWorkers.VideoImporter do
  @moduledoc false

  use Oban.Worker,
    queue: :video_importer,
    max_attempts: 1,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:video_id], states: :incomplete]

  alias Ytdarr.Content.Video
  alias Ytdarr.Imports.SafeMessage
  alias Ytdarr.Media.VideoImport

  require Logger

  @empty_recovery %{"mode" => nil, "entries" => []}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    run(job, video_import: VideoImport, content: Ytdarr.Content, imports: Ytdarr.Imports)
  end

  @spec run(Oban.Job.t(), keyword()) :: :ok | {:cancel, term()}
  def run(%Oban.Job{args: %{"video_id" => video_id, "channel_id" => channel_id}} = job, opts) do
    content = Keyword.fetch!(opts, :content)
    imports = Keyword.fetch!(opts, :imports)
    video_import = Keyword.fetch!(opts, :video_import)

    case content.get_video(video_id) do
      {:ok, %Video{} = video} ->
        run_for_video(job, video, channel_id, content, imports, video_import)

      {:error, reason} ->
        Logger.error(
          "Video import job #{job.id} could not load video #{video_id}: #{inspect(reason)}"
        )

        {:cancel, reason}
    end
  end

  def run(%Oban.Job{} = job, _opts) do
    Logger.error("Video import job #{job.id} has invalid arguments: #{inspect(job.args)}")
    {:cancel, :invalid_import_job}
  end

  defp run_for_video(job, video, channel_id, content, imports, video_import) do
    if importing_job?(video, job) and video.channel_id == channel_id do
      with {:ok, manifest} <- manifest_from_job(job, video_import),
           :ok <- ensure_job_paths(job, manifest),
           {:ok, channel} <- content.get_channel(channel_id) do
        stage_and_persist(job, video, channel, manifest, content, imports, video_import)
      else
        {:error, reason} -> fail_import(job, video, reason, [], content, imports)
      end
    else
      {:cancel, :video_not_importable}
    end
  end

  defp stage_and_persist(job, video, channel, manifest, content, imports, video_import) do
    case video_import.stage(job.id, manifest, channel, video) do
      {:ok, placement} ->
        persist_placement(job, video, placement, content, imports, video_import)

      {:error, reason, recovery_entries} when is_list(recovery_entries) ->
        fail_import(job, video, reason, recovery_entries, content, imports)

      {:error, reason} ->
        fail_import(job, video, reason, [], content, imports)
    end
  end

  defp persist_placement(job, video, placement, content, imports, video_import) do
    recovery = video_import.recovery_map(placement, :delete)

    case content.mark_video_imported(video, %{
           download_path: job.args["destination_path"],
           file_size: placement.file_size,
           download_quality: placement.quality,
           import_recovery: recovery
         }) do
      {:ok, imported_video} ->
        commit_cleanup(imported_video, placement, content, imports, video_import)

      {:error, reason} ->
        Logger.error("Video import job #{job.id} could not persist placement: #{inspect(reason)}")
        entries = rollback_entries(placement, video_import)
        fail_import(job, video, reason, entries, content, imports)
    end
  end

  defp commit_cleanup(imported_video, placement, content, imports, video_import) do
    case video_import.commit_cleanup(placement) do
      {:ok, []} ->
        case content.update_video_import_recovery(imported_video, %{
               import_recovery: @empty_recovery
             }) do
          {:ok, cleaned_video} ->
            :ok =
              imports.broadcast(
                {:video_import_completed, cleaned_video.channel_id, cleaned_video.id}
              )

            :ok

          {:error, reason} ->
            Logger.error(
              "Video import cleanup persistence failed for #{imported_video.id}: #{inspect(reason)}"
            )

            :ok =
              imports.broadcast(
                {:video_import_cleanup_warning, imported_video.channel_id, imported_video.id}
              )

            :ok
        end

      {:error, entries} when is_list(entries) ->
        persist_cleanup_warning(imported_video, entries, content, imports)

      unexpected ->
        Logger.error(
          "Video import cleanup failed for #{imported_video.id}: #{inspect(unexpected)}"
        )

        :ok =
          imports.broadcast(
            {:video_import_cleanup_warning, imported_video.channel_id, imported_video.id}
          )

        :ok
    end
  end

  defp persist_cleanup_warning(imported_video, entries, content, imports) do
    recovery = %{"mode" => "delete", "entries" => entries}

    case content.update_video_import_recovery(imported_video, %{import_recovery: recovery}) do
      {:ok, updated_video} ->
        :ok =
          imports.broadcast(
            {:video_import_cleanup_warning, updated_video.channel_id, updated_video.id}
          )

        :ok

      {:error, reason} ->
        Logger.error(
          "Video import cleanup journal failed for #{imported_video.id}: #{inspect(reason)}"
        )

        :ok =
          imports.broadcast(
            {:video_import_cleanup_warning, imported_video.channel_id, imported_video.id}
          )

        :ok
    end
  end

  defp fail_import(job, %Video{} = video, reason, recovery_entries, content, imports) do
    Logger.error("Video import job #{job.id} failed: #{inspect(reason)}")

    case content.get_video(video.id) do
      {:ok, current_video} ->
        persist_failure_if_current(job, current_video, reason, recovery_entries, content, imports)

      {:error, reload_reason} ->
        Logger.error(
          "Video import job #{job.id} could not reload video: #{inspect(reload_reason)}"
        )
    end

    {:cancel, reason}
  end

  defp persist_failure_if_current(job, video, reason, recovery_entries, content, imports) do
    if importing_job?(video, job) do
      recovery = %{"mode" => "restore", "entries" => recovery_entries}

      case content.mark_video_import_failed(video, %{
             import_error: SafeMessage.for(reason),
             import_recovery: recovery
           }) do
        {:ok, failed_video} ->
          :ok =
            imports.broadcast({
              :video_import_failed,
              failed_video.channel_id,
              failed_video.id,
              failed_video.import_error
            })

        {:error, persistence_reason} ->
          Logger.error(
            "Video import job #{job.id} could not persist failure: #{inspect(persistence_reason)}"
          )
      end
    else
      maybe_broadcast_downloaded_warning(video, imports)
    end
  end

  defp rollback_entries(placement, video_import) do
    case video_import.rollback(placement) do
      {:ok, []} -> []
      {:error, entries} when is_list(entries) -> entries
      _unexpected -> recovery_entries(video_import.recovery_map(placement, :restore))
    end
  end

  defp manifest_from_job(%Oban.Job{args: %{"manifest" => manifest_map}}, video_import)
       when is_map(manifest_map) do
    video_import
    |> Module.concat("Manifest")
    |> apply(:from_map, [manifest_map])
  end

  defp manifest_from_job(_job, _video_import), do: {:error, :invalid_import_manifest}

  defp ensure_job_paths(%Oban.Job{args: args}, manifest) do
    if args["source_path"] == manifest.source.source_path and
         args["destination_path"] == manifest.destination.media_path do
      :ok
    else
      {:error, :source_changed}
    end
  end

  defp importing_job?(%Video{download_state: :importing, import_job_id: job_id}, %Oban.Job{
         id: job_id
       }),
       do: true

  defp importing_job?(_video, _job), do: false

  defp maybe_broadcast_downloaded_warning(%Video{download_state: :downloaded} = video, imports) do
    case video.import_recovery do
      %{"entries" => [_ | _]} ->
        imports.broadcast({:video_import_cleanup_warning, video.channel_id, video.id})

      _ ->
        :ok
    end
  end

  defp maybe_broadcast_downloaded_warning(_video, _imports), do: :ok

  defp recovery_entries(%{"entries" => entries}) when is_list(entries), do: entries
  defp recovery_entries(_recovery), do: []
end
