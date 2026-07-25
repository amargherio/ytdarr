defmodule Ytdarr.Imports.Reconciler do
  @moduledoc false

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Ytdarr.Content.Video
  alias Ytdarr.Imports.Recovery

  require Logger

  @worker "Ytdarr.ObanWorkers.VideoImporter"
  @pending_states ["available", "scheduled", "retryable"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    case reconcile(opts) do
      :ok -> {:ok, %{}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @spec reconcile(keyword()) :: :ok | {:error, term()}
  def reconcile(opts \\ []) do
    repo = Keyword.get(opts, :repo, Ytdarr.Repo)
    content = Keyword.get(opts, :content, Ytdarr.Content)
    recovery_opts = recovery_opts(opts, content)

    try do
      with :ok <- reconcile_executing_jobs(repo, recovery_opts),
           {:ok, importing_videos} <- content.list_importing_videos(),
           :ok <- reconcile_remaining_videos(importing_videos, repo, recovery_opts) do
        :ok
      end
    rescue
      error ->
        Logger.error("Importer startup reconciliation failed: #{Exception.message(error)}")
        {:error, error}
    end
  end

  defp reconcile_executing_jobs(repo, recovery_opts) do
    jobs =
      repo.all(
        from(job in Oban.Job,
          where: job.worker == @worker and job.state == "executing",
          order_by: [asc: job.id]
        )
      )

    Enum.reduce_while(jobs, :ok, fn job, :ok ->
      with :ok <- recover_or_warn(job, recovery_opts),
           :ok <- cancel_stale_job(repo, job.id) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reconcile_remaining_videos(videos, repo, recovery_opts) do
    Enum.reduce_while(videos, :ok, fn video, :ok ->
      job =
        if is_integer(video.import_job_id), do: repo.get(Oban.Job, video.import_job_id), else: nil

      case job do
        %Oban.Job{state: state} when state in @pending_states ->
          {:cont, :ok}

        %Oban.Job{state: "executing", id: job_id} = job ->
          with :ok <- recover_or_warn(job, recovery_opts),
               :ok <- cancel_stale_job(repo, job_id) do
            {:cont, :ok}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        %Oban.Job{} = job ->
          case recover_or_warn(job, recovery_opts) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        nil ->
          case Recovery.recover_importing(video, recovery_opts) do
            {:ok, _failed_video} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp recover_or_warn(%Oban.Job{} = job, recovery_opts) do
    case Recovery.recover_job_id(job.id, recovery_opts) do
      {:ok, _failed_video} ->
        :ok

      {:error, :not_found} ->
        warn_if_downloaded(job, recovery_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp warn_if_downloaded(%Oban.Job{args: %{"video_id" => video_id}}, recovery_opts)
       when is_integer(video_id) do
    content = Keyword.fetch!(recovery_opts, :content)

    case content.get_video(video_id) do
      {:ok, %Video{} = video} ->
        Recovery.broadcast_downloaded_warning(video, recovery_opts)
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp warn_if_downloaded(_job, _recovery_opts), do: :ok

  defp cancel_stale_job(repo, job_id) do
    {count, _result} =
      repo.update_all(
        from(job in Oban.Job, where: job.id == ^job_id and job.state == "executing"),
        set: [state: "cancelled", cancelled_at: DateTime.utc_now()]
      )

    if count in [0, 1], do: :ok, else: {:error, {:unexpected_cancel_count, count}}
  end

  defp recovery_opts(opts, content) do
    [
      content: content,
      imports: Keyword.get(opts, :imports, Ytdarr.Imports),
      video_import: Keyword.get(opts, :video_import, Ytdarr.Media.VideoImport),
      reason: :import_failed
    ]
  end
end
