defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using yt-dlp.

  The logical flow for this is pulling video details, any custom
  yt-dlp settings and parameters saved, generating the target
  file path, and invoking the download process.
  """

  use Oban.Worker, queue: :video_downloader

  alias Ytdarr.Content
  alias Ytdarr.Content.{Channel, Video}

  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_id" => vid, "channel_id" => cid}}) do
    # Retrieve video details and settings
    video = Content.get_video!(vid)
    channel = Content.get_channel!(cid)

    # ytdlp_params = retrieve_ytdlp_parameters()

    # Get the current episode count for the year so we can number the episode.
    # The episode should already have a record in the database, so we need to determine
    # what the episode number is based on existing records for that channel and year.
    episode_number = calculate_episode_number(channel, video.upload_date.year, video)

    ytdlp_params = [
      "--embed-chapters",
      "--embed-thumbnails",
      "--embed-subs",
      "--write-auto-subs",
      "--merge-output-format mp4",
      "--mtime"
    ]

    # Check if our season folder exists, create if not
    season_folder = "#{channel.base_path}/Season #{video.upload_date.year}"
    unless File.exists?(season_folder) do
      File.mkdir_p!(season_folder)
    end

    ytdlp_out = "#{season_folder}/#{sanitize_filename(channel.name)} - S#{video.upload_date.year}E#{episode_number |> Integer.to_string() |> String.pad_leading(3, "0")} - #{sanitize_filename(video.title)}.mp4"

    # trigger yt-dlp to the target URL and out to the correct output file
    {_, status} = System.cmd("yt-dlp", [video.url | ytdlp_params ++ ["-o", ytdlp_out]])

    case status do
      0 ->
        generate_nfo_file(channel, video, episode_number, ytdlp_out)
        :ok
      _ -> {:error, :download_failed}
    end
    #   end
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

  def retrieve_ytdlp_parameters() do
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\?%*:|"<>]/, "_")
    |> String.trim()
  end

  defp generate_nfo_file(%Channel{} = _channel, %Video{} = video, episode_number, file_path) do
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
    File.write!(nfo_file_path, nfo_content)
  end
end
