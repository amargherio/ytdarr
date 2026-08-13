defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.
  """

  use Oban.Worker,
    queue: :video_downloader,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:video_id],
      states: :incomplete
    ]

  alias Ytdarr.{Content, MediaPermissions}
  alias Ytdarr.Downloads
  alias Ytdarr.Downloads.{Tracker, YtdlpProgressParser}
  alias Ytdarr.Media.VideoArtifacts

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => video_id, "channel_id" => channel_id}} = job) do
    with {:ok, video} <- Content.get_video(video_id),
         {:ok, channel} <- Content.get_channel(channel_id),
         {:ok, destination} <- VideoArtifacts.build_destination(channel, video, ".mp4") do
      start_and_download(job, video_id, channel, video, destination)
    else
      {:error, reason} -> cancel_download(reason)
    end
  end

  defp start_and_download(job, video_id, channel, video, destination) do
    case Content.start_video_download(video) do
      {:ok, downloading_video} ->
        prepare_and_download(job, video_id, channel, downloading_video, destination)

      {:error, reason} ->
        cancel_download(reason)
    end
  end

  defp prepare_and_download(job, video_id, channel, video, destination) do
    with {:ok, policy} <- MediaPermissions.load_policy(),
         :ok <- MediaPermissions.mkdir_p(destination.season_directory, policy) do
      download(job, video_id, channel, video, destination)
    else
      {:error, reason} -> fail_download(job, video_id, reason)
    end
  end

  defp download(job, video_id, channel, video, destination) do
    ytdlp_params = retrieve_ytdlp_parameters()
    Logger.info("Full yt-dlp parameters: #{inspect(ytdlp_params)}")

    progress_flags = [
      "--newline",
      "--no-color",
      "--progress-template",
      "download:%(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s"
    ]

    Tracker.track_start(job.id, video_id)

    Downloads.broadcast(
      {:download_started, job.id, video_id, %{title: video.title, channel_name: channel.name}}
    )

    try do
      case run_ytdlp(
             job,
             video_id,
             video.url,
             ytdlp_params,
             progress_flags,
             destination.media_path
           ) do
        {:ok, 0} ->
          case finalize_download(video, destination) do
            :ok ->
              Downloads.broadcast({:download_completed, job.id, video_id})
              :ok

            {:error, reason} ->
              fail_download(job, video_id, reason)
          end

        {:ok, status} ->
          Logger.error("yt-dlp failed with status: #{status}")
          fail_download(job, video_id, :download_failed)

        {:error, reason} ->
          fail_download(job, video_id, reason)
      end
    after
      Tracker.track_complete(job.id, video_id)
    end
  end

  defp run_ytdlp(job, video_id, url, ytdlp_params, progress_flags, output_path) do
    case System.find_executable("yt-dlp") do
      nil ->
        {:error, :ytdlp_unavailable}

      ytdlp_path ->
        run_ytdlp_port(
          ytdlp_path,
          [url | ytdlp_params ++ progress_flags ++ ["-o", output_path]],
          job.id,
          video_id
        )
    end
  end

  defp run_ytdlp_port(ytdlp_path, args, job_id, video_id) do
    port =
      Port.open({:spawn_executable, ytdlp_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    try do
      {output, status} = stream_port_output(port, job_id, video_id, [])
      Logger.info("yt-dlp output: #{output}")
      {:ok, status}
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    ArgumentError -> {:error, :ytdlp_unavailable}
  end

  defp finalize_download(video, destination) do
    with {:ok, policy} <- MediaPermissions.load_policy(),
         :ok <-
           VideoArtifacts.write_nfo(
             destination.nfo_path,
             video,
             destination.episode_number,
             policy
           ),
         {:ok, _artifact_count} <-
           MediaPermissions.apply_download_artifacts(destination.media_path, policy),
         {:ok, %{size: size}} <- File.stat(destination.media_path),
         {:ok, _video} <-
           Content.mark_video_downloaded(video, %{
             download_path: destination.media_path,
             file_size: size,
             download_quality: nil
           }) do
      :ok
    end
  end

  defp fail_download(job, video_id, reason) do
    Logger.error("Video download failed for #{video_id}: #{inspect(reason)}")
    Downloads.broadcast({:download_failed, job.id, video_id, reason})
    {:error, reason}
  end

  defp cancel_download(reason) do
    Logger.warning("Cancelling video download before execution: #{inspect(reason)}")
    {:cancel, reason}
  end

  defp stream_port_output(port, job_id, video_id, output_acc) do
    receive do
      {^port, {:data, data}} ->
        data
        |> String.split("\n", trim: true)
        |> Enum.each(fn line ->
          case YtdlpProgressParser.parse_line(line) do
            {:progress, progress_data} -> Tracker.update_progress(job_id, video_id, progress_data)
            _ -> :ok
          end
        end)

        stream_port_output(port, job_id, video_id, [data | output_acc])

      {^port, {:exit_status, status}} ->
        {output_acc |> Enum.reverse() |> IO.iodata_to_binary(), status}
    end
  end

  @default_ytdlp_params [
    "--embed-chapters",
    "--embed-thumbnail",
    "--embed-metadata",
    "--embed-subs",
    "--write-auto-subs",
    "--merge-output-format",
    "mp4",
    "--mtime"
  ]

  def retrieve_ytdlp_parameters do
    case Ytdarr.Settings.get_default_yt_dlp_param_set() do
      {:ok, %{extra_args: extra_args, format: format}} ->
        base = @default_ytdlp_params

        base =
          if is_binary(format) and format != "" do
            base ++ ["-f", format]
          else
            base
          end

        if is_binary(extra_args) and extra_args != "" do
          base ++ String.split(extra_args)
        else
          base
        end

      _ ->
        @default_ytdlp_params
    end
  end
end
