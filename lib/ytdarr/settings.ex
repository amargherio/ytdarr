defmodule Ytdarr.Settings do
  @moduledoc """
  Domain for application settings configuration.
  Provides Ash resources for managing settings, media folders, quality profiles, and yt-dlp parameters.
  """
  use Ash.Domain,
    otp_app: :ytdarr,
    extensions: [AshAdmin.Domain]

  alias __MODULE__.{AppSetting, MediaRootFolder, QualityProfile, YtDlpParamSet}

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
  Checks environment overrides first, then the database.
  """
  def get_setting_value(key, default \\ nil) do
    env_override(key) ||
      case get_app_setting_by_key(key) do
        {:ok, nil} -> default
        {:ok, %AppSetting{value: value}} -> unwrap_value(value)
        {:error, _} -> default
      end
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
  Delete a setting by key.
  """
  def delete_setting(key) when is_binary(key) do
    case get_app_setting_by_key(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, setting} -> destroy_app_setting(setting)
      error -> error
    end
  end

  defp wrap_value(v) when is_map(v), do: v
  defp wrap_value(v), do: %{"v" => v}

  defp unwrap_value(%{"v" => v}), do: v
  defp unwrap_value(v), do: v

  defp infer_type(v) when is_boolean(v), do: "boolean"
  defp infer_type(v) when is_integer(v), do: "integer"
  defp infer_type(v) when is_binary(v), do: "string"
  defp infer_type(_), do: "json"

  # Environment variable overrides for sensitive keys
  defp env_override("youtube.primary_api_key"), do: System.get_env("YTDARR_YOUTUBE_API_KEY")
  defp env_override(_), do: nil

  # ---------------------------------------------------------------------------
  # Aggregation: effective_config
  # ---------------------------------------------------------------------------

  @doc """
  Returns the effective runtime configuration aggregated from all settings.
  """
  def effective_config do
    media = %{
      file_naming_template:
        get_setting_value("media.file_naming_template", "%(channel)s/%(title)s.%(ext)s"),
      move_strategy: get_setting_value("media.move_strategy", "hardlink"),
      clean_orphans: get_setting_value("media.clean_orphans", true),
      root_folders: list_media_root_folders!()
    }

    youtube = %{
      api_key: get_setting_value("youtube.primary_api_key"),
      region: get_setting_value("youtube.region", "US")
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
end
