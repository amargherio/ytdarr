defmodule YtdarrWeb.SettingsLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ytdarr.Settings

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

  test "renders the requested tab", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=youtube")

    assert has_element?(lv, "#youtube-form")
    refute has_element?(lv, "#media-form")
  end

  test "saves media settings and manages root folders", %{conn: conn} do
    root_path = unique_path("media-root")
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=media")

    lv
    |> form("#media-form",
      media: %{
        file_naming_template: "%(channel)s/%(upload_date)s-%(title)s.%(ext)s",
        move_strategy: "copy",
        clean_orphans: "true"
      }
    )
    |> render_submit()

    assert render(lv) =~ "Media settings saved"

    assert Settings.get_setting_value("media.file_naming_template") ==
             "%(channel)s/%(upload_date)s-%(title)s.%(ext)s"

    assert Settings.get_setting_value("media.move_strategy") == "copy"
    assert Settings.get_setting_value("media.clean_orphans") == true

    lv
    |> form("#root-folder-form", root_folder: %{path: root_path})
    |> render_submit()

    assert render(lv) =~ "Root folder added"

    root_folder = Enum.find(Settings.list_media_root_folders!(), &(&1.path == root_path))
    assert root_folder
    assert has_element?(lv, "#root-folder-#{root_folder.id}")

    lv
    |> element("#root-folder-#{root_folder.id} button")
    |> render_click()

    assert render(lv) =~ "Root folder removed"
    refute Enum.any?(Settings.list_media_root_folders!(), &(&1.id == root_folder.id))
  end

  test "saves youtube settings", %{conn: conn} do
    api_key = "test-api-key-#{System.unique_integer([:positive])}"
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=youtube")

    lv
    |> form("#youtube-form", youtube: %{api_key: api_key, region: "CA"})
    |> render_submit()

    assert render(lv) =~ "YouTube settings saved"
    assert Settings.get_setting_value("youtube.primary_api_key") == api_key
    assert Settings.get_setting_value("youtube.region") == "CA"
  end

  test "creates and deletes downloader param sets", %{conn: conn} do
    name = "Downloader #{System.unique_integer([:positive])}"
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=downloader")

    lv
    |> form("#param-set-form",
      param_set: %{
        name: name,
        format: "bv*+ba/b",
        extra_args: "--embed-metadata",
        rate_limit_kbps: 900,
        concurrency: 2,
        is_default: "true"
      }
    )
    |> render_submit()

    assert render(lv) =~ "Param set created"

    param_set = Enum.find(Settings.list_yt_dlp_param_sets!(), &(&1.name == name))
    assert param_set
    assert has_element?(lv, "#param-set-#{param_set.id}")

    lv
    |> element("#param-set-#{param_set.id} button")
    |> render_click()

    assert render(lv) =~ "Param set deleted"
    refute Enum.any?(Settings.list_yt_dlp_param_sets!(), &(&1.id == param_set.id))
  end

  defp unique_path(prefix) do
    Path.join(File.cwd!(), "scratch-output/#{prefix}-#{System.unique_integer([:positive])}")
  end
end
