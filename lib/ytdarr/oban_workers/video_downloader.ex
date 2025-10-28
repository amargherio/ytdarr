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
    #ytdlp_params = retrieve_ytdlp_parameters()
    ytdlp_params = [
      "--embed-chapters",
      "--embed-thumbnails",
      "--embed-subs",
      "--write-auto-subs",
      "--merge-output-format mp4",
      "--mtime"
    ]

    ytdlp_out = "#{channel.base_path}/%(title)s.%(ext)s"


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

  def generate_output_filename() do
  end

  def retrieve_ytdlp_parameters() do

  end
end
