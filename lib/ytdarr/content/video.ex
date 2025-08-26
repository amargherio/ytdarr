defmodule Ytdarr.Content.Video do
  use Ecto.Schema
  import Ecto.Changeset

  schema "videos" do
    field :title, :string
    field :external_id, :string # YouTube video id, etc.
    field :url, :string
    field :description, :string
    field :duration, :integer # in seconds
    field :upload_date, :date
    field :thumbnail_url, :string

    # Download tracking
    field :is_downloaded, :boolean, default: false
    field :downloaded_at, :utc_datetime
    field :download_path, :string # "/downloads/channels/channel_name/videos/video_id.mp4"
    field :file_size, :integer # in bytes
    field :download_quality, :string # e.g., "1080p", "720p"

    # Relationships
    belongs_to :channel, Ytdarr.Content.Channel
    many_to_many :playlists, Ytdarr.Content.Playlist, join_through: "playlists_videos", join_keys: [video_id: :id, playlist_id: :id]

    timestamps()
  end

  @doc false
  def changeset(video, attrs) do
    video
    |> cast(attrs, [:title, :external_id, :url, :description, :duration,
                    :upload_date, :thumbnail_url, :is_downloaded,
                    :downloaded_at, :download_path, :file_size,
                    :download_quality, :channel_id])
    |> validate_required([:title, :external_id, :url, :channel_id])
    |> unique_constraint(:external_id)
    |> assoc_constraint(:channel)
    |> maybe_set_downloaded_timestamp()
  end

  defp maybe_set_downloaded_timestamp(changeset) do
    case get_change(changeset, :is_downloaded) do
      true -> put_change(changeset, :downloaded_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
