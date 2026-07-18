defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.

  The logical flow for this is pulling video details, any custom
  yt-dlp settings and parameters saved, generating the target
  file path, and invoking the download process.
  """

  use Oban.Worker, queue: :video_downloader

  alias Ytdarr.{Content, MediaPermissions}
  alias Ytdarr.Content.{Channel, Video}
  alias Ytdarr.Downloads
  alias Ytdarr.Downloads.{Tracker, YtdlpProgressParser}
  require Logger

  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => vid, "channel_id" => cid}} = job) do
    # Retrieve video details and settings
    video = Content.get_video!(vid)
    channel = Content.get_channel!(cid)

    # Transition from :queued to :downloading now that the job is executing
    Content.update_video(video, %{download_state: :downloading})

    ytdlp_params = retrieve_ytdlp_parameters()
    Logger.info("Full yt-dlp parameters: #{inspect(ytdlp_params)}")

    # Get the current episode count for the year so we can number the episode.
    episode_number = calculate_episode_number(channel, video.upload_date.year, video)

    # Check if our season folder exists, create if not
    season_folder = "#{channel.base_path}/Season #{video.upload_date.year}"

    policy = load_media_policy!()
    :ok = apply_permissions!(MediaPermissions.mkdir_p(season_folder, policy))

    ytdlp_out =
      "#{season_folder}/#{sanitize_filename(channel.name)} - S#{video.upload_date.year}E#{episode_number |> Integer.to_string() |> String.pad_leading(3, "0")} - #{sanitize_filename(video.title)}.mp4"

    progress_flags = [
      "--newline",
      "--no-color",
      "--progress-template",
      "download:%(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s"
    ]

    # trigger yt-dlp to the target URL and out to the correct output file
    Tracker.track_start(job.id, vid)

    Downloads.broadcast(
      {:download_started, job.id, vid, %{title: video.title, channel_name: channel.name}}
    )

    try do
      ytdlp_path = System.find_executable("yt-dlp") || raise "yt-dlp not found in PATH"

      port =
        Port.open({:spawn_executable, ytdlp_path}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: [video.url | ytdlp_params ++ progress_flags ++ ["-o", ytdlp_out]]
        ])

      try do
        {output, status} = stream_port_output(port, job.id, vid, [])
        Logger.info("yt-dlp output: #{output}")

        case status do
          0 ->
            final_policy = load_media_policy!()
            :ok = generate_nfo_file(channel, video, episode_number, ytdlp_out, final_policy)

            {:ok, _artifact_count} =
              MediaPermissions.apply_download_artifacts(ytdlp_out, final_policy)

            # Update video status in DB
            Content.update_video(video, %{
              download_state: :downloaded,
              download_path: ytdlp_out,
              is_downloaded: true,
              downloaded_at: DateTime.utc_now()
            })

            Downloads.broadcast({:download_completed, job.id, vid})
            :ok

          _ ->
            Logger.error("yt-dlp failed with status: #{status}")
            Downloads.broadcast({:download_failed, job.id, vid, :download_failed})
            {:error, :download_failed}
        end
      after
        if Port.info(port) != nil, do: Port.close(port)
      end
    after
      Tracker.track_complete(job.id, vid)
    end
  end

  defp stream_port_output(port, job_id, video_id, output_acc) do
    receive do
      {^port, {:data, data}} ->
        lines = String.split(data, "\n", trim: true)

        Enum.each(lines, fn line ->
          case YtdlpProgressParser.parse_line(line) do
            {:progress, progress_data} ->
              Tracker.update_progress(job_id, video_id, progress_data)

            _ ->
              :ok
          end
        end)

        stream_port_output(port, job_id, video_id, [output_acc, data])

      {^port, {:exit_status, status}} ->
        {IO.iodata_to_binary(output_acc), status}
    end
  end

  def calculate_episode_number(%Channel{} = _channel, year, %Video{} = video) do
    year_string = Integer.to_string(year)

    # Count videos from the same channel, same year, uploaded before this video
    query =
      Video
      |> Ash.Query.filter(channel_id == ^video.channel_id)
      |> Ash.Query.filter(fragment("strftime('%Y', ?)", upload_date) == ^year_string)
      |> Ash.Query.filter(
        upload_date < ^video.upload_date or
          (upload_date == ^video.upload_date and id < ^video.id)
      )

    case Ash.read(query) do
      {:ok, videos} -> length(videos) + 1
      {:error, _} -> 1
    end
  end

  @default_ytdlp_params [
    # "--postprocessor-args ffmpeg:'-c:a libopus -b:a 128k -c:v libsvtav1 -preset 4 -crf 24 -svtav1-params keyint=10s:tune=0:enable-overlays=1:scd=1:scm=0'",
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

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\?%*:|"<>]/, "_")
    |> String.trim()
  end

  defp generate_nfo_file(
         %Channel{} = _channel,
         %Video{} = video,
         episode_number,
         file_path,
         policy
       ) do
    nfo_content = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <episodedetails>
      <title>#{video.title}</title>
      <season>#{video.upload_date.year}</season>
      <episode>#{episode_number}</episode>
      <plot>#{video.description}</plot>
      <aired>#{Date.to_iso8601(video.upload_date)}</aired>
      <uniqueid type="youtube" default="true">#{video.id}</uniqueid>
      <url>#{video.url}</url>
    </episodedetails>
    """

    nfo_file_path = String.replace_suffix(file_path, ".mp4", ".nfo")
    MediaPermissions.write_file(nfo_file_path, nfo_content, policy)
  end

  defp load_media_policy! do
    case MediaPermissions.load_policy() do
      {:ok, policy} -> policy
      {:error, reason} -> raise MediaPermissions.error_message(reason)
    end
  end

  defp apply_permissions!(:ok), do: :ok

  defp apply_permissions!({:error, reason}) do
    raise MediaPermissions.error_message(reason)
  end
end
