defmodule YtdarrWeb.ChannelLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  @create_attrs %{name: "some name", description: "some description", base_path: "some base_path", url: "some url", external_id: "some external_id", platform: "some platform", avatar_url: "some avatar_url", is_monitored: true, is_monitored_since: "2025-08-27T03:13:00Z", last_checked_at: "2025-08-27T03:13:00Z", generic_video_path: "some generic_video_path"}
  @update_attrs %{name: "some updated name", description: "some updated description", base_path: "some updated base_path", url: "some updated url", external_id: "some updated external_id", platform: "some updated platform", avatar_url: "some updated avatar_url", is_monitored: false, is_monitored_since: "2025-08-28T03:13:00Z", last_checked_at: "2025-08-28T03:13:00Z", generic_video_path: "some updated generic_video_path"}
  @invalid_attrs %{name: nil, description: nil, base_path: nil, url: nil, external_id: nil, platform: nil, avatar_url: nil, is_monitored: false, is_monitored_since: nil, last_checked_at: nil, generic_video_path: nil}
  defp create_channel(_) do
    channel = channel_fixture()

    %{channel: channel}
  end

  describe "Index" do
    setup [:create_channel]

    test "lists all channels", %{conn: conn, channel: channel} do
      {:ok, _index_live, html} = live(conn, ~p"/channels")

      assert html =~ "Listing Channels"
      assert html =~ channel.name
    end

    test "saves new channel", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Channel")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/new")

      assert render(form_live) =~ "New Channel"

      assert form_live
             |> form("#channel-form", channel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#channel-form", channel: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/channels")

      html = render(index_live)
      assert html =~ "Channel created successfully"
      assert html =~ "some name"
    end

    test "updates channel in listing", %{conn: conn, channel: channel} do
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#channels-#{channel.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/#{channel}/edit")

      assert render(form_live) =~ "Edit Channel"

      assert form_live
             |> form("#channel-form", channel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#channel-form", channel: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/channels")

      html = render(index_live)
      assert html =~ "Channel updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes channel in listing", %{conn: conn, channel: channel} do
      {:ok, index_live, _html} = live(conn, ~p"/channels")

      assert index_live |> element("#channels-#{channel.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#channels-#{channel.id}")
    end
  end

  describe "Show" do
    setup [:create_channel]

    test "displays channel", %{conn: conn, channel: channel} do
      {:ok, _show_live, html} = live(conn, ~p"/channels/#{channel}")

      assert html =~ "Show Channel"
      assert html =~ channel.name
    end

    test "updates channel and returns to show", %{conn: conn, channel: channel} do
      {:ok, show_live, _html} = live(conn, ~p"/channels/#{channel}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/#{channel}/edit?return_to=show")

      assert render(form_live) =~ "Edit Channel"

      assert form_live
             |> form("#channel-form", channel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#channel-form", channel: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/channels/#{channel}")

      html = render(show_live)
      assert html =~ "Channel updated successfully"
      assert html =~ "some updated name"
    end
  end
end
