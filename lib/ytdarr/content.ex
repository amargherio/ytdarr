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

  def list_monitored_channels do
    Repo.all(from c in Channel, where: c.is_monitored == true)
  end

  def get_channel!(id), do: Repo.get!(Channel, id)

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
    |> Repo.update()
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

  def get_playlist_with_videos(id) do
    Playlist
    |> where([p], p.id == ^id)
    |> preload([:videos, :channel])
    |> Repo.one()
  end

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


end
