defmodule Ytdarr.Settings.YtDlpParamSet do
  @moduledoc """
  Resource for yt-dlp parameter set configuration.

  ## Constraints

    * `name` must be non-blank.
    * `rate_limit_kbps` and `concurrency` must be positive integers when provided.
    * The default parameter set cannot be deleted until another is set as default.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  alias Ytdarr.Settings.YtDlpParamSet.Validations.PreventDefaultDelete

  sqlite do
    table "yt_dlp_param_sets"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :is_default, :inserted_at]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :format, :extra_args, :rate_limit_kbps, :concurrency, :is_default]

      validate fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)

        if is_nil(name) or String.trim(name) == "" do
          {:error, field: :name, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :rate_limit_kbps) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :rate_limit_kbps, message: "must be a positive integer"}
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :concurrency) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :concurrency, message: "must be a positive integer"}
        end
      end

      change {Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults, []}
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :format, :extra_args, :rate_limit_kbps, :concurrency, :is_default]

      validate fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)

        if not is_nil(name) and String.trim(name) == "" do
          {:error, field: :name, message: "cannot be blank"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :rate_limit_kbps) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :rate_limit_kbps, message: "must be a positive integer"}
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :concurrency) do
          nil -> :ok
          v when is_integer(v) and v > 0 -> :ok
          _ -> {:error, field: :concurrency, message: "must be a positive integer"}
        end
      end

      change {Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults, []}
    end

    update :set_as_default do
      require_atomic? false
      change set_attribute(:is_default, true)
      change {Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults, []}
    end

    read :default_param_set do
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

    attribute :format, :string do
      public? true
      description "yt-dlp format string"
    end

    attribute :extra_args, :string do
      public? true
      description "Additional yt-dlp arguments"
    end

    attribute :rate_limit_kbps, :integer do
      public? true
      description "Download rate limit in kbps"
    end

    attribute :concurrency, :integer do
      public? true
      description "Max concurrent downloads"
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
