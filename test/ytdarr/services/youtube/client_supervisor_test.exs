defmodule Ytdarr.Services.YouTube.ClientSupervisorTest do
  use Ytdarr.DataCase, async: false

  alias Ytdarr.Services.YouTube.ClientSupervisor
  alias Ytdarr.Settings

  describe "process lifecycle" do
    test "is registered under its module name and alive" do
      pid = Process.whereis(ClientSupervisor)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "get_api_key/0" do
    setup do
      original = Settings.get_setting_value("youtube.primary_api_key")
      System.delete_env("YTDARR_YOUTUBE_API_KEY")

      on_exit(fn ->
        if original do
          Settings.put_setting("youtube.primary_api_key", original)
        end

        System.delete_env("YTDARR_YOUTUBE_API_KEY")
      end)

      :ok
    end

    test "returns the persisted API key" do
      Settings.put_setting("youtube.primary_api_key", "fixture-api-key")
      assert ClientSupervisor.get_api_key() == "fixture-api-key"
    end

    test "prefers an environment override over the persisted value" do
      Settings.put_setting("youtube.primary_api_key", "db-value")
      System.put_env("YTDARR_YOUTUBE_API_KEY", "env-value")
      assert ClientSupervisor.get_api_key() == "env-value"
    end
  end

  describe "get_client/0" do
    test "returns a usable Req struct each call" do
      client = ClientSupervisor.get_client()
      assert %Req.Request{} = client
      assert client.options[:base_url] == "https://www.googleapis.com/youtube/v3"
    end
  end

  describe "refresh_client/0" do
    test "returns :ok and continues to yield Req clients afterward" do
      assert :ok = ClientSupervisor.refresh_client()
      assert %Req.Request{} = ClientSupervisor.get_client()
    end
  end
end
