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
