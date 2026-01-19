defmodule Ytdarr.Settings.MediaRootFolder do
  @moduledoc """
  Resource for media root folder configuration.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "media_root_folders"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :path, :purpose, :active, :inserted_at]
  end

  attributes do
    integer_primary_key :id

    attribute :path, :string do
      allow_nil? false
      public? true
    end

    attribute :purpose, :string do
      allow_nil? false
      default "videos"
      public? true
      description "e.g., videos, music, podcasts"
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_path, [:path]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:path, :purpose, :active]
    end

    update :update do
      primary? true
      accept [:path, :purpose, :active]
    end

    update :activate do
      change set_attribute(:active, true)
    end

    update :deactivate do
      change set_attribute(:active, false)
    end

    read :active_folders do
      filter expr(active == true)
    end
  end
end
