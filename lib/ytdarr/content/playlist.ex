defmodule Ytdarr.Content.Playlist do
  use Ecto.Schema
  import Ecto.Changeset

  schema "playlists" do
    field :name, :string
    field :external_id, :string # YouTube playlist id, etc.
    field :url, :string
    field :description, :string
    field :video_count, :integer # number of videos in the playlist

    # Monitoring
    field :is_monitored, :boolean, default: false
    field :is_monitored_since, :utc_datetime
    field :last_checked_at, :utc_datetime

    # filesytem stuff
    field :download_path, :string # channel base path + "/playlist_name"

    # relationships
    belongs_to :channel, Ytdarr.Content.Channel
    many_to_many :videos, Ytdarr.Content.Video,
      join_through: "playlist_videos",
      join_keys: [playlist_id: :id, video_id: :id]

    timestamps()
  end

  @doc false
  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [
      :name,
      :external_id,
      :url,
      :description,
      :video_count,
      :is_monitored,
      :last_checked_at,
      :channel_id
    ])
    |> validate_required([:name, :external_id, :url, :channel_id])
    |> unique_constraint(:external_id)
    |> assoc_constraint(:channel)
    |> maybe_set_download_path()
    |> maybe_set_monitored_timestamp()
  end

  defp maybe_set_download_path(changeset) do
    case {get_field(changeset, :channel), get_change(changeset, :name)} do
      {%{base_path: base_path}, name} when not is_nil(name) ->
        sanitized_name = sanitize_filename(name)
        download_path = Path.join([base_path, sanitized_name])
        put_change(changeset, :download_path, download_path)
      _ -> changeset
    end
  end

  defp maybe_set_monitored_timestamp(changeset) do
    case get_change(changeset, :is_monitored) do
      true -> put_change(changeset, :is_monitored_since, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end
