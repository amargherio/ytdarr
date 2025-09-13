defmodule Ytdarr.Content do
  @moduledoc """
  The Content context handles channels, videos, and playlists.
  """

  import Ecto.Query
  alias Ytdarr.Repo
  alias Ytdarr.Content.{Channel, Video, Playlist}

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
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  def monitor_channel(%Channel{} = channel) do
    channel
    |> Channel.changeset(%{is_monitored: true, is_monitored_since: DateTime.utc_now()})

    case Repo.update(channel) do
      {:ok, updated_channel} -> pull_channel_data_after_channel_monitor(updated_channel)
      {:error, change} -> {:error, change}
    end
  end

  def unmonitor_channel(%Channel{} = channel) do
    channel
    |> Channel.changeset(%{is_monitored: false, is_monitored_since: nil})
    |> Repo.update()
  end

  ## Playlists
  def list_playlists_for_channel(channel_id) do
    Playlist
    |> where([p], p.channel_id == ^channel_id)
    |> Repo.all()
  end

  def list_playlists do
    Repo.all(Playlist)
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
    playlist
    |> Playlist.changeset(%{is_monitored: true, is_monitored_since: DateTime.utc_now()})
    |> Repo.update()
  end

  def unmonitor_playlist(%Playlist{} = playlist) do
    playlist
    |> Playlist.changeset(%{is_monitored: false, is_monitored_since: nil})
    |> Repo.update()
  end

  ## Videos
  def list_videos_for_channel(channel_id) do
    Video
    |> where([v], v.channel_id == ^channel_id)
    |> order_by([v], desc: v.upload_date)
    |> Repo.all()
  end

  ## Complex operations
  def queue_playlist_download(playlist_id) do
    playlist = get_playlist_with_videos(playlist_id)
    #TODO:  queue all videos in the playlist for download - integration point with Oban workers
    {:ok, playlist}
  end

  def sync_channel_content(channel_id) do
    # Fetch latest content from external API (e.g., YouTube)
    # Update/create videos and playlists in the database
    #
    # Start with playlists, ignoring the "uploads" playlist because it has all videos in it
    playlists = Client.get_channel_playlists(channel_id)

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
        Phoenix.Logger.info("Playlist #{pl.id} is already monitored, skipping")
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
            is_monitored: false
          })
          |> Repo.insert()
        else
          # log that this video is already monitored and skip
          Phoenix.Logger.info("Video #{vid.id} is already monitored, skipping")
        end
      end)
    end

    {:ok, :synced}
  end
end
