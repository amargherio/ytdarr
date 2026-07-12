defmodule Ytdarr.Settings.QualityProfile do
  @moduledoc """
  Resource for video quality profile configuration.

  ## Constraints

    * `name` must be non-blank.
    * `max_height` and `max_bitrate_kbps` must be positive integers when provided.
    * The default profile cannot be deleted until another profile is set as default.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  alias Ytdarr.Settings.QualityProfile.Validations.PreventDefaultDelete

  sqlite do
    table "quality_profiles"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :max_height, :is_default, :inserted_at]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :name,
        :max_height,
        :max_bitrate_kbps,
        :preferred_codecs,
        :allow_hdr,
        :format_selector,
        :is_default
      ]

      validate fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)

        if is_nil(name) or String.trim(name) == "" do
          {:error, field: :name, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :max_height) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :max_height, message: "must be a positive integer"}
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :max_bitrate_kbps) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :max_bitrate_kbps, message: "must be a positive integer"}
        end
      end

      change {Ytdarr.Settings.QualityProfile.ClearOtherDefaults, []}
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :max_height,
        :max_bitrate_kbps,
        :preferred_codecs,
        :allow_hdr,
        :format_selector,
        :is_default
      ]

      validate fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)

        if not is_nil(name) and String.trim(name) == "" do
          {:error, field: :name, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :max_height) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :max_height, message: "must be a positive integer"}
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :max_bitrate_kbps) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :max_bitrate_kbps, message: "must be a positive integer"}
        end
      end

      change {Ytdarr.Settings.QualityProfile.ClearOtherDefaults, []}
    end

    update :set_as_default do
      require_atomic? false
      change set_attribute(:is_default, true)
      change {Ytdarr.Settings.QualityProfile.ClearOtherDefaults, []}
    end

    read :default_profile do
      get? true
      filter expr(is_default == true)
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      validate PreventDefaultDelete
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :max_height, :integer do
      public? true
      description "Max video height in pixels (e.g., 1080, 2160)"
    end

    attribute :max_bitrate_kbps, :integer do
      public? true
      description "Max video bitrate in kbps"
    end

    attribute :preferred_codecs, {:array, :string} do
      default []
      public? true
      description "Ordered list of preferred codecs"
    end

    attribute :allow_hdr, :boolean do
      default true
      public? true
    end

    attribute :format_selector, :string do
      public? true
      description "yt-dlp format selector string"
    end

    attribute :is_default, :boolean do
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name]
  end
end
