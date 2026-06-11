defmodule Ytdarr.Content.PlaylistTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Ytdarr.ContentFixtures

  alias Ash.Error.Changes.Required
  alias Ytdarr.Content
  alias Ytdarr.ObanWorkers.SyncWorker

  describe "create_playlist/2" do
    test "creates with valid attributes" do
      channel = channel_fixture()
      attrs = playlist_attrs()

      assert {:ok, playlist} = Content.create_playlist(channel.id, attrs)
      assert playlist.channel_id == channel.id
      assert playlist.name == attrs.name
      assert playlist.external_id == attrs.external_id
      assert playlist.url == attrs.url
    end

    test "fails when required attributes or channel_id are nil" do
      channel = channel_fixture()
      attrs = playlist_attrs()

      for field <- [:name, :external_id, :url] do
        result = Content.create_playlist(channel.id, Map.put(attrs, field, nil))
        assert_required_error(result, field, :attribute)
      end

      result = Content.create_playlist(nil, attrs)
      assert_required_error(result, :channel_id, :argument)
    end
  end

  describe "SetMonitoredTimestamp" do
    test "sets is_monitored_since when created as monitored" do
      playlist = playlist_fixture(%{is_monitored: true})

      assert playlist.is_monitored
      assert %DateTime{} = playlist.is_monitored_since
    end

    test "clears is_monitored_since when unmonitored" do
      playlist = playlist_fixture(%{is_monitored: true})

      assert {:ok, updated_playlist} = Content.unmonitor_playlist(playlist)

      refute updated_playlist.is_monitored
      assert is_nil(updated_playlist.is_monitored_since)
    end

    test "leaves is_monitored_since untouched when monitor state is unchanged" do
      playlist = playlist_fixture(%{is_monitored: true})
      original_since = playlist.is_monitored_since

      assert {:ok, updated} =
               Content.update_playlist(playlist, %{description: "unchanged monitor"})

      assert updated.is_monitored
      assert updated.is_monitored_since == original_since
    end
  end

  describe "SetDownloadPath" do
    test "sets download_path from channel base_path and sanitized name on update" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id, name: "Initial Name"})

      # Reload with channel association so the change sees it in data
      {:ok, loaded} = Ash.load(playlist, :channel)

      assert {:ok, updated} = Content.update_playlist(loaded, %{name: "My Cool Playlist! 2025"})

      assert updated.download_path ==
               Path.join(channel.base_path, "my_cool_playlist_2025")
    end

    test "leaves download_path nil on initial create (channel not in data yet)" do
      channel = channel_fixture()

      {:ok, playlist} =
        Content.create_playlist(channel.id, %{
          name: "Detached Playlist #{System.unique_integer([:positive])}",
          external_id: "PLDETACHED#{System.unique_integer([:positive])}",
          url: "https://www.youtube.com/playlist?list=PLDETACHED",
          video_count: 0
        })

      assert is_nil(playlist.download_path)
    end
  end

  describe "toggle_playlist_monitor/1" do
    test "toggles monitoring and only queues a sync job when enabling" do
      playlist = playlist_fixture()
      args = %{"source_type" => "playlist", "source_id" => playlist.id}

      assert [] == all_enqueued(worker: SyncWorker, args: args)

      assert {:ok, monitored_playlist} = Content.toggle_playlist_monitor(playlist)
      assert monitored_playlist.is_monitored
      assert %DateTime{} = monitored_playlist.is_monitored_since
      assert_enqueued(worker: SyncWorker, args: args)

      assert {:ok, unmonitored_playlist} = Content.toggle_playlist_monitor(monitored_playlist)
      refute unmonitored_playlist.is_monitored
      assert is_nil(unmonitored_playlist.is_monitored_since)
      assert length(all_enqueued(worker: SyncWorker, args: args)) == 1
    end
  end

  describe "monitor_playlist/1" do
    test "queues a SyncWorker job" do
      playlist = playlist_fixture()
      args = %{"source_type" => "playlist", "source_id" => playlist.id}

      assert {:ok, monitored_playlist} = Content.monitor_playlist(playlist)

      assert monitored_playlist.is_monitored
      assert %DateTime{} = monitored_playlist.is_monitored_since
      assert_enqueued(worker: SyncWorker, args: args)
    end
  end

  describe "list_monitored_playlists/0" do
    test "returns only monitored playlists" do
      monitored_playlist = playlist_fixture(%{is_monitored: true})
      unmonitored_playlist = playlist_fixture(%{is_monitored: false})

      monitored_ids =
        Content.list_monitored_playlists!()
        |> Enum.map(& &1.id)

      assert monitored_playlist.id in monitored_ids
      refute unmonitored_playlist.id in monitored_ids
    end
  end

  describe "mark_playlist_checked/1" do
    test "sets last_checked_at" do
      playlist = playlist_fixture()
      assert is_nil(playlist.last_checked_at)

      assert {:ok, checked_playlist} = Content.mark_playlist_checked(playlist)
      assert %DateTime{} = checked_playlist.last_checked_at
    end
  end

  defp playlist_attrs(overrides \\ %{}) do
    unique_id = System.unique_integer([:positive])

    Enum.into(overrides, %{
      name: "Test Playlist #{unique_id}",
      external_id: "PL#{unique_id}",
      url: "https://www.youtube.com/playlist?list=PL#{unique_id}",
      description: "Playlist description",
      video_count: 12
    })
  end

  defp assert_required_error({:error, %Ash.Error.Invalid{errors: errors}}, field, type) do
    assert Enum.any?(errors, fn
             %Required{field: ^field, type: ^type} -> true
             _ -> false
           end)
  end
end
