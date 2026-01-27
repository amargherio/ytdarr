defmodule Ytdarr.Settings.AppSetting do
  @moduledoc """
  Resource for storing application settings as key/value pairs with typed values.
  """
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Settings,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "app_settings"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :key, :type, :inserted_at]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:key, :value, :type]
    end

    update :update do
      primary? true
      accept [:value, :type]
    end

    read :by_key do
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(key == ^arg(:key))
    end

    create :upsert do
      accept [:key, :value, :type]
      upsert? true
      upsert_identity :unique_key
      upsert_fields [:value, :type]
    end
  end

  attributes do
    integer_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :value, :map do
      allow_nil? false
      public? true
      description "Wrapped value (e.g., %{\"v\" => actual_value})"
    end

    attribute :type, :string do
      allow_nil? false
      public? true
      description "Type hint: boolean, integer, string, json"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
  end
end
