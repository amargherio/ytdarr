defmodule Ytdarr.Settings.MediaRootFolder do
  @moduledoc """
  Resource for media root folder configuration.

  ## Constraints

    * `path` must be non-blank, absolute, exist on disk, be a directory, and be writable.
    * `purpose` must be one of: `videos`, `music`, `podcasts`.
    * The last active folder cannot be deactivated or destroyed.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  alias Ytdarr.Settings.MediaRootFolder.Validations.{LastActiveCheck, PathCheck}

  sqlite do
    table "media_root_folders"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :path, :purpose, :active, :inserted_at]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:path, :purpose, :active]

      validate fn changeset, _context ->
        path = Ash.Changeset.get_attribute(changeset, :path)

        if is_nil(path) or String.trim(path) == "" do
          {:error, field: :path, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        purpose = Ash.Changeset.get_attribute(changeset, :purpose)

        if is_nil(purpose) or purpose not in ["videos", "music", "podcasts"] do
          {:error, field: :purpose, message: "must be one of: videos, music, podcasts"}
        else
          :ok
        end
      end

      validate PathCheck
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:path, :purpose, :active]

      validate fn changeset, _context ->
        path = Ash.Changeset.get_attribute(changeset, :path)

        if not is_nil(path) and String.trim(path) == "" do
          {:error, field: :path, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        purpose = Ash.Changeset.get_attribute(changeset, :purpose)

        if not is_nil(purpose) and purpose not in ["videos", "music", "podcasts"] do
          {:error, field: :purpose, message: "must be one of: videos, music, podcasts"}
        else
          :ok
        end
      end

      validate PathCheck
      validate LastActiveCheck
    end

    update :activate do
      change set_attribute(:active, true)
    end

    update :deactivate do
      require_atomic? false
      validate LastActiveCheck
      change set_attribute(:active, false)
    end

    read :active_folders do
      filter expr(active == true)
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      validate LastActiveCheck
    end
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
end
