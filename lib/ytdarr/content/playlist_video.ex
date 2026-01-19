defmodule Ytdarr.Content.PlaylistVideo do
  @moduledoc "Join resource for the many-to-many relationship between playlists and videos"
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "playlist_videos"
    repo Ytdarr.Repo
  end

  attributes do
    integer_primary_key :id

    attribute :position, :integer do
      public? true
      description "Position of the video in the playlist"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :playlist, Ytdarr.Content.Playlist do
      attribute_type :integer
      allow_nil? false
      primary_key? true
    end

    belongs_to :video, Ytdarr.Content.Video do
      attribute_type :integer
      allow_nil? false
      primary_key? true
    end
  end

  identities do
    identity :unique_playlist_video, [:playlist_id, :video_id]
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      primary? true
      accept [:position, :playlist_id, :video_id]
    end
  end
end
