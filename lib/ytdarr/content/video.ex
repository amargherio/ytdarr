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
        :discovered_from,
        :position_in_uploads,
        :is_blocklisted
      ]
    end

    update :begin_download do
      accept []

      validate data_one_of(:download_state, [:available, :missing, :import_failed])

      validate attribute_equals(:import_recovery, %{"mode" => nil, "entries" => []}),
        message: "must not have pending recovery work"

      change set_attribute(:download_state, :queued)
      change set_attribute(:is_downloaded, false)
      change set_attribute(:download_path, nil)
      change set_attribute(:downloaded_at, nil)
      change set_attribute(:file_size, nil)
      change set_attribute(:download_quality, nil)
      change set_attribute(:import_error, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
      change set_attribute(:import_recovery, %{"mode" => nil, "entries" => []})
    end

    update :start_download do
      accept []

      validate data_one_of(:download_state, [:queued])

      change set_attribute(:download_state, :downloading)
    end

    update :mark_downloaded do
      accept [:download_path, :file_size, :download_quality]
      validate present(:download_path)

      validate data_one_of(:download_state, [:downloading])

      change set_attribute(:is_downloaded, true)
      change set_attribute(:download_state, :downloaded)
      change set_attribute(:downloaded_at, &Ytdarr.Content.Video.Changes.utc_now_truncated/0)
      change set_attribute(:import_error, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
      change set_attribute(:import_recovery, %{"mode" => nil, "entries" => []})
    end

    update :reset_download do
      accept []

      validate data_one_of(:download_state, [:queued, :downloading])

      change set_attribute(:is_downloaded, false)
      change set_attribute(:download_state, :available)
      change set_attribute(:download_path, nil)
      change set_attribute(:downloaded_at, nil)
      change set_attribute(:file_size, nil)
      change set_attribute(:download_quality, nil)
      change set_attribute(:import_error, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
      change set_attribute(:import_recovery, %{"mode" => nil, "entries" => []})
    end

    update :reset_downloaded do
      accept []

      validate data_one_of(:download_state, [:downloaded])

      change set_attribute(:is_downloaded, false)
      change set_attribute(:download_state, :available)
      change set_attribute(:download_path, nil)
      change set_attribute(:downloaded_at, nil)
      change set_attribute(:file_size, nil)
      change set_attribute(:download_quality, nil)
      change set_attribute(:import_error, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
      change set_attribute(:import_recovery, %{"mode" => nil, "entries" => []})
    end

    update :begin_import do
      accept [:import_job_id, :import_manifest]
      validate present(:import_job_id)
      validate compare(:import_job_id, greater_than: 0)
      validate present(:import_manifest)

      validate data_one_of(:download_state, [:available, :missing, :import_failed])

      validate attribute_equals(:import_recovery, %{"mode" => nil, "entries" => []}),
        message: "must not have pending recovery work"

      change set_attribute(:is_downloaded, false)
      change set_attribute(:download_state, :importing)
      change set_attribute(:download_path, nil)
      change set_attribute(:downloaded_at, nil)
      change set_attribute(:file_size, nil)
      change set_attribute(:download_quality, nil)
      change set_attribute(:import_error, nil)
    end

    update :mark_imported do
      accept [:download_path, :file_size, :download_quality, :import_recovery]
      validate present([:download_path, :import_recovery])

      validate data_one_of(:download_state, [:importing])

      change set_attribute(:is_downloaded, true)
      change set_attribute(:download_state, :downloaded)
      change set_attribute(:downloaded_at, &Ytdarr.Content.Video.Changes.utc_now_truncated/0)
      change set_attribute(:import_error, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
    end

    update :mark_import_failed do
      accept [:import_error, :import_recovery]
      validate present([:import_error, :import_recovery])

      validate data_one_of(:download_state, [:importing])

      change set_attribute(:is_downloaded, false)
      change set_attribute(:download_state, :import_failed)
      change set_attribute(:download_path, nil)
      change set_attribute(:downloaded_at, nil)
      change set_attribute(:file_size, nil)
      change set_attribute(:download_quality, nil)
      change set_attribute(:import_job_id, nil)
      change set_attribute(:import_manifest, nil)
    end

    update :update_import_recovery do
      accept [:import_recovery]
      validate present(:import_recovery)

      validate data_one_of(:download_state, [:downloaded, :import_failed])
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
      constraints one_of: [
                    :available,
                    :queued,
                    :downloading,
                    :downloaded,
                    :missing,
                    :importing,
                    :import_failed
                  ]

      default :available
      allow_nil? false
      public? true
    end

    attribute :import_error, :string do
      constraints max_length: 500
      public? true
    end

    attribute :import_job_id, :integer do
      public? true
    end

    attribute :import_manifest, :map do
      public? true
    end

    attribute :import_recovery, :map do
      allow_nil? false
      default %{"mode" => nil, "entries" => []}
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
