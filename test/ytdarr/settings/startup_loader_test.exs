defmodule Ytdarr.Settings.StartupLoaderTest do
  use Ytdarr.DataCase, async: false

  alias Ytdarr.Settings
  alias Ytdarr.Settings.StartupLoader

  setup do
    on_exit(fn -> System.delete_env("YTDARR_YOUTUBE_API_KEY") end)
    System.delete_env("YTDARR_YOUTUBE_API_KEY")
    :ok
  end

  describe "start_link/1" do
    test "starts a transient task linked to the caller" do
      assert {:ok, pid} = StartupLoader.start_link([])
      assert is_pid(pid)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  describe "run/0" do
    test "delegates to load_youtube_api_key without raising" do
      assert :ok = StartupLoader.run()
    end
  end

  describe "load_youtube_api_key/0" do
    test "is a no-op when database value is already set" do
      {:ok, _} = Settings.put_setting("youtube.primary_api_key", "existing_db_key")

      assert :ok = StartupLoader.load_youtube_api_key()

      {:ok, setting} = Settings.get_app_setting_by_key("youtube.primary_api_key")
      assert setting.value == %{"v" => "existing_db_key"}
    end

    test "stores env value when database is empty" do
      delete_existing_setting()
      System.put_env("YTDARR_YOUTUBE_API_KEY", "env_only_key")

      assert :ok = StartupLoader.load_youtube_api_key()

      {:ok, setting} = Settings.get_app_setting_by_key("youtube.primary_api_key")
      assert setting.value == %{"v" => "env_only_key"}
    end

    test "warns and returns :ok when neither database nor env are set" do
      delete_existing_setting()
      assert :ok = StartupLoader.load_youtube_api_key()
      assert {:error, %Ash.Error.Invalid{}} =
               Settings.get_app_setting_by_key("youtube.primary_api_key")
    end

    test "treats an empty-string env value the same as missing" do
      delete_existing_setting()
      System.put_env("YTDARR_YOUTUBE_API_KEY", "")
      assert :ok = StartupLoader.load_youtube_api_key()
      assert {:error, %Ash.Error.Invalid{}} =
               Settings.get_app_setting_by_key("youtube.primary_api_key")
    end
  end

  defp delete_existing_setting do
    case Settings.get_app_setting_by_key("youtube.primary_api_key") do
      {:ok, %{} = setting} -> Settings.destroy_app_setting(setting)
      _ -> :ok
    end
  end
end
