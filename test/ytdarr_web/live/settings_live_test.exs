defmodule YtdarrWeb.SettingsLiveTest do
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ytdarr.Settings

  test "renders the category navigation and defaults to media management", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#settings-category-navigation")
    assert has_element?(view, "#settings-category-media[aria-current='page']")
    assert has_element?(view, "#settings-section-media")
    assert has_element?(view, "#media-form")
  end

  test "supports canonical categories and legacy tab links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")

    assert has_element?(view, "#settings-category-youtube[aria-current='page']")
    assert has_element?(view, "#youtube-form")
    refute has_element?(view, "#media-form")

    {:ok, legacy_view, _html} = live(conn, ~p"/settings?tab=downloader")
    assert has_element?(legacy_view, "#settings-section-download")
    assert has_element?(legacy_view, "#settings-category-download[aria-current='page']")
  end

  test "shows and clears the section save bar around media changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?category=media")

    refute has_element?(view, "#settings-save-bar")

    view
    |> form("#media-form",
      media: %{
        file_naming_template: "%(channel)s/%(upload_date)s-%(title)s.%(ext)s",
        move_strategy: "copy",
        clean_orphans: "true"
      }
    )
    |> render_change()

    assert has_element?(view, "#settings-save-bar")

    view
    |> form("#media-form",
      media: %{
        file_naming_template: "%(channel)s/%(upload_date)s-%(title)s.%(ext)s",
        move_strategy: "copy",
        clean_orphans: "true"
      }
    )
    |> render_submit()

    refute has_element?(view, "#settings-save-bar")

    assert Settings.get_setting_value("media.file_naming_template") ==
             "%(channel)s/%(upload_date)s-%(title)s.%(ext)s"

    assert Settings.get_setting_value("media.move_strategy") == "copy"
    assert Settings.get_setting_value("media.clean_orphans") == true
  end

  test "creates and edits a validated media root folder", %{conn: conn} do
    root_path = create_writable_directory("media-root")
    updated_path = create_writable_directory("media-root-updated")
    {:ok, view, _html} = live(conn, ~p"/settings?category=media")

    view
    |> element("#add-root-folder")
    |> render_click()

    assert has_element?(view, "#settings-resource-editor")

    view
    |> form("#settings-editor-form",
      root_folder: %{path: root_path, purpose: "videos", active: "true"}
    )
    |> render_submit()

    root_folder = Enum.find(Settings.list_media_root_folders!(), &(&1.path == root_path))
    assert root_folder
    assert has_element?(view, "#root-folder-#{root_folder.id}")

    view
    |> element("#edit-root-folder-#{root_folder.id}")
    |> render_click()

    view
    |> form("#settings-editor-form",
      root_folder: %{path: updated_path, purpose: "videos", active: "true"}
    )
    |> render_submit()

    assert Settings.get_media_root_folder!(root_folder.id).path == updated_path
  end

  test "creates, edits, and selects a quality profile", %{conn: conn} do
    name = "Profile #{System.unique_integer([:positive])}"
    renamed = "#{name} Updated"
    {:ok, view, _html} = live(conn, ~p"/settings?category=profiles")

    view
    |> element("#add-quality-profile")
    |> render_click()

    view
    |> form("#settings-editor-form",
      profile: %{
        name: name,
        max_height: 1080,
        max_bitrate_kbps: 8_000,
        preferred_codecs: "av1, h264",
        allow_hdr: "true",
        is_default: "false"
      }
    )
    |> render_submit()

    profile = Enum.find(Settings.list_quality_profiles!(), &(&1.name == name))
    assert profile

    view
    |> element("#edit-profile-#{profile.id}")
    |> render_click()

    view
    |> form("#settings-editor-form",
      profile: %{
        name: renamed,
        max_height: 720,
        max_bitrate_kbps: 4_000,
        preferred_codecs: "h264",
        allow_hdr: "false"
      }
    )
    |> render_submit()

    assert Settings.get_quality_profile!(profile.id).name == renamed

    view
    |> element("#default-profile-#{profile.id}")
    |> render_click()

    assert Settings.get_quality_profile!(profile.id).is_default
  end

  test "creates, edits, and selects a yt-dlp parameter set", %{conn: conn} do
    name = "Parameter Set #{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/settings?category=download")

    view
    |> element("#add-param-set")
    |> render_click()

    view
    |> form("#settings-editor-form",
      param_set: %{
        name: name,
        format: "bv*+ba/b",
        extra_args: "--embed-metadata",
        rate_limit_kbps: 900,
        concurrency: 2,
        is_default: "false"
      }
    )
    |> render_submit()

    param_set = Enum.find(Settings.list_yt_dlp_param_sets!(), &(&1.name == name))
    assert param_set

    view
    |> element("#edit-param-set-#{param_set.id}")
    |> render_click()

    view
    |> form("#settings-editor-form",
      param_set: %{
        name: name,
        format: "best",
        extra_args: "--embed-metadata --write-description",
        rate_limit_kbps: 1_200,
        concurrency: 3
      }
    )
    |> render_submit()

    assert Settings.get_yt_dlp_param_set!(param_set.id).format == "best"

    view
    |> element("#default-param-set-#{param_set.id}")
    |> render_click()

    assert Settings.get_yt_dlp_param_set!(param_set.id).is_default
  end

  test "saves the automatic sync interval", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?category=general")

    view
    |> form("#general-form", general: %{sync_interval_minutes: 45})
    |> render_submit()

    assert Settings.get_setting_value("sync_interval_minutes") == 45
    assert has_element?(view, "#general-sync-interval")
  end

  test "saves a browser-managed YouTube API key", %{conn: conn} do
    previous_api_key = System.get_env("YTDARR_YOUTUBE_API_KEY")
    System.delete_env("YTDARR_YOUTUBE_API_KEY")

    on_exit(fn ->
      if previous_api_key do
        System.put_env("YTDARR_YOUTUBE_API_KEY", previous_api_key)
      else
        System.delete_env("YTDARR_YOUTUBE_API_KEY")
      end
    end)

    api_key = "test-api-key-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")

    view
    |> form("#youtube-form", youtube: %{api_key: api_key, region: "CA"})
    |> render_submit()

    assert Settings.get_setting_value("youtube.primary_api_key") == api_key
    assert Settings.get_setting_value("youtube.region") == "CA"
  end

  test "shows honest effect labels and read-only system information", %{conn: conn} do
    {:ok, media_view, _html} = live(conn, ~p"/settings?category=media")
    assert has_element?(media_view, "#media-file-naming-template", "Stored only")

    {:ok, system_view, _html} = live(conn, ~p"/settings?category=system")
    assert has_element?(system_view, "#system-information")
    assert has_element?(system_view, "#settings-section-system", "Restart required")
    assert render(system_view) =~ "Local-network access"
  end

  defp create_writable_directory(prefix) do
    path =
      Path.join(
        File.cwd!(),
        "scratch-output/#{prefix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
