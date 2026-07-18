defmodule Ytdarr.Settings do
  @moduledoc """
  Domain for application settings configuration.
  Provides Ash resources for managing settings, media folders, quality profiles, and yt-dlp parameters.
  """
  use Ash.Domain,
    otp_app: :ytdarr,
    extensions: [AshAdmin.Domain]

  alias __MODULE__.{AppSetting, Catalog, MediaRootFolder, QualityProfile, YtDlpParamSet}

  admin do
    show? true
  end

  resources do
    resource AppSetting do
      define :list_app_settings, action: :read
      define :get_app_setting_by_key, action: :by_key, args: [:key]
      define :create_app_setting, action: :create
      define :update_app_setting, action: :update
      define :upsert_app_setting, action: :upsert
      define :destroy_app_setting, action: :destroy
    end

    resource MediaRootFolder do
      define :list_media_root_folders, action: :read
      define :list_active_media_folders, action: :active_folders
      define :get_media_root_folder, action: :read, get_by: [:id]
      define :create_media_root_folder, action: :create
      define :update_media_root_folder, action: :update
      define :activate_media_root_folder, action: :activate
      define :deactivate_media_root_folder, action: :deactivate
      define :destroy_media_root_folder, action: :destroy
    end

    resource QualityProfile do
      define :list_quality_profiles, action: :read
      define :get_quality_profile, action: :read, get_by: [:id]
      define :get_default_quality_profile, action: :default_profile
      define :create_quality_profile, action: :create
      define :update_quality_profile, action: :update
      define :set_default_quality_profile, action: :set_as_default
      define :destroy_quality_profile, action: :destroy
    end

    resource YtDlpParamSet do
      define :list_yt_dlp_param_sets, action: :read
      define :get_yt_dlp_param_set, action: :read, get_by: [:id]
      define :get_default_yt_dlp_param_set, action: :default_param_set
      define :create_yt_dlp_param_set, action: :create
      define :update_yt_dlp_param_set, action: :update
      define :set_default_yt_dlp_param_set, action: :set_as_default
      define :destroy_yt_dlp_param_set, action: :destroy
    end
  end

  # ---------------------------------------------------------------------------
  # Convenience functions for key/value settings
  # ---------------------------------------------------------------------------

  @doc """
  Get a setting value by key with an optional default.
  Checks environment overrides first (if non-empty), then the database.

  Note: The StartupLoader will also store the environment variable value
  into the database at startup if the database is empty, ensuring persistence.
  """
  def get_setting_value(key, default \\ nil) when is_binary(key) do
    case env_override(key) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case get_app_setting_by_key(key) do
          {:ok, nil} -> default
          {:ok, %AppSetting{value: value}} -> unwrap_value(value)
          {:error, _} -> default
        end
    end
  end

  @doc """
  Returns `{display_value, source}` for a setting key.

  `source` is one of:
    * `:environment` — an env var override is in effect
    * `:database` — value is stored in the database
    * `:default` — no stored value; the catalog default applies
    * `:unset` — no stored value and no catalog default

  Sensitive keys (e.g., `youtube.primary_api_key`) return `"[configured]"` as
  the display value when a value is present, never the actual secret. Internal
  callers that need the raw value should use `get_setting_value/2` directly.
  """
  @spec get_setting_with_source(String.t(), term()) ::
          {term(), Catalog.source()}
  def get_setting_with_source(key, default \\ nil) when is_binary(key) do
    {raw, source} = raw_value_with_source(key, default)

    display =
      if Catalog.sensitive?(key) and not is_nil(raw) do
        "[configured]"
      else
        raw
      end

    {display, source}
  end

  @doc """
  Put a setting value (creates or updates).
  """
  def put_setting(key, value, type \\ nil) when is_binary(key) do
    type = type || infer_type(value)
    attrs = %{key: key, value: wrap_value(value), type: type}
    upsert_app_setting(attrs)
  end

  @doc """
  Saves multiple settings transactionally.

  Accepts a list of `{key, value}` pairs (or a keyword list). All upserts run
  inside a single database transaction — if any write fails the whole batch is
  rolled back and `{:error, reason}` is returned so the UI never reports success
  after a partial write.

  Returns `{:ok, [%AppSetting{}]}` on success.
  """
  @spec save_section([{String.t(), term()}]) ::
          {:ok, [AppSetting.t()]} | {:error, term()}
  def save_section(pairs) when is_list(pairs) do
    Ytdarr.Repo.transaction(fn ->
      Enum.map(pairs, fn {key, value} ->
        case put_setting(key, value) do
          {:ok, setting} ->
            setting

          {:error, reason} ->
            Ytdarr.Repo.rollback(reason)
        end
      end)
    end)
  end

  @doc """
  Delete a setting by key.
  """
  def delete_setting(key) when is_binary(key) do
    case get_app_setting_by_key(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, setting} -> destroy_app_setting(setting)
      error -> error
    end
  end

  @doc """
  Get the first active media root folder path.
  Returns the path of the first active folder, or a default.
  """
  def get_app_media_root_folder! do
    case list_active_media_folders!() do
      [folder | _] -> folder.path
      [] -> "/downloads"
    end
  end

  # ---------------------------------------------------------------------------
  # Path validation helper
  # ---------------------------------------------------------------------------

  @doc """
  Validates that a path is absolute, exists, is a directory, and is writable.

  Returns `{:ok, path}` on success, or `{:error, reason_atom, human_message}` on failure.

  `reason_atom` values:
    * `:not_absolute` — path does not start with `/`
    * `:not_found` — path does not exist on disk
    * `:not_directory` — path exists but is not a directory
    * `:not_writable` — directory exists but is not writable by the current process
  """
  @spec validate_path(String.t()) ::
          {:ok, String.t()}
          | {:error, :not_absolute, String.t()}
          | {:error, :not_found, String.t()}
          | {:error, :not_directory, String.t()}
          | {:error, :not_writable, String.t()}
  def validate_path(path) when is_binary(path) do
    cond do
      Path.type(path) != :absolute ->
        {:error, :not_absolute, "path must be absolute (must start with /)"}

      not File.exists?(path) ->
        {:error, :not_found, "path does not exist on disk"}

      not File.dir?(path) ->
        {:error, :not_directory, "path exists but is not a directory"}

      not path_writable?(path) ->
        {:error, :not_writable, "directory is not writable by the application"}

      true ->
        {:ok, path}
    end
  end

  # ---------------------------------------------------------------------------
  # YouTube credential test
  # ---------------------------------------------------------------------------

  @doc """
  Tests a YouTube API key by issuing a minimal `channels.list` read request
  (1 quota unit). The key is not logged or included in error tuples.

  Accepts an optional `:client` keyword for test injection (follows the same
  `Req` plug pattern used throughout the YouTube service layer).

  Returns:
    * `{:ok, :valid}` — key is accepted by the API
    * `{:error, :empty_key}` — key is nil or blank
    * `{:error, :invalid_key}` — API returned 403 keyInvalid
    * `{:error, :quota_exceeded}` — API returned 403 quotaExceeded
    * `{:error, {:http_error, status, message}}` — unexpected HTTP response
    * `{:error, {:network, reason}}` — connection-level failure
  """
  @spec test_youtube_credential(String.t() | nil, keyword()) ::
          {:ok, :valid}
          | {:error, :empty_key}
          | {:error, :invalid_key}
          | {:error, :quota_exceeded}
          | {:error, {:http_error, integer(), String.t()}}
          | {:error, {:network, term()}}
  def test_youtube_credential(api_key, opts \\ [])

  def test_youtube_credential(nil, _opts), do: {:error, :empty_key}
  def test_youtube_credential("", _opts), do: {:error, :empty_key}

  def test_youtube_credential(api_key, opts) when is_binary(api_key) do
    Ytdarr.Services.YouTube.Client.test_credential(api_key, opts)
  end

  # ---------------------------------------------------------------------------
  # AshPhoenix form helpers
  # ---------------------------------------------------------------------------

  @doc "Builds an AshPhoenix form for creating a new media root folder."
  def form_to_create_media_root_folder do
    AshPhoenix.Form.for_create(MediaRootFolder, :create,
      domain: __MODULE__,
      as: "media_root_folder"
    )
  end

  @doc "Builds an AshPhoenix form for updating an existing media root folder."
  def form_to_update_media_root_folder(folder) do
    AshPhoenix.Form.for_update(folder, :update,
      domain: __MODULE__,
      as: "media_root_folder"
    )
  end

  @doc "Builds an AshPhoenix form for creating a new quality profile."
  def form_to_create_quality_profile do
    AshPhoenix.Form.for_create(QualityProfile, :create,
      domain: __MODULE__,
      as: "quality_profile"
    )
  end

  @doc "Builds an AshPhoenix form for updating an existing quality profile."
  def form_to_update_quality_profile(profile) do
    AshPhoenix.Form.for_update(profile, :update,
      domain: __MODULE__,
      as: "quality_profile"
    )
  end

  @doc "Builds an AshPhoenix form for creating a new yt-dlp parameter set."
  def form_to_create_yt_dlp_param_set do
    AshPhoenix.Form.for_create(YtDlpParamSet, :create,
      domain: __MODULE__,
      as: "yt_dlp_param_set"
    )
  end

  @doc "Builds an AshPhoenix form for updating an existing yt-dlp parameter set."
  def form_to_update_yt_dlp_param_set(param_set) do
    AshPhoenix.Form.for_update(param_set, :update,
      domain: __MODULE__,
      as: "yt_dlp_param_set"
    )
  end

  @doc "Builds an AshPhoenix form for updating an existing app setting."
  def form_to_update_app_setting(setting) do
    AshPhoenix.Form.for_update(setting, :update,
      domain: __MODULE__,
      as: "app_setting"
    )
  end

  # ---------------------------------------------------------------------------
  # Aggregation: effective_config
  # ---------------------------------------------------------------------------

  @doc """
  Returns the effective runtime configuration aggregated from all settings.
  """
  def effective_config do
    media = %{
      file_naming_template:
        get_setting_value(
          "media.file_naming_template",
          Catalog.default_value("media.file_naming_template")
        ),
      move_strategy:
        get_setting_value("media.move_strategy", Catalog.default_value("media.move_strategy")),
      clean_orphans:
        get_setting_value("media.clean_orphans", Catalog.default_value("media.clean_orphans")),
      owner_group:
        get_setting_value("media.owner_group", Catalog.default_value("media.owner_group")),
      file_mode: get_setting_value("media.file_mode", Catalog.default_value("media.file_mode")),
      directory_mode:
        get_setting_value(
          "media.directory_mode",
          Catalog.default_value("media.directory_mode")
        ),
      root_folders: list_media_root_folders!()
    }

    youtube = %{
      api_key: get_setting_value("youtube.primary_api_key"),
      region: get_setting_value("youtube.region", Catalog.default_value("youtube.region"))
    }

    profiles = list_quality_profiles!()
    param_sets = list_yt_dlp_param_sets!()

    downloader = %{
      default_param_set:
        get_setting_value("yt_dlp.default_param_set_name", default_param_set_name(param_sets)),
      param_sets: param_sets
    }

    %{
      media: media,
      youtube: youtube,
      profiles: profiles,
      downloader: downloader
    }
  end

  defp default_param_set_name(param_sets) do
    case Enum.find(param_sets, & &1.is_default) do
      nil -> param_sets |> List.first() |> then(&(&1 && &1.name)) || "Default"
      set -> set.name
    end
  end

  # ---------------------------------------------------------------------------
  # Stable integration-contract functions for SettingsLive
  # ---------------------------------------------------------------------------

  @doc """
  Returns a unified state map for a single setting key.

  This is the primary function for the UI to read a setting — it combines
  the effective display value, its source, a `configured?` flag, and the
  full catalog metadata in one call.

  ## Return shape

      %{
        key:         "youtube.primary_api_key",
        value:       "[configured]",       # nil when unset; masked for sensitive keys
        source:      :environment,         # :database | :environment | :default | :unset
        configured?: true,                 # true when value is non-nil
        metadata:    %{                    # nil when key is not in the catalog
          type:           :string,
          category:       :youtube,
          effect_status:  :runtime,
          description:    "YouTube Data API v3 key…",
          env_var:        "YTDARR_YOUTUBE_API_KEY",
          sensitive?:     true,
          allowed_values: nil
        }
      }

  Sensitive keys (marked `sensitive?: true` in the catalog) always return
  `"[configured]"` as the display value when a value is present — the raw
  secret is never returned. Callers that need the actual value for runtime use
  (not display) should call `get_setting_value/2` directly.
  """
  @spec setting_state(String.t()) :: %{
          key: String.t(),
          value: term(),
          source: Catalog.source(),
          configured?: boolean(),
          metadata: map() | nil
        }
  def setting_state(key) when is_binary(key) do
    {display_value, source} = get_setting_with_source(key)

    metadata =
      case Catalog.get(key) do
        nil ->
          nil

        entry ->
          %{
            type: entry.type,
            category: entry.category,
            effect_status: entry.effect_status,
            description: entry.description,
            env_var: Map.get(entry, :env_var),
            sensitive?: Map.get(entry, :sensitive?, false),
            allowed_values: Map.get(entry, :allowed_values)
          }
      end

    %{
      key: key,
      value: display_value,
      source: source,
      configured?: not is_nil(display_value),
      metadata: metadata
    }
  end

  @doc """
  Saves multiple settings transactionally.

  Alias for `save_section/1` that additionally accepts a plain map (atom or
  string keys are both accepted). All upserts run in a single database
  transaction — if any write fails the entire batch rolls back and
  `{:error, reason}` is returned so the UI never reports success after a
  partial write.

  ## Examples

      # List of {key, value} pairs (strings or atoms as keys)
      Settings.save_settings([{"media.move_strategy", "copy"}, {"youtube.region", "GB"}])

      # Plain map (atom keys are converted to strings)
      Settings.save_settings(%{media_move_strategy: "copy", youtube_region: "GB"})

  ## Returns

    * `{:ok, [%AppSetting{}]}` — all settings written
    * `{:error, %Ash.Error.Invalid{}}` — validation failure (all writes rolled back)
    * `{:error, term()}` — other failure (all writes rolled back)
  """
  @spec save_settings([{String.t() | atom(), term()}] | %{optional(term()) => term()}) ::
          {:ok, [AppSetting.t()]} | {:error, term()}
  def save_settings(settings) when is_map(settings) do
    settings
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> save_section()
  end

  def save_settings(pairs) when is_list(pairs), do: save_section(pairs)

  @doc """
  Validates that `path` is absolute, exists on disk, is a directory, and is
  writable by the application process.

  Returns `:ok` on success. Returns `{:error, reason}` where `reason` is a
  descriptive atom on failure.

  ## Reason atoms

    * `:not_absolute` — path does not start with `/`
    * `:not_found` — path does not exist on disk
    * `:not_directory` — path exists but is not a directory
    * `:not_writable` — directory exists but is not writable

  Use `validate_path/1` if you also need the human-readable message string.
  """
  @spec validate_media_root_path(String.t()) :: :ok | {:error, atom()}
  def validate_media_root_path(path) do
    case validate_path(path) do
      {:ok, _} -> :ok
      {:error, reason, _message} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp wrap_value(v) when is_map(v), do: v
  defp wrap_value(v), do: %{"v" => v}

  defp unwrap_value(%{"v" => v}), do: v
  defp unwrap_value(v), do: v

  defp infer_type(v) when is_boolean(v), do: "boolean"
  defp infer_type(v) when is_integer(v), do: "integer"
  defp infer_type(v) when is_binary(v), do: "string"
  defp infer_type(_), do: "json"

  # Returns the raw (un-masked) value and its source atom.
  defp raw_value_with_source(key, default) do
    case env_override(key) do
      value when is_binary(value) and value != "" ->
        {value, :environment}

      _ ->
        case get_app_setting_by_key(key) do
          {:ok, nil} ->
            case default_value(key, default) do
              nil -> {nil, :unset}
              val -> {val, :default}
            end

          {:ok, %AppSetting{value: value}} ->
            {unwrap_value(value), :database}

          {:error, _} ->
            case default_value(key, default) do
              nil -> {nil, :unset}
              val -> {val, :default}
            end
        end
    end
  end

  defp default_value(key, nil), do: Catalog.default_value(key)
  defp default_value(_key, default), do: default

  # Environment variable overrides for sensitive keys (only if non-empty)
  defp env_override("youtube.primary_api_key"), do: System.get_env("YTDARR_YOUTUBE_API_KEY")
  defp env_override(_), do: nil

  # Checks writability by attempting to create and immediately remove a probe file.
  defp path_writable?(path) do
    probe = Path.join(path, ".ytdarr_write_probe_#{System.unique_integer([:positive])}")

    case File.write(probe, "") do
      :ok ->
        File.rm(probe)
        true

      {:error, _} ->
        false
    end
  end
end
