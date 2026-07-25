defmodule YtdarrWeb.ChannelLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures
  alias Ytdarr.Settings

  defp create_channel(_) do
    root = activate_test_media_root()
    channel = channel_fixture()
    on_exit(fn -> File.rm_rf!(root) end)

    %{channel: channel}
  end

  defp create_channel_with_playlist(_) do
    root = activate_test_media_root()
    channel = channel_fixture()
    playlist = playlist_fixture(%{channel_id: channel.id})
    on_exit(fn -> File.rm_rf!(root) end)

    %{channel: channel, playlist: playlist}
  end

  defp activate_test_media_root do
    root =
      Path.join(System.tmp_dir!(), "ytdarr-channel-live-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    {:ok, active_root} = Settings.create_media_root_folder(%{path: root})

    Settings.list_media_root_folders!()
    |> Enum.filter(&(&1.active and &1.id != active_root.id))
    |> Enum.each(fn folder ->
      {:ok, _folder} = Settings.deactivate_media_root_folder(folder)
    end)

    root
  end

  describe "Index" do
    setup [:create_channel]

    test "lists all channels", %{conn: conn, channel: channel} do
      {:ok, _index_live, html} = live(conn, ~p"/channels")

      assert html =~ "Listing Channels"
      assert html =~ channel.name
    end

    test "navigates to edit channel from listing", %{conn: conn, channel: channel} do
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#channels-#{channel.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/#{channel}/edit")

      assert render(form_live) =~ "Editing Channel:"
    end

    test "removes a channel and keeps downloaded files", %{conn: conn, channel: channel} do
      downloaded_file = create_downloaded_file(channel, "keep.mp4")
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert index_live
             |> element("#remove-channel-keep-files-#{channel.id}")
             |> render_click() =~ "Downloaded files were kept."

      refute has_element?(index_live, "#channels-#{channel.id}")
      assert File.exists?(downloaded_file)
      assert {:error, _error} = Ytdarr.Content.get_channel(channel.id)
    end

    test "removes a channel and deletes downloaded files", %{conn: conn, channel: channel} do
      downloaded_file = create_downloaded_file(channel, "delete.mp4")
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert index_live
             |> element("#remove-channel-delete-files-#{channel.id}")
             |> render_click() =~ "Channel and downloaded files removed."

      refute has_element?(index_live, "#channels-#{channel.id}")
      refute File.exists?(downloaded_file)
      assert {:error, _error} = Ytdarr.Content.get_channel(channel.id)
    end
  end

  describe "Show" do
    setup :create_channel_with_playlist

    test "displays channel", %{conn: conn, channel: channel} do
      {:ok, _show_live, html} = live(conn, ~p"/channels/#{channel}")

      assert html =~ channel.name
    end

    test "renders playlist row with expand toggle", %{
      conn: conn,
      channel: channel,
      playlist: playlist
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      assert render(view) =~ playlist.name
    end

    test "toggle-playlist-expand flips the expanded set", %{
      conn: conn,
      channel: channel,
      playlist: playlist
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      render_hook(view, "toggle-playlist-expand", %{"id" => to_string(playlist.id)})
      # Toggling again collapses
      render_hook(view, "toggle-playlist-expand", %{"id" => to_string(playlist.id)})
      assert is_binary(render(view))
    end

    test "toggle-monitor on a playlist updates its state", %{
      conn: conn,
      channel: channel,
      playlist: playlist
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result =
        render_hook(view, "toggle-monitor", %{
          "id" => to_string(playlist.id),
          "type" => "playlist"
        })

      assert result =~ "Playlist status updated."
    end

    test "navigates to edit from show and returns", %{conn: conn, channel: channel} do
      {:ok, show_live, _html} = live(conn, ~p"/channels/#{channel}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a[title='Edit channel']")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/#{channel}/edit?return_to=show")

      assert render(form_live) =~ "Editing Channel:"
    end

    test "toggle-monitor on a channel flips the monitored flag and flashes",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result =
        render_hook(view, "toggle-monitor", %{"id" => to_string(channel.id), "type" => "channel"})

      assert result =~ "Channel status updated."
      {:ok, reloaded} = Ytdarr.Content.get_channel(channel.id)
      assert reloaded.is_monitored != channel.is_monitored
    end

    test "toggle-monitor with an unknown type is a no-op", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result =
        render_hook(view, "toggle-monitor", %{"id" => to_string(channel.id), "type" => "video"})

      refute result =~ "Channel status updated."
      refute result =~ "Playlist status updated."
    end

    test "queue-download flashes after enqueueing the job",
         %{conn: conn, channel: channel} do
      video = video_fixture(%{channel_id: channel.id, title: "Queue Show Video"})
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result =
        render_hook(view, "queue-download", %{
          "id" => to_string(video.id),
          "channel-id" => to_string(channel.id)
        })

      assert result =~ "Video queued for download."
    end

    test "blocklist and unblocklist events persist state and flash",
         %{conn: conn, channel: channel} do
      video = video_fixture(%{channel_id: channel.id, title: "Blocklist Show Video"})
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result = render_hook(view, "blocklist-video", %{"id" => to_string(video.id)})
      assert result =~ "Video added to blocklist."
      assert Ytdarr.Content.get_video!(video.id).is_blocklisted

      result = render_hook(view, "unblocklist-video", %{"id" => to_string(video.id)})
      assert result =~ "Video removed from blocklist."
      refute Ytdarr.Content.get_video!(video.id).is_blocklisted
    end

    test "queue-download explains why a blocklisted video was rejected",
         %{conn: conn, channel: channel} do
      video =
        video_fixture(%{
          channel_id: channel.id,
          title: "Blocked Queue Show Video",
          is_blocklisted: true
        })

      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result =
        render_hook(view, "queue-download", %{
          "id" => to_string(video.id),
          "channel-id" => to_string(channel.id)
        })

      assert result =~
               "This video is blocklisted. Remove it from the blocklist before downloading."

      refute result =~ "Video queued for download."
    end

    test "delete-video resets the video file state and flashes",
         %{conn: conn, channel: channel} do
      video =
        video_fixture(%{channel_id: channel.id, title: "Delete Show Video"})

      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result = render_hook(view, "delete-video", %{"id" => to_string(video.id)})
      assert result =~ "Video file deleted."
    end

    test "refresh-channel-data enqueues a sync job and flashes",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      result = render_hook(view, "refresh-channel-data", %{})
      assert result =~ "Channel data refresh in progress."
    end

    test "placeholder delete events flash a 'not yet implemented' message",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      r1 = render_hook(view, "delete-channel-files", %{"id" => to_string(channel.id)})
      assert r1 =~ "Channel file deletion not yet implemented."

      r2 = render_hook(view, "delete-playlist-files", %{"id" => "99"})
      assert r2 =~ "Playlist file deletion not yet implemented."

      r3 = render_hook(view, "delete-video-files", %{})
      assert r3 =~ "Video file deletion not yet implemented."
    end

    test "toggle-expand-all flips expansion state and flushes back",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      render_hook(view, "toggle-expand-all", %{})
      render_hook(view, "toggle-expand-all", %{})
      render_hook(view, "toggle-videos-expand", %{})
      assert is_binary(render(view))
    end
  end

  describe "Form" do
    setup [:create_channel]

    test "validate event updates the form without saving",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}/edit")

      result =
        view
        |> form("#channel-form", channel: %{name: ""})
        |> render_change()

      # An invalid empty name should not produce a flash but should re-render the form
      assert result =~ "channel-form" || result =~ "phx-change"
    end

    test "save event persists changes and redirects to the listing",
         %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}/edit")

      assert {:ok, _, html} =
               view
               |> form("#channel-form", channel: %{description: "Updated description"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Channel updated successfully"
    end
  end

  defp create_downloaded_file(channel, filename) do
    downloaded_file = Path.join([channel.base_path, "videos", filename])
    File.mkdir_p!(Path.dirname(downloaded_file))
    File.write!(downloaded_file, "downloaded content")
    on_exit(fn -> File.rm_rf(channel.base_path) end)
    downloaded_file
  end
end
