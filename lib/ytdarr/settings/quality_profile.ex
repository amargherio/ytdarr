defmodule Ytdarr.Settings.QualityProfile do
  @moduledoc """
  Resource for video quality profile configuration.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "quality_profiles"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :max_height, :is_default, :inserted_at]
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

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :max_height, :max_bitrate_kbps, :preferred_codecs, :allow_hdr, :format_selector, :is_default]
      change {Ytdarr.Settings.QualityProfile.ClearOtherDefaults, []}
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :max_height, :max_bitrate_kbps, :preferred_codecs, :allow_hdr, :format_selector, :is_default]
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
  end
end

defmodule Ytdarr.Settings.QualityProfile.ClearOtherDefaults do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      if result.is_default do
        require Ash.Query

        Ytdarr.Settings.QualityProfile
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
