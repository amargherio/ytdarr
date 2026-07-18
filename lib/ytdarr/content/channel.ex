defmodule Ytdarr.Content.Channel do
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "channels"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :external_id, :platform, :is_monitored, :inserted_at]
  end

  actions do
    defaults [:read]

    destroy :destroy do
      require_atomic? false

      argument :delete_files, :boolean do
        allow_nil? false
        default true
      end

      change Ytdarr.Content.Channel.Changes.CleanupOnDestroy
    end

    create :create do
      accept [
        :name,
        :external_id,
        :url,
        :description,
        :platform,
        :avatar_url,
        :banner_url,
        :platform_username,
        :is_monitored,
        :uploads_playlist_id
      ]

      change Ytdarr.Content.Channel.Changes.SetFilesystemPaths
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :external_id,
        :url,
        :description,
        :platform,
        :avatar_url,
        :banner_url,
        :platform_username,
        :is_monitored,
        :last_checked_at,
        :last_video_published_at,
        :uploads_playlist_id
      ]

      change Ytdarr.Content.Channel.Changes.SetFilesystemPaths
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :monitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, true)
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
      change Ytdarr.Content.Channel.Changes.QueueSync
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
      change Ytdarr.Content.Channel.Changes.ToggleMonitor
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :mark_checked do
      require_atomic? false
      accept []
      change set_attribute(:last_checked_at, &DateTime.utc_now/0)
    end

    read :monitored do
      description "List all monitored channels"
      filter expr(is_monitored == true)
      prepare build(sort: [name: :asc])
    end
  end

  validations do
    validate {Ytdarr.Content.Channel.Validations.ValidUrl, attribute: :url}
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
      description "YouTube channel id, etc."
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :platform, :string do
      allow_nil? false
      public? true
      default "YouTube"
      description "e.g., YouTube, Twitch"
    end

    attribute :avatar_url, :string do
      public? true
      description "Platform thumbnail/avatar url"
    end

    attribute :banner_url, :string do
      public? true
      description "Platform banner url"
    end

    attribute :platform_username, :string do
      public? true
    end

    attribute :uploads_playlist_id, :string do
      public? true
      description "YouTube uploads playlist ID"
    end

    # Monitoring status
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

    attribute :last_video_published_at, :utc_datetime do
      public? true
      description "Publish date of the most recent video, used for incremental sync"
    end

    # Filesystem paths
    attribute :base_path, :string do
      public? true
      description "e.g., /downloads/channels/channel_name"
    end

    attribute :generic_video_path, :string do
      public? true
      description "e.g., /downloads/channels/channel_name/videos"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :videos, Ytdarr.Content.Video
    has_many :playlists, Ytdarr.Content.Playlist
  end

  identities do
    identity :unique_external_id, [:external_id]
  end
end
