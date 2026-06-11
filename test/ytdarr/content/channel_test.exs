defmodule Ytdarr.Content.ChannelTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ash.Error.Changes.{InvalidAttribute, Required}
  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.SyncWorker
  alias Ytdarr.Settings

  describe "create_channel/1" do
    test "creates with valid attributes" do
      attrs = channel_attrs()

      assert {:ok, channel} = Content.create_channel(attrs)
      assert channel.name == attrs.name
      assert channel.external_id == attrs.external_id
      assert channel.url == attrs.url
      assert channel.platform == attrs.platform
    end

    test "fails when required attributes are nil" do
      attrs = channel_attrs()

      for field <- [:name, :external_id, :url, :platform] do
        result = Content.create_channel(Map.put(attrs, field, nil))
        assert_required_error(result, field)
      end
    end
  end

  describe "SetFilesystemPaths" do
    test "sets base_path and generic_video_path from the sanitized name" do
      media_root = Settings.get_app_media_root_folder!()

      assert {:ok, channel} =
               Content.create_channel(
                 channel_attrs(%{
                   name: "My Fancy Channel!"
                 })
               )

      assert channel.base_path == Path.join(media_root, "my_fancy_channel")
      assert channel.generic_video_path == Path.join(channel.base_path, "videos")
    end
  end

  describe "SetMonitoredTimestamp" do
    test "sets is_monitored_since when created as monitored" do
      channel = channel_fixture(%{is_monitored: true})

      assert channel.is_monitored
      assert %DateTime{} = channel.is_monitored_since
    end

    test "clears is_monitored_since when unmonitored" do
      channel = channel_fixture(%{is_monitored: true})

      assert {:ok, updated_channel} = Content.unmonitor_channel(channel)

      refute updated_channel.is_monitored
      assert is_nil(updated_channel.is_monitored_since)
    end

    test "leaves is_monitored_since untouched when neither monitored nor unmonitored transitions" do
      channel = channel_fixture(%{is_monitored: true})
      original_since = channel.is_monitored_since

      assert {:ok, updated} = Content.update_channel(channel, %{description: "unchanged monitor"})
      assert updated.is_monitored
      assert updated.is_monitored_since == original_since
    end
  end

  describe "toggle_channel_monitor/1" do
    test "toggles monitoring and only queues a sync job when enabling" do
      channel = channel_fixture()
      args = %{"source_type" => "channel", "source_id" => channel.id}

      assert [] == all_enqueued(worker: SyncWorker, args: args)

      assert {:ok, monitored_channel} = Content.toggle_channel_monitor(channel)
      assert monitored_channel.is_monitored
      assert %DateTime{} = monitored_channel.is_monitored_since
      assert_enqueued(worker: SyncWorker, args: args)

      assert {:ok, unmonitored_channel} = Content.toggle_channel_monitor(monitored_channel)
      refute unmonitored_channel.is_monitored
      assert is_nil(unmonitored_channel.is_monitored_since)
      assert length(all_enqueued(worker: SyncWorker, args: args)) == 1
    end
  end

  describe "monitor_channel/1" do
    test "queues a SyncWorker job" do
      channel = channel_fixture()
      args = %{"source_type" => "channel", "source_id" => channel.id}

      assert {:ok, monitored_channel} = Content.monitor_channel(channel)

      assert monitored_channel.is_monitored
      assert %DateTime{} = monitored_channel.is_monitored_since
      assert_enqueued(worker: SyncWorker, args: args)
    end
  end

  describe "ValidUrl" do
    test "accepts valid urls" do
      assert {:ok, channel} =
               Content.create_channel(
                 channel_attrs(%{url: "https://www.youtube.com/channel/UCvalid123"})
               )

      assert channel.url == "https://www.youtube.com/channel/UCvalid123"
    end

    test "rejects urls without a scheme" do
      result = Content.create_channel(channel_attrs(%{url: "youtube.com/channel/no-scheme"}))

      assert_invalid_attribute_error(result, :url, "must have a scheme (http or https)")
    end

    test "rejects urls without a host" do
      result = Content.create_channel(channel_attrs(%{url: "http:/missing-host"}))

      assert_invalid_attribute_error(result, :url, "must have a host")
    end

    test "rejects urls with a non-http(s) scheme" do
      result = Content.create_channel(channel_attrs(%{url: "ftp://example.com/feed"}))

      assert_invalid_attribute_error(result, :url, "must be a valid http or https URL")
    end
  end

  describe "list_monitored_channels/0" do
    test "returns only monitored channels" do
      monitored_channel = channel_fixture(%{is_monitored: true})
      unmonitored_channel = channel_fixture(%{is_monitored: false})

      monitored_ids =
        Content.list_monitored_channels!()
        |> Enum.map(& &1.id)

      assert monitored_channel.id in monitored_ids
      refute unmonitored_channel.id in monitored_ids
    end
  end

  describe "mark_channel_checked/1" do
    test "sets last_checked_at" do
      channel = channel_fixture()
      assert is_nil(channel.last_checked_at)

      assert {:ok, checked_channel} = Content.mark_channel_checked(channel)
      assert %DateTime{} = checked_channel.last_checked_at
    end
  end

  describe "destroy_channel/1" do
    test "removes the channel directory from disk" do
      root_path = configure_local_media_root()
      on_exit(fn -> File.rm_rf(root_path) end)

      channel = channel_fixture(%{name: "Cleanup Channel #{System.unique_integer([:positive])}"})
      nested_file = Path.join([channel.base_path, "videos", "sample.txt"])

      File.mkdir_p!(Path.dirname(nested_file))
      File.write!(nested_file, "cleanup me")

      assert File.exists?(nested_file)
      assert :ok = Content.destroy_channel(channel)
      refute File.exists?(channel.base_path)
    end
  end

  defp channel_attrs(overrides \\ %{}) do
    unique_id = System.unique_integer([:positive])

    Enum.into(overrides, %{
      name: "Test Channel #{unique_id}",
      external_id: "UCCHANNEL#{unique_id}",
      url: "https://www.youtube.com/channel/UCCHANNEL#{unique_id}",
      platform: "YouTube"
    })
  end

  defp configure_local_media_root do
    root_path =
      Path.join([
        File.cwd!(),
        "test",
        "scratch",
        "channel_cleanup_#{System.unique_integer([:positive])}"
      ])

    Settings.list_active_media_folders!()
    |> Enum.each(&Settings.deactivate_media_root_folder!/1)

    File.mkdir_p!(root_path)
    Settings.create_media_root_folder!(%{path: root_path, purpose: "videos", active: true})

    root_path
  end

  defp assert_required_error({:error, %Ash.Error.Invalid{errors: errors}}, field) do
    assert Enum.any?(errors, fn
             %Required{field: ^field} -> true
             _ -> false
           end)
  end

  defp assert_invalid_attribute_error(
         {:error, %Ash.Error.Invalid{errors: errors}},
         field,
         message
       ) do
    assert Enum.any?(errors, fn
             %InvalidAttribute{field: ^field, message: ^message} -> true
             _ -> false
           end)
  end
end
