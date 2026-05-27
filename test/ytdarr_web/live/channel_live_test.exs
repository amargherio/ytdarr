defmodule YtdarrWeb.ChannelLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

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
    setup [:create_channel]

    test "displays channel", %{conn: conn, channel: channel} do
      {:ok, _show_live, html} = live(conn, ~p"/channels/#{channel}")

      assert html =~ channel.name
    end

    test "navigates to edit from show and returns", %{conn: conn, channel: channel} do
      {:ok, show_live, _html} = live(conn, ~p"/channels/#{channel}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit channel")
               |> render_click()
               |> follow_redirect(conn, ~p"/channels/#{channel}/edit?return_to=show")

      assert render(form_live) =~ "Editing Channel:"
    end
  end
end
