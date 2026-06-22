defmodule Ytdarr.Content.Video do
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "videos"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :title, :external_id, :is_downloaded, :upload_date, :inserted_at]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :title,
        :external_id,
        :url,
        :description,
        :duration,
        :upload_date,
        :thumbnail_url,
        :is_downloaded,
        :download_state,
        :download_path,
        :downloaded_at,
        :file_size,
        :download_quality,
        :discovered_from,
        :position_in_uploads,
        :is_blocklisted
      ]

      argument :channel_id, :integer do
        allow_nil? false
      end

      change manage_relationship(:channel_id, :channel, type: :append)
      change Ytdarr.Content.Video.Changes.SetDiscoveredFields
    end

    create :upsert do
      accept [
        :title,
        :external_id,
        :url,
        :description,
        :duration,
        :upload_date,
        :thumbnail_url,
        :discovered_from,
        :position_in_uploads,
        :is_blocklisted
      ]

      argument :channel_id, :integer do
        allow_nil? false
      end

      change manage_relationship(:channel_id, :channel, type: :append)
      change Ytdarr.Content.Video.Changes.SetDiscoveredFields

      upsert? true
      upsert_identity :unique_external_id
      upsert_fields [:title, :description, :duration, :upload_date, :thumbnail_url]
    end

    update :update do
      accept [
        :title,
        :description,
        :duration,
        :upload_date,
        :thumbnail_url,
        :is_downloaded,
        :download_state,
        :download_path,
        :downloaded_at,
        :file_size,
        :download_quality,
        :discovered_from,
        :position_in_uploads,
        :is_blocklisted
      ]
    end

    update :mark_downloaded do
      accept [:download_path, :file_size, :download_quality]

      change set_attribute(:is_downloaded, true)
      change set_attribute(:download_state, :downloaded)
      change set_attribute(:downloaded_at, &Ytdarr.Content.Video.Changes.utc_now_truncated/0)
    end

    update :blocklist do
      change set_attribute(:is_blocklisted, true)
    end

    update :unblocklist do
      change set_attribute(:is_blocklisted, false)
    end
  end

  attributes do
    integer_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      public? true
      description "YouTube video id, etc."
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :duration, :integer do
      public? true
      description "Duration in seconds"
    end

    attribute :upload_date, :date do
      public? true
    end

    attribute :thumbnail_url, :string do
      public? true
    end

    # Download tracking
    attribute :is_downloaded, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :downloaded_at, :utc_datetime do
      public? true
    end

    attribute :download_path, :string do
      public? true
      description "e.g., /downloads/channels/channel_name/videos/video_id.mp4"
    end

    attribute :file_size, :integer do
      public? true
      description "File size in bytes"
    end

    attribute :download_quality, :string do
      public? true
      description "e.g., 1080p, 720p"
    end

    attribute :download_state, :atom do
      constraints one_of: [:available, :queued, :downloading, :downloaded, :missing]
      default :available
      allow_nil? false
      public? true
    end

    # Discovery tracking
    attribute :discovered_from, :string do
      public? true
      description "uploads, playlist:PLAYLIST_ID, search, etc"
    end

    attribute :discovered_at, :utc_datetime do
      public? true
    end

    attribute :position_in_uploads, :integer do
      public? true
      description "Position when first discovered in the uploads playlist"
    end

    attribute :is_blocklisted, :boolean do
      default false
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :channel, Ytdarr.Content.Channel do
      attribute_type :integer
      allow_nil? false
    end

    many_to_many :playlists, Ytdarr.Content.Playlist do
      through Ytdarr.Content.PlaylistVideo
      source_attribute_on_join_resource :video_id
      destination_attribute_on_join_resource :playlist_id
    end
  end

  identities do
    identity :unique_external_id, [:external_id]
  end
end
