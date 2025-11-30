defmodule Ytdarr.Content do
  @moduledoc """
  The Content context handles channels, videos, and playlists.
  """

  import Ecto.Query
  alias Ytdarr.Repo
  alias Ytdarr.Content.{Channel, Video, Playlist}
  alias Ytdarr.Services.YouTube.Client

  require Logger

  import Path

  ## Channels
  def list_channels do
    Repo.all(Channel)
  end

  @doc """
  Search channels by case-insensitive partial match on name or external_id.
  Returns all channels when the query is blank or nil.
  """
  def list_channels_search(query) when query in [nil, ""], do: list_channels()

  def list_channels_search(query) do
    like = "%#{query}%"

    Channel
    |> where([c], ilike(c.name, ^like) or ilike(c.external_id, ^like))
    |> Repo.all()
  end

  def list_monitored_channels do
    Repo.all(from c in Channel, where: c.is_monitored == true)
  end

  @doc """
  Returns a page of monitored channels ordered by name.

  Options:
    * :page - 1-based page number (default 1)
    * :page_size - items per page (default 20)
    * :preload - list of associations to preload (default [])
  """
  def list_monitored_channels_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    preload_assocs = Keyword.get(opts, :preload, [])

    query =
      Channel
      |> where([c], c.is_monitored == true)
      |> order_by([c], asc: c.name)
      |> limit(^page_size)
      |> offset(^((max(page, 1) - 1) * page_size))

    query
    |> Repo.all()
    |> Repo.preload(preload_assocs)
  end

  @doc """
  Returns a page of monitored channels filtered by a search query (case-insensitive).

  When query is blank, falls back to `list_monitored_channels_paginated/1`.
  """
  def search_monitored_channels_paginated(query_string, opts \\ [])

  def search_monitored_channels_paginated(query_string, opts) when query_string in [nil, ""] do
    list_monitored_channels_paginated(opts)
  end

  def search_monitored_channels_paginated(query_string, opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    preload_assocs = Keyword.get(opts, :preload, [])
    like = "%#{query_string}%"

    query =
      Channel
      |> where([c], c.is_monitored == true)
      |> where([c], ilike(c.name, ^like) or ilike(c.external_id, ^like))
      |> order_by([c], asc: c.name)
      |> limit(^page_size)
      |> offset(^((max(page, 1) - 1) * page_size))

    query
    |> Repo.all()
    |> Repo.preload(preload_assocs)
  end

  def get_channel!(id), do: Repo.get!(Channel, id)
  def get_channel_by_external_id(ext_id), do: Repo.get_by(Channel, external_id: ext_id)

  def get_channel_with_videos(id) do
    Channel
    |> where([c], c.id == ^id)
    |> preload([:videos, :playlists])
    |> Repo.one()
  end

  def create_channel(attrs \\ %{}) do
    case Client.get_channel(attrs["external_id"]) do
      {:ok, channel} ->
        # flip the is_monitored flag to true and persist
        monitored = Channel.changeset(channel, %{is_monitored: true})

        case Repo.insert(monitored) do
          {:ok, chan} ->
            case File.mkdir_p!(chan.base_path) do
              {:ok} ->
                Logger.info("Created channel base path #{chan.base_path}")
              {:error, reason} ->
                Logger.error("Failed to create channel base path #{chan.base_path}: #{reason}")
            end

            sync_channel_content(chan.external_id)

            {:ok, chan}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end

    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    Channel.changeset(channel, attrs)
  end

  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update()
  end

  def monitor_channel(%Channel{} = channel) do
    case channel
         |> Channel.changeset(%{is_monitored: true})
         |> Repo.update(channel) do
      #{:ok, updated_channel} -> sync_channel_content(updated_channel.external_id)
      {:ok, updated_channel} -> Oban.insert(%Oban.Job{
        worker: Ytdarr.ObanWorkers.SyncWorker,
        args: %{"source_type" => "channel", "source_id" => updated_channel.id}
      })
      {:error, change} -> {:error, change}
    end
  end

  def unmonitor_channel(%Channel{} = channel) do
    channel
    |> Channel.changeset(%{is_monitored: false})
    |> Repo.update()
  end

  def toggle_channel_monitor_status(id) do
    channel = get_channel!(id)

    case channel
    |> Channel.changeset(%{is_monitored: not channel.is_monitored})
    |> Repo.update() do
      {:ok, updated_channel} ->
        if updated_channel.is_monitored do
          Oban.insert(%Oban.Job{
            worker: Ytdarr.ObanWorkers.SyncWorker,
            args: %{"source_type" => "channel", "source_id" => updated_channel.id}
          })
        end
      {:error, change} -> {:error, change}
    end
  end

  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  end

  ## Playlists
  def get_playlist!(id), do: Repo.get!(Playlist, id)

  def list_playlists_for_channel(channel_id) do
    Playlist
    |> where([p], p.channel_id == ^channel_id)
    |> Repo.all()
  end

  def get_playlist_with_videos(id) do
    Playlist
    |> where([p], p.id == ^id)
    |> preload([:videos, :channel])
    |> Repo.one()
  end

  def get_playlist_by_external_id(ext_id), do: Repo.get_by(Playlist, external_id: ext_id)

  def create_playlist(attrs \\ %{}) do
    %Playlist{}
    |> Playlist.changeset(attrs)
    |> Repo.insert()
  end

  def monitor_playlist(%Playlist{} = playlist) do
    case playlist
         |> Playlist.changeset(%{is_monitored: true, is_monitored_since: DateTime.utc_now()})
         |> Repo.update() do
      {:ok, updated_playlist} -> Oban.insert(%Oban.Job{
        worker: Ytdarr.ObanWorkers.SyncWorker,
        args: %{"source_type" => "playlist", "source_id" => updated_playlist.id}
      })
      {:error, change} -> {:error, change}
    end
  end

  @doc """
  Stop monitoring a playlist.
  """
  def unmonitor_playlist(%Playlist{} = playlist) do
    playlist
    |> Playlist.changeset(%{is_monitored: false, is_monitored_since: nil})
    |> Repo.update()
  end

  @doc """
  Toggle the monitored status of a playlist by its internal ID.
  """
  def toggle_playlist_monitor_status(id) do
    playlist = Playlist
      |> where([p], p.id == ^id)
      |> preload([:channel, :videos])
      |> Repo.one()

    case playlist
    |> Playlist.changeset(%{is_monitored: not playlist.is_monitored})
    |> Repo.update() do
      {:ok, updated_playlist} ->
        if updated_playlist.is_monitored do
          Oban.insert(%Oban.Job{
            worker: Ytdarr.ObanWorkers.SyncWorker,
            args: %{"source_type" => "playlist", "source_id" => updated_playlist.id}
          })
        end
      {:error, change} -> {:error, change}
    end
  end

  ## Videos

  @doc """
  List all videos for a given channel, ordered by upload date descending.

  ## Parameters
    - channel_id: Internal ID of the channel
  """
  def list_videos_for_channel(channel_id) do
    Video
    |> where([v], v.channel_id == ^channel_id)
    |> order_by([v], desc: v.upload_date)
    |> Repo.all()
  end

  ## Complex operations

  @doc """
  For a given video, queue it for download via Oban. Validate the target directory structure
  exists, creating as needed. Update the video record with the target
  download path since it isn't going to change after this point.

  Then...push an Oban job to download the video.

  ## Parameters
    - video_id: Internal ID of the video to queue for download
  """
  def queue_video_download(video_id) do
    vid = Repo.get!(Video, video_id) |> Repo.preload(:channel)
    channel_id = vid.channel.id

    # Work through the directory structure creation flow
    if !File.exists?(channel.base_path) do
      case File.mkdir_p!(channel.base_path) do
        {:ok} -> :ok
        {:error, reason} ->
          Logger.error("Failed to create channel base path #{channel.base_path}: #{reason}")
      end
    end

    # The channel path exists, so let's do the video-specific path
    year = video.published_at |> DateTime.to_date() |> Date.to_iso8601() |> String.slice(0, 4)
    dest_path = Path.join([channel.base_path, "Season" ++ year])
    if !File.exists?(dest_path) do
      case File.mkdir_p!(dest_path) do
        {:ok} -> vid |> Video.changeset(%{download_path: dest_path}) |> Repo.update()
        {:error, reason} ->
          Logger.error("Failed to create video destination path #{dest_path}: #{reason}")
      end
    end

    %Oban.Job{
      worker: Ytdarr.ObanWorkers.VideoDownloader,
      args: %{"video_id" => video_id, "channel_id" => channel_id}
    }
    |> Oban.insert()
  end


  @doc """
  For a given playlist, iterate through all playlist items and queue each video for download.

  ## Parameters
    - playlist_id: Internal ID of the playlist to queue downloads for
  """
  def queue_playlist_download(playlist_id) do
    playlist = get_playlist_with_videos(playlist_id)
    # TODO:  queue all videos in the playlist for download - integration point with Oban workers
    {:ok, playlist}
  end

  @doc"""
  Sync channel or playlist content with the latest from the source, persisting new videos/playlists as needed.

  ## Parameters
    - target_type: "channel" or "playlist"
    - target_id: Internal ID of the channel or playlist to sync
  """
  def sync_content(target_type, target_id) do
    case target_type do
      "channel" ->
        Oban.insert(%Oban.Job{
          worker: Ytdarr.ObanWorkers.SyncWorker,
          args: %{"source_type" => "channel", "source_id" => target_id}
        })

      "playlist" ->
        Oban.insert(%Oban.Job{
          worker: Ytdarr.ObanWorkers.SyncWorker,
          args: %{"source_type" => "playlist", "source_id" => target_id}
        })

      _ ->
        {:error, :unknown_target_type}
    end
  end

  @doc """
  Syncs playlists for a channel, creating any new playlists as needed

  ## Parameters
    - channel: The Ytdarr.Content.Channel struct to sync playlists for
  """
  def sync_channel_playlists(%Channel{} = channel) do
    playlists = Client.get_channel_playlists(channel.external_id)

    Enum.each(playlists, fn pl ->
      existing_pl = get_playlist_by_external_id(pl.id)

      if is_nil(existing_pl) do
        # not already monitored, so create a Ytdarr.Content.Playlist struct and
        # add it to the DB
        %Playlist{}
        |> Playlist.changeset(%{
          external_id: pl.id,
          title: pl.title,
          description: pl.description,
          url: pl.url,
          thumbnail_url: pl.thumbnail_url,
          video_count: pl.video_count,
          channel_id: pl.channel_id,
          is_monitored: false
        })
        |> Repo.insert()
      else
        # log that this playlist is already monitored and skip
        Logger.info("Playlist #{pl.id} is already monitored, skipping")
      end
    end)

    {:ok, :synced}
  end

  @doc """
  Fetch latest content from external API (e.g., YouTube). Update/create videos and playlists in the database

  Start with playlists, ignoring the "uploads" playlist because it has all videos in it

  ## Parameters
    - channel_id: The external ID of the channel to sync
  """
  def sync_channel_content(channel_id) do
    playlists = Client.get_channel_playlists(channel_id)
    uploads_playlist = Enum.find(playlists, fn pl -> pl.title == "Uploads" end)

    Enum.each(playlists, fn pl ->
      existing_pl = get_playlist_by_external_id(pl.id)

      if is_nil(existing_pl) do
        # not already monitored, so create a Ytdarr.Content.Playlist struct and
        # add it to the DB
        %Playlist{}
        |> Playlist.changeset(%{
          external_id: pl.id,
          title: pl.title,
          description: pl.description,
          url: pl.url,
          thumbnail_url: pl.thumbnail_url,
          video_count: pl.video_count,
          channel_id: pl.channel_id,
          is_monitored: false
        })
        |> Repo.insert()
      else
        # log that this playlist is already monitored and skip
        Logger.info("Playlist #{pl.id} is already monitored, skipping")
      end
    end)

    # Now handle videos by pulling from the "uploads" playlist
    uploads_playlist = Enum.find(playlists, fn pl -> pl.title == "Uploads" end)

    if uploads_playlist do
      videos = Client.get_playlist_videos(uploads_playlist.id)

      Enum.each(videos, fn vid ->
        existing_vid = Repo.get_by(Video, external_id: vid.id)

        if is_nil(existing_vid) do
          # not already monitored, so create a Ytdarr.Content.Video struct and
          # add it to the DB
          %Video{}
          |> Video.changeset(%{
            external_id: vid.id,
            title: vid.title,
            description: vid.description,
            url: vid.url,
            thumbnail_url: vid.thumbnail_url,
            published_at: vid.published_at,
            duration: vid.duration,
            view_count: vid.view_count,
            channel_id: vid.channel_id,
          })
          |> Repo.insert()
        else
          # log that this video is already monitored and skip
          Logger.info("Video #{vid.id} is already monitored, skipping")
        end
      end)
    end

    {:ok, :synced}
  end

  @doc """
  Syncs uploads playlist for a channel, creating videos as needed
  """
  def sync_channel_uploads(%Channel{} = channel) do
  end

  @doc"""
  Associate playlists and videos

  ## Parameters
    - playlist_id: Internal ID of the playlist to associate videos for
  """
  def associate_playlists_and_videos(playlist_id) do
    playlist = Repo.get(Playlist, playlist_id)
    videos = Client.get_playlist_videos(playlist.external_id)

    # For each video, query if it's in the DB. If it is, verify the association exists, if not create it
    Enum.each(videos, fn vid ->
      existing_vid = Repo.get_by(Video, external_id: vid.id)

      if existing_vid do
        # Check if association exists
        assoc_exists = Repo.exists?(
          from pv in "playlist_videos",
          where: pv.playlist_id == ^playlist.id and pv.video_id == ^existing_vid.id
        )

        unless assoc_exists do
          # Create association
          Repo.insert_all("playlist_videos", [%{playlist_id: playlist.id, video_id: existing_vid.id}])
        end
      end
    end)

    {:ok, :associated}
  end

  def create_jellyfin_collection_from_playlist(playlist_id) do
    Oban.insert(%Oban.Job{
      worker: Ytdarr.ObanWorkers.JellyfinCollectionCreator,
      args: %{"playlist_id" => playlist_id}
    })
  end
end
