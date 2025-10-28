defmodule Ytdarr.ObanWorkers.JellyfinCollectionCreator do
  use Oban.Worker, queue: :jellyfin_collections

  alias Ytdarr.Services.Jellyfin.Client
  alias Ytdarr.Services.Jellyfin.Models
  alias Ytdarr.Services.Jellyfin.Parser
  alias Ytdarr.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"playlist_id" => playlist_id}}) do
    # grab playlist details from DB
    playlist = Content.get_playlist!(playlist_id)

    # for each video in the playlist, see if it's downloaded. if it isn't,
    # queue the item for download (using existing video downloader worker)
    # and wait for all queued downloads to finish before proceeding
    for video <- playlist.videos do
      if !video.is_downloaded do
        Oban.insert(%Oban.Job{
          worker: Ytdarr.ObanWorkers.VideoDownloader,
          args: %{"video_id" => video.id, "channel_id" => playlist.channel_id}
        })
      end
    end

    # once all of the videos are downloaded, build a list of item ids from jellyfin
    # so we can create the collection
    downloaded_items = []
    for video <- playlist.videos do
      downloaded_items = [downloaded_items | Client.get_item_id(%{file_path: video.download_path})]
    end

    # Now that we have a list of item ids, create the collection in Jellyfin
    Client.create_collection(playlist.name, downloaded_items)

    {:ok, :created}
  end
end
