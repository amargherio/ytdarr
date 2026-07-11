defmodule YtdarrWeb.DashboardLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  alias Ytdarr.Content

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

  test "search returns matching monitored channels", %{conn: conn} do
    external_id = "UCDASHSEARCH#{System.unique_integer([:positive])}"

    keeper =
      channel_fixture(%{
        name: "DashSearch Keep #{System.unique_integer([:positive])}",
        external_id: external_id,
        is_monitored: true
      })

    excluded =
      channel_fixture(%{
        name: "DashSearch Excluded #{System.unique_integer([:positive])}",
        is_monitored: true
      })

    _video = video_fixture(%{channel_id: keeper.id, title: "Keeper Video"})

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    assert render(view) =~ keeper.name
    assert render(view) =~ excluded.name

    view
    |> element("#infinite-scroll-container input[name='q']")
    |> render_change(%{"q" => "Keep"})

    assert render(view) =~ keeper.name
    refute render(view) =~ excluded.name

    view
    |> element("#infinite-scroll-container input[name='q']")
    |> render_change(%{"q" => external_id})

    assert render(view) =~ keeper.name
    refute render(view) =~ excluded.name
  end

  test "search event with an empty query restores the full list", %{conn: conn} do
    keeper =
      channel_fixture(%{
        name: "DashSearch Reset #{System.unique_integer([:positive])}",
        is_monitored: true
      })

    _video = video_fixture(%{channel_id: keeper.id, title: "Keeper Video"})

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> element("#infinite-scroll-container input[name='q']")
    |> render_change(%{"q" => "no-match"})

    refute render(view) =~ keeper.name

    view
    |> element("#infinite-scroll-container input[name='q']")
    |> render_change(%{"q" => ""})

    assert render(view) =~ keeper.name
  end

  test "load-more is a no-op when end_of_list? is already true", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    before = render(view)
    render_hook(view, "load-more", %{})
    assert render(view) == before
  end

  test "load-more appends the next page of channels", %{conn: conn} do
    # Page size is 25 — create 26 monitored channels so a second page exists.
    unmonitor_seeded_channels()
    unique = System.unique_integer([:positive])

    first_page =
      for i <- 1..25 do
        channel_fixture(%{
          name: "LoadMore First #{unique}-#{i}",
          external_id: "UCLoadMoreFirst#{unique}#{i}",
          is_monitored: true
        })
      end

    next =
      channel_fixture(%{
        name: "LoadMore Next #{unique}",
        external_id: "UCLoadMoreNext#{unique}",
        is_monitored: true
      })

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    rendered = render(view)
    assert Enum.any?(first_page, &String.contains?(rendered, &1.name))
    refute rendered =~ next.name

    render_hook(view, "load-more", %{})

    assert render(view) =~ next.name
    assert has_element?(view, "#infinite-scroll-marker", "No more channels")
  end

  defp unmonitor_seeded_channels do
    Content.list_monitored_channels!()
    |> Enum.each(fn channel ->
      assert {:ok, _channel} = Content.unmonitor_channel(channel)
    end)
  end
end
