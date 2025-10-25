defmodule Ytdarr.Settings do
  @moduledoc """
  Central settings context for application configuration (DB-backed).
  Provides CRUD for settings-related entities and an aggregated effective_config/0 for runtime use.
  """
  import Ecto.Query
  alias Ytdarr.Repo
  alias __MODULE__.{AppSetting, MediaRootFolder, QualityProfile, YtDlpParamSet}
  alias Ecto.Changeset

  # -----------------
  # Generic App Settings (key/value with typed value wrapper)
  # -----------------
  def list_app_settings, do: Repo.all(from s in AppSetting, order_by: s.key)

  def get_app_setting(key) when is_binary(key) do
    Repo.get_by(AppSetting, key: key)
  end

  def get_setting_value(key, default \\ nil) do
    env_override(key) ||
      case get_app_setting(key) do
        nil -> default
        %AppSetting{value: value} -> unwrap_value(value)
      end
  end

  # note: default type derived from provided value when not explicitly passed
  def put_setting(key, value, type \\ nil) when is_binary(key) do
    type = type || infer_type(value)
    attrs = %{key: key, value: wrap_value(value), type: type}

    case get_app_setting(key) do
      nil -> %AppSetting{} |> AppSetting.changeset(attrs) |> Repo.insert()
      setting -> setting |> AppSetting.changeset(attrs) |> Repo.update()
    end
  end

  def delete_setting(key) when is_binary(key) do
    with %AppSetting{} = setting <- get_app_setting(key) do
      Repo.delete(setting)
    else
      _ -> {:error, :not_found}
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

  # -----------------
  # Media Root Folders
  # -----------------
  def list_media_root_folders, do: Repo.all(from f in MediaRootFolder, order_by: f.path)
  def get_media_root_folder!(id), do: Repo.get!(MediaRootFolder, id)

  def create_media_root_folder(attrs) do
    %MediaRootFolder{} |> MediaRootFolder.changeset(attrs) |> Repo.insert()
  end

  def change_media_root_folder(%MediaRootFolder{} = folder, attrs \\ %{}) do
    MediaRootFolder.changeset(folder, attrs)
  end

  def delete_media_root_folder(id) do
    case Repo.get(MediaRootFolder, id) do
      nil -> {:error, :not_found}
      folder -> Repo.delete(folder)
    end
  end

  # -----------------
  # Quality Profiles
  # -----------------
  def list_quality_profiles do
    Repo.all(from p in QualityProfile, order_by: p.name)
  end

  def get_quality_profile!(id), do: Repo.get!(QualityProfile, id)

  def create_quality_profile(attrs) do
    Repo.transaction(fn ->
      with {:ok, profile} <-
             %QualityProfile{} |> QualityProfile.changeset(attrs) |> Repo.insert(),
           :ok <- maybe_clear_other_profile_defaults(profile) do
        profile
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def update_quality_profile(%QualityProfile{} = profile, attrs) do
    Repo.transaction(fn ->
      with {:ok, profile} <- profile |> QualityProfile.changeset(attrs) |> Repo.update(),
           :ok <- maybe_clear_other_profile_defaults(profile) do
        profile
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def change_quality_profile(%QualityProfile{} = profile, attrs \\ %{}) do
    QualityProfile.changeset(profile, attrs)
  end

  def delete_quality_profile(id) do
    case Repo.get(QualityProfile, id) do
      nil -> {:error, :not_found}
      profile -> Repo.delete(profile)
    end
  end

  defp maybe_clear_other_profile_defaults(%QualityProfile{is_default: true, id: id}) do
    Repo.update_all(from(p in QualityProfile, where: p.id != ^id and p.is_default),
      set: [is_default: false]
    )

    :ok
  end

  defp maybe_clear_other_profile_defaults(_), do: :ok

  def get_default_profile do
    Repo.one(from p in QualityProfile, where: p.is_default, limit: 1)
  end

  # -----------------
  # yt-dlp Param Sets
  # -----------------
  def list_yt_dlp_param_sets do
    Repo.all(from s in YtDlpParamSet, order_by: s.name)
  end

  def get_yt_dlp_param_set!(id), do: Repo.get!(YtDlpParamSet, id)

  def create_yt_dlp_param_set(attrs) do
    Repo.transaction(fn ->
      with {:ok, set} <- %YtDlpParamSet{} |> YtDlpParamSet.changeset(attrs) |> Repo.insert(),
           :ok <- maybe_clear_other_param_set_defaults(set) do
        set
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def update_yt_dlp_param_set(%YtDlpParamSet{} = set, attrs) do
    Repo.transaction(fn ->
      with {:ok, set} <- set |> YtDlpParamSet.changeset(attrs) |> Repo.update(),
           :ok <- maybe_clear_other_param_set_defaults(set) do
        set
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def change_yt_dlp_param_set(%YtDlpParamSet{} = set, attrs \\ %{}) do
    YtDlpParamSet.changeset(set, attrs)
  end

  def delete_yt_dlp_param_set(id) do
    case Repo.get(YtDlpParamSet, id) do
      nil -> {:error, :not_found}
      set -> Repo.delete(set)
    end
  end

  def get_default_param_set do
    Repo.one(from s in YtDlpParamSet, where: s.is_default, limit: 1)
  end

  defp maybe_clear_other_param_set_defaults(%YtDlpParamSet{is_default: true, id: id}) do
    Repo.update_all(from(s in YtDlpParamSet, where: s.id != ^id and s.is_default),
      set: [is_default: false]
    )

    :ok
  end

  defp maybe_clear_other_param_set_defaults(_), do: :ok

  # -----------------
  # Aggregation: effective_config
  # -----------------
  def effective_config do
    media = %{
      file_naming_template:
        get_setting_value("media.file_naming_template", "%(channel)s/%(title)s.%(ext)s"),
      move_strategy: get_setting_value("media.move_strategy", "hardlink"),
      clean_orphans: get_setting_value("media.clean_orphans", true),
      root_folders: list_media_root_folders()
    }

    youtube = %{
      api_key: get_setting_value("youtube.primary_api_key"),
      region: get_setting_value("youtube.region", "US")
    }

    profiles = list_quality_profiles()
    param_sets = list_yt_dlp_param_sets()

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
  # Virtual form changesets (for settings stored as key/value pairs)
  # ---------------------------------------------------------------------------
  def media_settings_changeset(attrs \\ %{}) do
    types = %{
      file_naming_template: :string,
      move_strategy: :string,
      clean_orphans: :boolean
    }

    data = %{
      file_naming_template:
        get_setting_value("media.file_naming_template", "%(channel)s/%(title)s.%(ext)s"),
      move_strategy: get_setting_value("media.move_strategy", "hardlink"),
      clean_orphans: get_setting_value("media.clean_orphans", true)
    }

    {data, types}
    |> Changeset.cast(attrs, Map.keys(types))
    |> Changeset.validate_required([:file_naming_template, :move_strategy])
    |> Changeset.validate_inclusion(:move_strategy, ["copy", "move", "hardlink"])
  end

  def youtube_settings_changeset(attrs \\ %{}) do
    types = %{
      api_key: :string,
      region: :string
    }

    data = %{
      api_key: get_setting_value("youtube.primary_api_key"),
      region: get_setting_value("youtube.region", "US")
    }

    {data, types}
    |> Changeset.cast(attrs, Map.keys(types))
    |> Changeset.validate_required([:region])
    |> Changeset.update_change(:api_key, fn
      "" -> nil
      v -> v
    end)
  end
end
