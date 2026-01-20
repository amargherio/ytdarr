defmodule Ytdarr.SettingsTest do
  use Ytdarr.DataCase, async: true

  alias Ytdarr.Settings

  describe "app settings" do
    test "put/get roundtrip" do
      assert {:ok, _} = Settings.put_setting("media.move_strategy", "hardlink")
      assert Settings.get_setting_value("media.move_strategy") == "hardlink"
    end

    test "env override takes precedence when set" do
      # Store a value in the database first
      {:ok, _} = Settings.put_setting("youtube.primary_api_key", "db_key")
      # Env var should override database value when set
      System.put_env("YTDARR_YOUTUBE_API_KEY", "env_key")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)
      # Env value should be returned
      assert Settings.get_setting_value("youtube.primary_api_key") == "env_key"
    end

    test "database value used when env is empty" do
      # Store a value in the database
      {:ok, _} = Settings.put_setting("youtube.primary_api_key", "db_key")
      # Make sure env var is not set
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      # Database value should be returned
      assert Settings.get_setting_value("youtube.primary_api_key") == "db_key"
    end

    test "startup loader loads env into db when empty" do
      # Ensure no database value exists
      case Settings.get_app_setting_by_key("youtube.primary_api_key") do
        {:ok, setting} when not is_nil(setting) -> Settings.destroy_app_setting(setting)
        _ -> :ok
      end

      # Set env var
      System.put_env("YTDARR_YOUTUBE_API_KEY", "startup_key")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)

      # Run startup loader
      Ytdarr.Settings.StartupLoader.load_youtube_api_key()

      # Value should now be in database
      {:ok, setting} = Settings.get_app_setting_by_key("youtube.primary_api_key")
      assert setting.value == %{"v" => "startup_key"}
    end
  end

  describe "quality profiles defaults" do
    test "only one default enforced" do
      {:ok, p1} = Settings.create_quality_profile(%{name: "A", is_default: true})
      {:ok, p2} = Settings.create_quality_profile(%{name: "B", is_default: true})
      refute Settings.get_quality_profile!(p1.id).is_default
      assert Settings.get_quality_profile!(p2.id).is_default
    end
  end

  describe "yt-dlp param sets defaults" do
    test "only one default enforced" do
      {:ok, s1} = Settings.create_yt_dlp_param_set(%{name: "Set1", is_default: true})
      {:ok, s2} = Settings.create_yt_dlp_param_set(%{name: "Set2", is_default: true})
      refute Settings.get_yt_dlp_param_set!(s1.id).is_default
      assert Settings.get_yt_dlp_param_set!(s2.id).is_default
    end
  end

  describe "effective_config" do
    test "returns structured map" do
      {:ok, _} = Settings.put_setting("media.file_naming_template", "%(title)s.%(ext)s")
      cfg = Settings.effective_config()
      assert cfg.media.file_naming_template == "%(title)s.%(ext)s"
      assert is_list(cfg.media.root_folders)
      assert is_list(cfg.profiles)
      assert is_list(cfg.downloader.param_sets)
    end
  end
end
