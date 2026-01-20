defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.

  The logical flow for this is pulling video details, any custom
  yt-dlp settings and parameters saved, generating the target
  file path, and invoking the download process.
  """

  use Oban.Worker, queue: :video_downloader

  alias Ytdarr.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => vid, "channel_id" => cid}}) do
    # Retrieve video details and settings
    video = Content.get_video!(vid)
    channel = Content.get_channel!(cid)

    # ytdlp_params = retrieve_ytdlp_parameters()

    # Get the current episode count for the year so we can number the episode.
    # The episode should already have a record in the database, so we need to determine
    # what the episode number is based on existing records for that channel and year.
    year = Integer.to_string(video.upload_date.year)
    episode_number = calculate_episode_number(channel, video.upload_date.year, video)

    ytdlp_params = [
      "--embed-chapters",
      "--embed-thumbnails",
      "--embed-subs",
      "--write-auto-subs",
      "--merge-output-format mp4",
      "--mtime"
    ]

    ytdlp_out = "#{sanitize_filename(channel.name)} - S#{video.upload_date.year}E#{episode_number |> Integer.to_string() |> String.pad_leading(3, "0")} - #{sanitize_filename(video.title)}.mp4"

    # trigger yt-dlp to the target URL and out to the correct output file
    {_, status} = System.cmd("yt-dlp", [video.url | ytdlp_params ++ ["-o", ytdlp_out]])

    case status do
      0 -> :ok
      _ -> {:error, :download_failed}
    end
    #   end
  end

  def generate_output_filename() do
  end

  def retrieve_ytdlp_parameters() do
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\?%*:|"<>]/, "_")
    |> String.trim()
  end
end
