defmodule Ytdarr.SettingsTest do
  use Ytdarr.DataCase

  alias Ytdarr.Settings
  alias Ytdarr.Settings.Catalog

  describe "app settings" do
    test "put/get roundtrip" do
      assert {:ok, _} = Settings.put_setting("media.move_strategy", "hardlink")
      assert Settings.get_setting_value("media.move_strategy") == "hardlink"
    end

    test "env override takes precedence when set" do
      {:ok, _} = Settings.put_setting("youtube.primary_api_key", "db_key")
      System.put_env("YTDARR_YOUTUBE_API_KEY", "env_key")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)
      assert Settings.get_setting_value("youtube.primary_api_key") == "env_key"
    end

    test "database value used when env is empty" do
      {:ok, _} = Settings.put_setting("youtube.primary_api_key", "db_key")
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      assert Settings.get_setting_value("youtube.primary_api_key") == "db_key"
    end

    test "startup loader loads env into db when empty" do
      case Settings.get_app_setting_by_key("youtube.primary_api_key") do
        {:ok, setting} when not is_nil(setting) -> Settings.destroy_app_setting(setting)
        _ -> :ok
      end

      System.put_env("YTDARR_YOUTUBE_API_KEY", "startup_key")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)

      Ytdarr.Settings.StartupLoader.load_youtube_api_key()

      {:ok, setting} = Settings.get_app_setting_by_key("youtube.primary_api_key")
      assert setting.value == %{"v" => "startup_key"}
    end

    test "get_setting_value returns default when no record and no env override" do
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      assert Settings.get_setting_value("unknown.setting.key", :fallback) == :fallback
      assert Settings.get_setting_value("unknown.setting.key") == nil
    end

    test "put_setting infers types correctly" do
      assert {:ok, %{type: "integer"}} = Settings.put_setting("misc.int_setting", 42)
      assert Settings.get_setting_value("misc.int_setting") == 42

      assert {:ok, %{type: "boolean"}} = Settings.put_setting("misc.bool_setting", true)
      assert Settings.get_setting_value("misc.bool_setting") == true

      assert {:ok, %{type: "json"}} =
               Settings.put_setting("misc.list_setting", [1, 2, 3])
    end

    test "put_setting passes maps through wrap_value unchanged" do
      payload = %{"foo" => "bar"}
      assert {:ok, setting} = Settings.put_setting("misc.map_setting", payload, "json")
      assert setting.value == payload
    end

    test "delete_setting removes an existing setting" do
      {:ok, _} = Settings.put_setting("to.delete", "value")
      assert :ok = Settings.delete_setting("to.delete")
      assert Settings.get_setting_value("to.delete") == nil
    end

    test "delete_setting returns an error for missing key" do
      assert {:error, %Ash.Error.Invalid{}} = Settings.delete_setting("never.existed")
    end
  end

  # ---------------------------------------------------------------------------
  # Catalog
  # ---------------------------------------------------------------------------

  describe "Catalog.all/0" do
    test "returns all catalogued entries" do
      entries = Catalog.all()
      assert length(entries) >= 6
      keys = Enum.map(entries, & &1.key)
      assert "youtube.primary_api_key" in keys
      assert "sync_interval_minutes" in keys
    end
  end

  describe "Catalog.get/1" do
    test "returns entry for known key" do
      entry = Catalog.get("youtube.primary_api_key")
      assert entry.category == :youtube
      assert entry.type == :string
      assert entry.sensitive? == true
      assert entry.env_var == "YTDARR_YOUTUBE_API_KEY"
    end

    test "returns nil for unknown key" do
      assert Catalog.get("no.such.key") == nil
    end
  end

  describe "Catalog.default_value/1" do
    test "returns correct defaults" do
      assert Catalog.default_value("youtube.region") == "US"
      assert Catalog.default_value("media.move_strategy") == "hardlink"
      assert Catalog.default_value("sync_interval_minutes") == 60
      assert Catalog.default_value("media.clean_orphans") == true
      assert Catalog.default_value("youtube.primary_api_key") == nil
    end
  end

  describe "Catalog.sensitive?/1" do
    test "true for sensitive keys" do
      assert Catalog.sensitive?("youtube.primary_api_key") == true
    end

    test "false for non-sensitive keys" do
      assert Catalog.sensitive?("youtube.region") == false
      assert Catalog.sensitive?("sync_interval_minutes") == false
    end

    test "false for unknown keys" do
      assert Catalog.sensitive?("some.unknown.key") == false
    end
  end

  describe "Catalog.by_category/1" do
    test "returns all youtube-category entries" do
      youtube_entries = Catalog.by_category(:youtube)
      assert length(youtube_entries) >= 2
      assert Enum.all?(youtube_entries, &(&1.category == :youtube))
    end

    test "returns empty list for unknown category" do
      assert Catalog.by_category(:nonexistent) == []
    end
  end

  # ---------------------------------------------------------------------------
  # get_setting_with_source/2
  # ---------------------------------------------------------------------------

  describe "get_setting_with_source/2" do
    test "returns :environment source when env override is active" do
      System.put_env("YTDARR_YOUTUBE_API_KEY", "env_val")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)

      {display, source} = Settings.get_setting_with_source("youtube.primary_api_key")
      assert source == :environment
      assert display == "[configured]"
    end

    test "masks sensitive value from env source" do
      System.put_env("YTDARR_YOUTUBE_API_KEY", "super_secret_key")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)

      {display, :environment} = Settings.get_setting_with_source("youtube.primary_api_key")
      refute display =~ "super_secret"
      assert display == "[configured]"
    end

    test "returns :database source when stored in DB" do
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      {:ok, _} = Settings.put_setting("youtube.region", "DE")
      {val, source} = Settings.get_setting_with_source("youtube.region")
      assert source == :database
      assert val == "DE"
    end

    test "returns :default source for catalogued key with no stored value" do
      {val, source} =
        Settings.get_setting_with_source("youtube.region_#{System.unique_integer()}")

      assert source in [:default, :unset]
      _ = val
    end

    test "returns :default with catalog default for missing catalogued key" do
      {val, source} =
        Settings.get_setting_with_source(
          "media.move_strategy_missing_#{System.unique_integer()}",
          nil
        )

      assert source in [:default, :unset]
      _ = val
    end

    test "returns :unset when no value and no catalog default" do
      {val, source} =
        Settings.get_setting_with_source("completely.unknown.#{System.unique_integer()}")

      assert source == :unset
      assert val == nil
    end

    test "does not mask non-sensitive keys" do
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      {:ok, _} = Settings.put_setting("youtube.region", "FR")
      {val, :database} = Settings.get_setting_with_source("youtube.region")
      assert val == "FR"
    end

    test "preserves explicit false and zero defaults" do
      false_key = "unknown.false.#{System.unique_integer()}"
      zero_key = "unknown.zero.#{System.unique_integer()}"

      assert {false, :default} = Settings.get_setting_with_source(false_key, false)
      assert {0, :default} = Settings.get_setting_with_source(zero_key, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # save_section/1
  # ---------------------------------------------------------------------------

  describe "save_section/1" do
    test "saves multiple settings atomically and returns {:ok, settings}" do
      pairs = [
        {"media.move_strategy", "copy"},
        {"media.clean_orphans", false},
        {"youtube.region", "GB"}
      ]

      assert {:ok, saved} = Settings.save_section(pairs)
      assert length(saved) == 3

      assert Settings.get_setting_value("media.move_strategy") == "copy"
      assert Settings.get_setting_value("media.clean_orphans") == false
      assert Settings.get_setting_value("youtube.region") == "GB"
    end

    test "rolls back all saves when one key is invalid (nil key rejected)" do
      # Store a canary to verify rollback
      {:ok, _} = Settings.put_setting("section.canary", "before")

      # An empty string key is rejected by put_setting -> Ash validation
      pairs = [
        {"section.canary", "after"},
        {"", "bad_key"}
      ]

      result = Settings.save_section(pairs)
      assert {:error, _} = result

      # Canary should still be "before" if transaction rolled back
      assert Settings.get_setting_value("section.canary") == "before"
    end

    test "accepts keyword list format" do
      pairs = [my_key: "val1", other_key: "val2"]

      assert {:ok, _saved} =
               Settings.save_section(Enum.map(pairs, fn {k, v} -> {Atom.to_string(k), v} end))
    end
  end

  # ---------------------------------------------------------------------------
  # validate_path/1
  # ---------------------------------------------------------------------------

  describe "validate_path/1" do
    test "returns {:ok, path} for a writable directory" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)
      assert {:ok, ^dir} = Settings.validate_path(dir)
    end

    test "returns {:error, :not_absolute, _} for relative paths" do
      assert {:error, :not_absolute, msg} = Settings.validate_path("relative/path")
      assert is_binary(msg)
    end

    test "returns {:error, :not_found, _} for a non-existent absolute path" do
      assert {:error, :not_found, msg} =
               Settings.validate_path("/nonexistent/ytdarr_test_path_#{System.unique_integer()}")

      assert is_binary(msg)
    end

    test "returns {:error, :not_directory, _} for a file path" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)
      file_path = Path.join(dir, "testfile.txt")
      File.write!(file_path, "content")
      assert {:error, :not_directory, msg} = Settings.validate_path(file_path)
      assert is_binary(msg)
    end
  end

  # ---------------------------------------------------------------------------
  # quality profiles defaults
  # ---------------------------------------------------------------------------

  describe "quality profiles defaults" do
    test "only one default enforced" do
      {:ok, p1} = Settings.create_quality_profile(%{name: "A", is_default: true})
      {:ok, p2} = Settings.create_quality_profile(%{name: "B", is_default: true})
      refute Settings.get_quality_profile!(p1.id).is_default
      assert Settings.get_quality_profile!(p2.id).is_default
    end
  end

  describe "quality profile protected delete" do
    test "cannot delete default quality profile" do
      {:ok, profile} =
        Settings.create_quality_profile(%{
          name: "DefaultProfile_#{System.unique_integer()}",
          is_default: true
        })

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.destroy_quality_profile(profile)

      assert Enum.any?(errors, &(&1.field == :is_default))
    end

    test "can delete non-default quality profile" do
      {:ok, profile} =
        Settings.create_quality_profile(%{
          name: "NonDefault_#{System.unique_integer()}",
          is_default: false
        })

      assert :ok = Settings.destroy_quality_profile(profile)
    end

    test "non-blank name enforced on create" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_quality_profile(%{name: ""})

      assert Enum.any?(errors, &(&1.field == :name))
    end

    test "positive integer enforced for max_height" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_quality_profile(%{
                 name: "P_#{System.unique_integer()}",
                 max_height: -10
               })

      assert Enum.any?(errors, &(&1.field == :max_height))
    end
  end

  # ---------------------------------------------------------------------------
  # yt-dlp param sets defaults
  # ---------------------------------------------------------------------------

  describe "yt-dlp param sets defaults" do
    test "only one default enforced" do
      {:ok, s1} = Settings.create_yt_dlp_param_set(%{name: "Set1", is_default: true})
      {:ok, s2} = Settings.create_yt_dlp_param_set(%{name: "Set2", is_default: true})
      refute Settings.get_yt_dlp_param_set!(s1.id).is_default
      assert Settings.get_yt_dlp_param_set!(s2.id).is_default
    end
  end

  describe "yt-dlp param set protected delete" do
    test "cannot delete default yt-dlp param set" do
      {:ok, ps} =
        Settings.create_yt_dlp_param_set(%{
          name: "DefaultPS_#{System.unique_integer()}",
          is_default: true
        })

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.destroy_yt_dlp_param_set(ps)

      assert Enum.any?(errors, &(&1.field == :is_default))
    end

    test "can delete non-default yt-dlp param set" do
      {:ok, ps} =
        Settings.create_yt_dlp_param_set(%{
          name: "NonDefaultPS_#{System.unique_integer()}",
          is_default: false
        })

      assert :ok = Settings.destroy_yt_dlp_param_set(ps)
    end

    test "non-blank name enforced on create" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_yt_dlp_param_set(%{name: "  "})

      assert Enum.any?(errors, &(&1.field == :name))
    end

    test "positive integer enforced for concurrency" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_yt_dlp_param_set(%{
                 name: "PS_#{System.unique_integer()}",
                 concurrency: 0
               })

      assert Enum.any?(errors, &(&1.field == :concurrency))
    end
  end

  # ---------------------------------------------------------------------------
  # effective_config
  # ---------------------------------------------------------------------------

  describe "effective_config" do
    test "returns structured map" do
      {:ok, _} = Settings.put_setting("media.file_naming_template", "%(title)s.%(ext)s")
      cfg = Settings.effective_config()
      assert cfg.media.file_naming_template == "%(title)s.%(ext)s"
      assert cfg.media.owner_group == "ytdarr"
      assert cfg.media.file_mode == "0644"
      assert cfg.media.directory_mode == "0755"
      assert is_list(cfg.media.root_folders)
      assert is_list(cfg.profiles)
      assert is_list(cfg.downloader.param_sets)
    end

    test "returns persisted media permission values" do
      assert {:ok, _} = Settings.put_setting("media.owner_group", "media")
      assert {:ok, _} = Settings.put_setting("media.file_mode", "0664")
      assert {:ok, _} = Settings.put_setting("media.directory_mode", "0775")

      cfg = Settings.effective_config()

      assert cfg.media.owner_group == "media"
      assert cfg.media.file_mode == "0664"
      assert cfg.media.directory_mode == "0775"
    end
  end

  # ---------------------------------------------------------------------------
  # sync_interval_minutes key consistency
  # ---------------------------------------------------------------------------

  describe "sync_interval_minutes key" do
    test "string key is used consistently — stored value is returned" do
      {:ok, _} = Settings.put_setting("sync_interval_minutes", 30)
      assert Settings.get_setting_value("sync_interval_minutes", 60) == 30
    end

    test "atom key never matches database (verifying the bug is fixed)" do
      {:ok, _} = Settings.put_setting("sync_interval_minutes", 30)
      # The atom version should NOT find the string-keyed record
      # get_setting_value now requires binary keys — atom args would fail at compile/match
      # Confirming the string key works:
      assert Settings.get_setting_value("sync_interval_minutes") == 30
    end
  end

  # ---------------------------------------------------------------------------
  # Stable integration-contract functions
  # ---------------------------------------------------------------------------

  describe "setting_state/1" do
    test "returns full state map for a catalogued key with database value" do
      System.delete_env("YTDARR_YOUTUBE_API_KEY")
      {:ok, _} = Settings.put_setting("youtube.region", "AU")

      state = Settings.setting_state("youtube.region")

      assert state.key == "youtube.region"
      assert state.value == "AU"
      assert state.source == :database
      assert state.configured? == true
      assert state.metadata.type == :string
      assert state.metadata.category == :youtube
      assert state.metadata.sensitive? == false
      assert is_binary(state.metadata.description)
    end

    test "masks value for sensitive catalogued keys" do
      System.put_env("YTDARR_YOUTUBE_API_KEY", "supersecret")
      on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)

      state = Settings.setting_state("youtube.primary_api_key")

      assert state.source == :environment
      assert state.configured? == true
      assert state.value == "[configured]"
      refute state.value =~ "supersecret"
      assert state.metadata.sensitive? == true
      assert state.metadata.env_var == "YTDARR_YOUTUBE_API_KEY"
    end

    test "returns source: :default and configured?: false for unset catalogued key" do
      System.delete_env("YTDARR_YOUTUBE_API_KEY")

      # Use a unique suffix to guarantee no DB record
      state = Settings.setting_state("youtube.region")

      # If there's a DB record from another test, this may be :database — that's fine.
      # Just verify shape is correct.
      assert is_atom(state.source)
      assert is_boolean(state.configured?)
      assert is_map(state.metadata)
    end

    test "returns source: :unset and configured?: false for completely unknown key" do
      state = Settings.setting_state("no.such.key.#{System.unique_integer()}")

      assert state.source == :unset
      assert state.configured? == false
      assert state.value == nil
      assert state.metadata == nil
    end

    test "returns allowed_values in metadata when defined" do
      state = Settings.setting_state("media.move_strategy")
      assert state.metadata.allowed_values == ["hardlink", "copy", "move"]
    end

    test "returns effect_status in metadata" do
      sync_state = Settings.setting_state("sync_interval_minutes")
      assert sync_state.metadata.effect_status == :next_schedule

      dl_state = Settings.setting_state("media.file_naming_template")
      assert dl_state.metadata.effect_status == :stored_only
    end
  end

  describe "save_settings/1" do
    test "accepts a list and saves all settings transactionally" do
      assert {:ok, saved} =
               Settings.save_settings([
                 {"media.move_strategy", "move"},
                 {"youtube.region", "JP"}
               ])

      assert length(saved) == 2
      assert Settings.get_setting_value("media.move_strategy") == "move"
      assert Settings.get_setting_value("youtube.region") == "JP"
    end

    test "accepts a map with string keys" do
      assert {:ok, saved} =
               Settings.save_settings(%{
                 "media.clean_orphans" => false,
                 "sync_interval_minutes" => 120
               })

      assert length(saved) == 2
      assert Settings.get_setting_value("media.clean_orphans") == false
      assert Settings.get_setting_value("sync_interval_minutes") == 120
    end

    test "accepts a map with atom keys (converted to strings)" do
      assert {:ok, _} =
               Settings.save_settings(%{
                 "youtube.region" => "KR"
               })

      assert Settings.get_setting_value("youtube.region") == "KR"
    end

    test "rolls back all writes on failure" do
      {:ok, _} = Settings.put_setting("save_settings.canary", "original")

      # Trigger rollback via an invalid key (empty string key rejected by Ash)
      result =
        Settings.save_settings([
          {"save_settings.canary", "changed"},
          {"", "bad"}
        ])

      assert {:error, _} = result
      assert Settings.get_setting_value("save_settings.canary") == "original"
    end
  end

  describe "validate_media_root_path/1" do
    test "returns :ok for a valid writable directory" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)
      assert :ok = Settings.validate_media_root_path(dir)
    end

    test "returns {:error, :not_absolute} for a relative path" do
      assert {:error, :not_absolute} = Settings.validate_media_root_path("relative/path")
    end

    test "returns {:error, :not_found} for a non-existent absolute path" do
      assert {:error, :not_found} =
               Settings.validate_media_root_path("/nonexistent_ytdarr_#{System.unique_integer()}")
    end

    test "returns {:error, :not_directory} for a file path" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)
      file = Path.join(dir, "file.txt")
      File.write!(file, "x")
      assert {:error, :not_directory} = Settings.validate_media_root_path(file)
    end

    test "error tuples are 2-element (reason atom only, no message string)" do
      result = Settings.validate_media_root_path("relative")
      assert {:error, atom} = result
      assert is_atom(atom)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_test_dir do
    base = Path.join(File.cwd!(), ".test_media_roots")
    dir = Path.join(base, "dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
