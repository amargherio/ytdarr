defmodule Ytdarr.Settings.Catalog do
  @moduledoc """
  Centralized metadata catalog for known application setting keys.

  Each entry describes a setting's type, category, default value, sensitivity,
  runtime effect status, and optional environment variable source.

  ## Sources

    * `:database` — value comes from the app_settings table
    * `:environment` — value comes from an env var override (takes precedence)
    * `:default` — no stored value; catalog default is used
    * `:unset` — no stored value and no catalog default

  ## Effect Statuses

    * `:runtime` — change takes effect immediately on next request/operation
    * `:stored_only` — value is persisted but current runtime code does not consume it
    * `:next_schedule` — change applies when the next interval job is scheduled
  """

  @type source :: :database | :environment | :default | :unset

  @type entry :: %{
          key: String.t(),
          type: :string | :integer | :boolean,
          category: atom(),
          default: term(),
          sensitive?: boolean(),
          effect_status: :runtime | :stored_only | :next_schedule,
          env_var: String.t() | nil,
          description: String.t()
        }

  @catalog %{
    "youtube.primary_api_key" => %{
      key: "youtube.primary_api_key",
      type: :string,
      category: :youtube,
      default: nil,
      sensitive?: true,
      effect_status: :runtime,
      env_var: "YTDARR_YOUTUBE_API_KEY",
      description: "YouTube Data API v3 key used for all API calls."
    },
    "youtube.region" => %{
      key: "youtube.region",
      type: :string,
      category: :youtube,
      default: "US",
      sensitive?: false,
      effect_status: :stored_only,
      env_var: nil,
      description: "Region/country code reserved for future region-aware YouTube API requests."
    },
    "media.file_naming_template" => %{
      key: "media.file_naming_template",
      type: :string,
      category: :media,
      default: "%(channel)s/%(title)s.%(ext)s",
      sensitive?: false,
      effect_status: :stored_only,
      env_var: nil,
      description: "Intended output template for a future configurable naming pipeline."
    },
    "media.move_strategy" => %{
      key: "media.move_strategy",
      type: :string,
      category: :media,
      default: "hardlink",
      sensitive?: false,
      effect_status: :stored_only,
      env_var: nil,
      allowed_values: ["hardlink", "copy", "move"],
      description: "Intended file placement strategy: hardlink, copy, or move."
    },
    "media.clean_orphans" => %{
      key: "media.clean_orphans",
      type: :boolean,
      category: :media,
      default: true,
      sensitive?: false,
      effect_status: :stored_only,
      env_var: nil,
      description: "Intended orphan cleanup policy for future runtime support."
    },
    "sync_interval_minutes" => %{
      key: "sync_interval_minutes",
      type: :integer,
      category: :sync,
      default: 60,
      sensitive?: false,
      effect_status: :next_schedule,
      env_var: nil,
      description: "Interval in minutes between automatic batch sync runs."
    }
  }

  @doc "Returns all catalog entries as a list."
  @spec all() :: [entry()]
  def all, do: Map.values(@catalog)

  @doc "Returns all catalog entries for a given category atom."
  @spec by_category(atom()) :: [entry()]
  def by_category(category), do: Enum.filter(all(), &(&1.category == category))

  @doc "Returns the catalog entry for `key`, or `nil` if not in the catalog."
  @spec get(String.t()) :: entry() | nil
  def get(key), do: Map.get(@catalog, key)

  @doc "Returns the default value for `key`, or `nil` if not catalogued."
  @spec default_value(String.t()) :: term()
  def default_value(key) do
    case Map.get(@catalog, key) do
      nil -> nil
      entry -> entry.default
    end
  end

  @doc "Returns `true` if the given key is marked as sensitive."
  @spec sensitive?(String.t()) :: boolean()
  def sensitive?(key) do
    case Map.get(@catalog, key) do
      nil -> false
      entry -> Map.get(entry, :sensitive?, false)
    end
  end

  @doc "Returns the environment variable name for `key`, or `nil`."
  @spec env_var(String.t()) :: String.t() | nil
  def env_var(key) do
    case Map.get(@catalog, key) do
      nil -> nil
      entry -> entry.env_var
    end
  end

  @doc """
  Returns the allowed string values for `key`, or `nil` if unrestricted.
  Only set for string-typed settings with a fixed value set.
  """
  @spec allowed_values(String.t()) :: [String.t()] | nil
  def allowed_values(key) do
    case Map.get(@catalog, key) do
      nil -> nil
      entry -> Map.get(entry, :allowed_values)
    end
  end
end
