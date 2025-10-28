defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.

  The logical flow for this is pulling video details, any custom
  yt-dlp settings and parameters saved, generating the target
  file path, and invoking the download process.
  """

  use Oban.Worker, queue: :video_downloader

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

    ytdlp_out = "%(title)s.%(ext)s"



    # trigger yt-dlp to the target URL and out to the correct output file
    System.cmd("yt-dlp", [video.url | ytdlp_params ++ ["-o", ytdlp_out]])


    case Client.download_video(video_url) do
      {:ok, file_path} ->
        # Handle successful download (e.g., move file, update DB, etc.)
        IO.puts("Video downloaded successfully: #{file_path}")
        :ok

      {:error, reason} ->
        # Handle download failure
        IO.puts("Failed to download video: #{reason}")
        {:error, reason}
    end
  end

  def generate_output_filename() do
  end

  def retrieve_ytdlp_parameters() do

  end
end
