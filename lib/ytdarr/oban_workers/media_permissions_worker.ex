defmodule Ytdarr.ObanWorkers.MediaPermissionsWorker do
  @moduledoc """
  Applies a captured media ownership and mode policy to all configured roots.

  Traversal is best-effort. Individual path failures are summarized in the
  completed job metadata so operators can correct host permissions and rerun.
  """

  use Oban.Worker,
    queue: :media_permissions,
    max_attempts: 1,
    unique: [
      period: :infinity,
      fields: [:worker, :queue, :args],
      states: :incomplete
    ]

  alias Ytdarr.{MediaPermissions, Settings}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    started_at = DateTime.utc_now()

    case MediaPermissions.policy_from_args(job.args) do
      {:ok, policy} ->
        summary = normalize_all_roots(policy)
        status = if summary.failed == 0, do: "completed", else: "completed_with_errors"
        metadata = completion_metadata(job, status, started_at, summary)

        with {:ok, _updated_job} <- Oban.update_job(job, %{meta: metadata}) do
          Logger.info(
            "Media permission normalization #{status}: " <>
              "#{summary.files} files, #{summary.directories} directories, " <>
              "#{summary.skipped} skipped, #{summary.failed} failed"
          )

          MediaPermissions.broadcast({:media_permissions_completed, job.id, metadata})
          :ok
        end

      {:error, reason} ->
        metadata = failure_metadata(job, started_at, reason)
        _result = Oban.update_job(job, %{meta: metadata})
        MediaPermissions.broadcast({:media_permissions_failed, job.id, metadata})
        {:cancel, inspect(reason)}
    end
  end

  @doc false
  def configured_roots do
    Settings.list_media_root_folders!()
    |> Enum.map(&Path.expand(&1.path))
    |> Enum.uniq()
    |> Enum.sort_by(&byte_size/1)
    |> Enum.reduce([], fn root, selected ->
      if Enum.any?(selected, &inside_root?(root, &1)), do: selected, else: selected ++ [root]
    end)
  end

  defp normalize_all_roots(policy) do
    Enum.reduce(configured_roots(), MediaPermissions.empty_summary(), fn root, acc ->
      root_summary =
        case MediaPermissions.normalize_tree(root, policy) do
          {:ok, summary} -> summary
          {:error, reason} -> root_error_summary(root, reason)
        end

      MediaPermissions.merge_summaries(acc, root_summary)
    end)
  end

  defp completion_metadata(job, status, started_at, summary) do
    Map.merge(job.meta, %{
      "status" => status,
      "policy" => job.args,
      "started_at" => DateTime.to_iso8601(started_at),
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "files" => summary.files,
      "directories" => summary.directories,
      "skipped" => summary.skipped,
      "failed" => summary.failed,
      "errors" => Enum.map(summary.errors, &serialize_error/1)
    })
  end

  defp failure_metadata(job, started_at, reason) do
    Map.merge(job.meta, %{
      "status" => "failed",
      "policy" => job.args,
      "started_at" => DateTime.to_iso8601(started_at),
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "files" => 0,
      "directories" => 0,
      "skipped" => 0,
      "failed" => 1,
      "errors" => [%{"operation" => "validate_policy", "reason" => inspect(reason)}]
    })
  end

  defp serialize_error(error) do
    %{
      "path" => error.path,
      "operation" => to_string(error.operation),
      "reason" => inspect(error.reason)
    }
  end

  defp root_error_summary(root, reason) do
    %{
      files: 0,
      directories: 0,
      skipped: 0,
      failed: 1,
      errors: [%{path: root, operation: :normalize_root, reason: reason}]
    }
  end

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")
end
