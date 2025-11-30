defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.

  The logical flow for this is pulling video details, any custom
  yt-dlp settings and parameters saved, generating the target
  file path, and invoking the download process.
  """

  use Oban.Worker, queue: :video_downloader

  require Logger
  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.Content.{Channel, Playlist, Video}
  alias Ytdarr.{Content, Settings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => vid, "channel_id" => cid}}) do
    # Retrieve video details and settings
    video = Content.get_video!(vid)
    channel = Content.get_channel!(cid)

    # Get the current episode count for the year so we can number the episode.
    # The episode should already have a record in the database, so we need to determine
    # what the episode number is based on existing records for that channel and year.
    year = Integer.to_string(video.upload_date.year)
    episode_number = calculate_episode_number(channel, video.upload_date.year, video)



    #ytdlp_params = retrieve_ytdlp_parameters()
    ytdlp_params = [
      "--embed-chapters",
      "--embed-thumbnails",
      "--embed-subs",
      "--write-auto-subs",
      "--merge-output-format mp4",
      "--mtime"
    ]

    #ytdlp_out = "#{channel.name} - S#{video.upload_date.year}E11111 - #{video.title}.mp4"
    ytdlp_out = "#{sanitize_filename(channel.name)} - S#{video.upload_date.year}E#{episode_number |> Integer.to_string() |> String.pad_leading(3, "0")} - #{sanitize_filename(video.title)}.mp4"

    # trigger yt-dlp to the target URL and out to the correct output file
    {output, exit_status} = System.cmd("yt-dlp", [video.url | ytdlp_params ++ ["-o", ytdlp_out]])
    if exit_status != 0 do
      Logger.warn("yt-dlp failed with status #{exit_status}: #{output}")
      {:error, :download_failed}
    end

    Logger.info("Video downloaded successfully to #{ytdlp_out}. Updating video details in database")
    Content.update_video(vid, %{
      is_downloaded: true,
      download_path: ytdlp_out
    })
    :ok
  end

  def calculate_episode_number(%Channel{} = channel, year, %Video{} = video) do
    previous_count =
      from(v in Video,
        where: v.channel_id == ^video.channel_id,
        where: fragment("strftime('%Y', ?)", v.upload_date) == ^Integer.to_string(year),
        where:
          v.uploade_date < ^video.upload_date or
            (v.upload_date == ^video.upload_date and v.id < ^video.id),
        select: count(v.id)
        )
      |> Ytdarr.Repo.one()

      previous_count + 1
  end

  def generate_output_filename(channel, video) do
  end

  def retrieve_ytdlp_parameters() do

  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\?%*:|"<>]/, "_")
    |> String.trim()
  end
end
