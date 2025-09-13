defmodule Ytdarr.ObanWorkers.VideoDownloader do
  @moduledoc """
  Oban worker for downloading videos using youtube-dl or yt-dlp.
  """

  use Oban.Worker, queue: :video_downloader

  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.Content.{Playlist, Video}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"video_url" => video_url}}) do
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
end
