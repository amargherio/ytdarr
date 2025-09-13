defmodule YtdarrWeb.SettingsLiveTest do
  use YtdarrWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders settings tabs", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings")
    assert html =~ "Settings"
    assert html =~ "Media"
    assert html =~ "Profiles"
    assert html =~ "YouTube"
    assert html =~ "Downloader"
  end

  test "create profile flow", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=profiles")

    form = form(lv, "#profile-form", profile: %{name: "TestProf", is_default: true})
    render_submit(form)

    assert render(lv) =~ "Profile created"
    assert render(lv) =~ "TestProf"
  end
end
