defmodule Ytdarr.Content.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :external_id, :string # YouTube channel id, etc.
    field :url, :string
    field :description, :string
    field :platform, :string # e.g., "YouTube", "Twitch"
    field :avatar_url, :string

    # monitoring status
    field :is_monitored, :boolean, default: true
    field :is_monitored_since, :utc_datetime
    field :last_checked_at, :utc_datetime

    # filesystem stuff
    field :base_path, :string # "/downloads/channels/channel_name"
    field :generic_video_path, :string # "/downloads/channels/channel_name/videos"

    # relationships
    has_many :videos, Ytdarr.Content.Video
    has_many :playlists, Ytdarr.Content.Playlist
    has_many :playlist_videos, through: [:playlists, :videos]

    timestamps()
  end

  @doc false
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :external_id, :url, :description, :platform,
                    :avatar_url, :watched, :watched_since, :base_path, :videos_path])
    |> validate_required([:name, :external_id, :url, :platform])
    |> unique_constraint(:external_id)
    |> validate_url(:url)
    |> maybe_set_filesystem_paths()
    |> maybe_set_watched_timestamp()
  end

  defp maybe_set_filesystem_paths(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name ->
        sanitized_name = sanitize_filename(name)
        base_path = Path.join(["/downloads/channels", sanitized_name])
        videos_path = Path.join([base_path, "videos"])

        changeset
        |> put_change(:base_path, base_path)
        |> put_change(:videos_path, videos_path)
    end
  end

  defp maybe_set_watched_timestamp(changeset) do
    case get_change(changeset, :is_monitored) do
      true -> put_change(changeset, :is_monitored_since, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: nil} -> [{field, "must have a scheme (http or https)"}]
        %URI{host: nil} -> [{field, "must have a host"}]
        %URI{scheme: scheme} when scheme in ["http", "https"] -> []
        _ -> [{field, "must be a valid http or https URL"}]
      end
    end)
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end
