defmodule Ytdarr.Imports.Recovery do
  @moduledoc false

  alias Ytdarr.Content.Video
  alias Ytdarr.Imports.SafeMessage
  alias Ytdarr.Media.VideoImport

  @empty_recovery %{"mode" => nil, "entries" => []}

  @spec recover_importing(Video.t(), keyword()) :: {:ok, Video.t()} | {:error, term()}
  def recover_importing(video, opts \\ [])

  def recover_importing(%Video{download_state: :importing} = video, opts) do
    content = Keyword.get(opts, :content, Ytdarr.Content)
    imports = Keyword.get(opts, :imports, Ytdarr.Imports)
    video_import = Keyword.get(opts, :video_import, VideoImport)
    reason = Keyword.get(opts, :reason, :import_failed)

    with {:ok, manifest} <- manifest_from_video(video, video_import),
         recovery_result <- video_import.recover(video.import_job_id, manifest, :importing),
         {:ok, recovery} <- recovery_from_result(recovery_result),
         {:ok, failed_video} <-
           content.mark_video_import_failed(video, %{
             import_error: SafeMessage.for(reason),
             import_recovery: recovery
           }) do
      :ok =
        imports.broadcast(
          {:video_import_failed, failed_video.channel_id, failed_video.id,
           failed_video.import_error}
        )

      {:ok, failed_video}
    end
  end

  def recover_importing(_video, _opts), do: {:error, :video_not_importing}

  @spec recover_job_id(integer(), keyword()) :: {:ok, Video.t()} | {:error, term()}
  def recover_job_id(job_id, opts \\ []) when is_integer(job_id) do
    content = Keyword.get(opts, :content, Ytdarr.Content)

    with {:ok, video} <- content.get_importing_video_by_job_id(job_id) do
      recover_importing(video, opts)
    end
  end

  @spec broadcast_downloaded_warning(Video.t(), keyword()) :: :ok
  def broadcast_downloaded_warning(video, opts \\ [])

  def broadcast_downloaded_warning(%Video{download_state: :downloaded} = video, opts) do
    if recovery_entries(video.import_recovery) == [] do
      :ok
    else
      imports = Keyword.get(opts, :imports, Ytdarr.Imports)
      imports.broadcast({:video_import_cleanup_warning, video.channel_id, video.id})
    end
  end

  def broadcast_downloaded_warning(_video, _opts), do: :ok

  @spec recovery_entries(map() | nil) :: [map()]
  def recovery_entries(%{"entries" => entries}) when is_list(entries), do: entries
  def recovery_entries(_recovery), do: []

  defp manifest_from_video(%Video{import_manifest: manifest_map}, video_import)
       when is_map(manifest_map) do
    video_import
    |> Module.concat("Manifest")
    |> apply(:from_map, [manifest_map])
  end

  defp manifest_from_video(_video, _video_import), do: {:error, :invalid_import_manifest}

  defp recovery_from_result({:ok, []}), do: {:ok, @empty_recovery}

  defp recovery_from_result({:error, entries}) when is_list(entries),
    do: {:ok, %{"mode" => "restore", "entries" => entries}}

  defp recovery_from_result({:ok, entries}) when is_list(entries),
    do: {:ok, %{"mode" => "restore", "entries" => entries}}

  defp recovery_from_result(_result), do: {:error, :invalid_recovery_result}
end
