defmodule Ytdarr.Content.Video do
  use Ecto.Schema
  import Ecto.Changeset

  schema "videos" do
    field :title, :string
    # YouTube video id, etc.
    field :external_id, :string
    field :url, :string
    field :description, :string
    # in seconds
    field :duration, :integer
    field :upload_date, :date
    field :thumbnail_url, :string

    # Download tracking
    field :is_downloaded, :boolean, default: false
    field :downloaded_at, :utc_datetime
    # "/downloads/channels/channel_name/videos/video_id.mp4"
    field :download_path, :string
    # in bytes
    field :file_size, :integer
    # e.g., "1080p", "720p"
    field :download_quality, :string

    # discovery tracking
    # "uploads, playlist:PLAYLIST_ID, search, etc
    field :discovered_from, :string
    field :discovered_at, :utc_datetime
    # position when first discovered in the uploads playlist
    field :position_in_uploads, :integer

    # Relationships
    belongs_to :channel, Ytdarr.Content.Channel

    many_to_many :playlists, Ytdarr.Content.Playlist,
      join_through: "playlist_videos",
      join_keys: [video_id: :id, playlist_id: :id]

    timestamps()
  end

  @doc false
  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :title,
      :external_id,
      :url,
      :description,
      :duration,
      :upload_date,
      :thumbnail_url,
      :is_downloaded,
      :downloaded_at,
      :download_path,
      :file_size,
      :download_quality,
      :channel_id,
      :discovered_from,
      :discovered_at,
      :position_in_uploads
    ])
    |> validate_required([:title, :external_id, :url, :channel_id])
    |> unique_constraint(:external_id)
    |> assoc_constraint(:channel)
    |> maybe_set_downloaded_timestamp()
    |> maybe_set_discovered_fields()
  end

  defp maybe_set_downloaded_timestamp(changeset) do
    case get_change(changeset, :is_downloaded) do
      true ->
        put_change(changeset, :downloaded_at, DateTime.utc_now() |> DateTime.truncate(:second))

      _ ->
        changeset
    end
  end

  defp maybe_set_discovered_fields(changeset) do
    discovered_from? = get_change(changeset, :discovered_from)

    changeset =
      case {discovered_from?, get_field(changeset, :discovered_at)} do
        {val, nil} when is_binary(val) and byte_size(val) > 0 ->
          put_change(changeset, :discovered_at, DateTime.utc_now() |> DateTime.truncate(:second))

        _ ->
          changeset
      end

    # If discovered_from indicates uploads playlist, attempt to set position if unset
    case {discovered_from?, get_change(changeset, :position_in_uploads)} do
      {"uploads" <> _rest, nil} -> put_change(changeset, :position_in_uploads, 0)
      _ -> changeset
    end
  end
end
