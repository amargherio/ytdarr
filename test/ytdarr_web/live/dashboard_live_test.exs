defmodule YtdarrWeb.DashboardLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  test "renders monitored dashboard content", %{conn: conn} do
    monitored_channel =
      channel_fixture(%{
        name: "Dashboard Monitored #{System.unique_integer([:positive])}",
        is_monitored: true
      })

    _video = video_fixture(%{channel_id: monitored_channel.id, title: "Dashboard Video"})

    hidden_channel =
      channel_fixture(%{name: "Dashboard Hidden #{System.unique_integer([:positive])}"})

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Dashboard"
    assert html =~ "Overview of monitored channels"
    assert has_element?(view, "#dashboard-channels")
    assert has_element?(view, "#infinite-scroll-container input[name='q']")
    assert render(view) =~ monitored_channel.name
    refute render(view) =~ hidden_channel.name
  end
end
