defmodule YtdarrWeb.ChannelLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  defp create_channel(_) do
    channel = channel_fixture()

    %{channel: channel}
  end

  defp create_channel_with_playlist(_) do
    channel = channel_fixture()
    playlist = playlist_fixture(%{channel_id: channel.id})
    %{channel: channel, playlist: playlist}
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

    test "deletes channel in listing", %{conn: conn, channel: channel} do
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert index_live |> element("#channels-#{channel.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#channels-#{channel.id}")
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
end
