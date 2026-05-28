defmodule Ytdarr.Content.Playlist do
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "playlists"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :external_id, :video_count, :is_monitored, :inserted_at]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :external_id,
        :url,
        :description,
        :video_count,
        :is_monitored
      ]

      argument :channel_id, :integer do
        allow_nil? false
      end

      change manage_relationship(:channel_id, :channel, type: :append)
      change Ytdarr.Content.Playlist.Changes.SetDownloadPath
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    create :upsert do
      accept [
        :name,
        :external_id,
        :url,
        :description,
        :video_count,
        :is_monitored
      ]

      argument :channel_id, :integer do
        allow_nil? false
      end

      change manage_relationship(:channel_id, :channel, type: :append)
      change Ytdarr.Content.Playlist.Changes.SetDownloadPath
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp

      upsert? true
      upsert_identity :unique_external_id
      upsert_fields [:name, :description, :video_count]
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :description,
        :video_count,
        :is_monitored,
        :last_checked_at
      ]

      change Ytdarr.Content.Playlist.Changes.SetDownloadPath
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    update :monitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, true)
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
      change Ytdarr.Content.Playlist.Changes.QueueSync
    end

    update :unmonitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, false)
      change set_attribute(:is_monitored_since, nil)
    end

    update :toggle_monitor do
      require_atomic? false
      accept []
      change Ytdarr.Content.Playlist.Changes.ToggleMonitor
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    update :mark_checked do
      require_atomic? false
      accept []
      change set_attribute(:last_checked_at, &DateTime.utc_now/0)
    end

    read :monitored do
      description "List all monitored playlists"
      filter expr(is_monitored == true)
      prepare build(sort: [name: :asc], load: [:channel])
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      public? true
      description "YouTube playlist id, etc."
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :video_count, :integer do
      public? true
      description "Number of videos in the playlist"
    end

    # Monitoring
    attribute :is_monitored, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :is_monitored_since, :utc_datetime do
      public? true
    end

    attribute :last_checked_at, :utc_datetime do
      public? true
    end

    # Filesystem
    attribute :download_path, :string do
      public? true
      description "channel base path + /playlist_name"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :channel, Ytdarr.Content.Channel do
      attribute_type :integer
      allow_nil? false
    end

    many_to_many :videos, Ytdarr.Content.Video do
      through Ytdarr.Content.PlaylistVideo
      source_attribute_on_join_resource :playlist_id
      destination_attribute_on_join_resource :video_id
    end
  end

  identities do
    identity :unique_external_id, [:external_id]
  end
end
