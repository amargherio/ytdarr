defmodule Ytdarr.Settings.YtDlpParamSet do
  @moduledoc """
  Resource for yt-dlp parameter set configuration.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "yt_dlp_param_sets"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :is_default, :inserted_at]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :format, :extra_args, :rate_limit_kbps, :concurrency, :is_default]
      change {Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults, []}
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :format, :extra_args, :rate_limit_kbps, :concurrency, :is_default]
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

defmodule Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      if result.is_default do
        require Ash.Query

        Ytdarr.Settings.YtDlpParamSet
        |> Ash.Query.filter(id != ^result.id and is_default == true)
        |> Ash.bulk_update!(:update, %{is_default: false},
          domain: Ytdarr.Settings,
          strategy: :stream
        )
      end

      {:ok, result}
    end)
  end
end
