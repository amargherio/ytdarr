defmodule YtdarrWeb.SettingsLiveTest do
  use YtdarrWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Ytdarr.Settings

  defmodule CredentialPlug do
    @moduledoc false

    def init(opts), do: opts

    def call(conn, opts) do
      conn = Plug.Conn.fetch_query_params(conn)
      send(Keyword.fetch!(opts, :test_pid), {:credential_request, conn.params["key"]})
      {status, body} = Keyword.get(opts, :response, {200, %{"items" => []}})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  test "renders the category navigation and defaults to media management", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#settings-category-navigation")
    assert has_element?(view, "#settings-category-media[aria-current='page']")
    assert has_element?(view, "#settings-section-media")
    assert has_element?(view, "#media-form")
    assert has_element?(view, "#settings-section-media h2", "Media Management")
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
        clean_orphans: "true",
        owner_group: current_group_name(),
        file_mode: "664",
        directory_mode: "0775"
      }
    )
    |> render_change()

    assert has_element?(view, "#settings-save-bar")

    view
    |> form("#media-form",
      media: %{
        file_naming_template: "%(channel)s/%(upload_date)s-%(title)s.%(ext)s",
        move_strategy: "copy",
        clean_orphans: "true",
        owner_group: current_group_name(),
        file_mode: "664",
        directory_mode: "0775"
      }
    )
    |> render_submit()

    refute has_element?(view, "#settings-save-bar")

    assert Settings.get_setting_value("media.file_naming_template") ==
             "%(channel)s/%(upload_date)s-%(title)s.%(ext)s"

    assert Settings.get_setting_value("media.move_strategy") == "copy"
    assert Settings.get_setting_value("media.clean_orphans") == true
    assert Settings.get_setting_value("media.owner_group") == current_group_name()
    assert Settings.get_setting_value("media.file_mode") == "0664"
    assert Settings.get_setting_value("media.directory_mode") == "0775"
  end

  test "queues permission normalization explicitly", %{conn: conn} do
    assert {:ok, _} = Settings.put_setting("media.owner_group", current_group_name())
    {:ok, view, _html} = live(conn, ~p"/settings?category=media")

    view
    |> element("#apply-media-permissions")
    |> render_click()

    assert has_element?(view, "#apply-media-permissions[disabled]")

    assert Ytdarr.Repo.exists?(
             from(job in Oban.Job,
               where: job.worker == "Ytdarr.ObanWorkers.MediaPermissionsWorker"
             )
           )
  end

  test "rejects invalid media permission modes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?category=media")

    view
    |> form("#media-form",
      media: %{
        file_naming_template: "%(channel)s/%(title)s.%(ext)s",
        move_strategy: "copy",
        clean_orphans: "true",
        owner_group: current_group_name(),
        file_mode: "0888",
        directory_mode: "0755"
      }
    )
    |> render_submit()

    assert render(view) =~ "File mode must contain three octal digits"
    refute Settings.get_setting_value("media.file_mode") == "0888"
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
      root_folder: %{path: updated_path, purpose: "videos"}
    )
    |> render_submit()

    assert Settings.get_media_root_folder!(root_folder.id).path == updated_path
    assert has_element?(view, "#root-folder-#{root_folder.id}", "Writable")
  end

  defp current_group_name do
    {group, 0} = System.cmd("id", ["-gn"])
    String.trim(group)
  end

  test "preserves the root editor and shows path errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?category=media")

    view
    |> element("#add-root-folder")
    |> render_click()

    view
    |> form("#settings-editor-form",
      root_folder: %{
        path: "/missing-ytdarr-root-#{System.unique_integer([:positive])}",
        purpose: "videos",
        active: "true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#settings-resource-editor")
    assert has_element?(view, "#settings-editor-form", "path does not exist on disk")
    assert has_element?(view, ".max-lg\\:hidden")

    view
    |> element("#validate-root-path")
    |> render_click()

    assert has_element?(view, "#root-path-result", "does not exist")
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
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")

    api_key = "test-api-key-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")

    view
    |> form("#youtube-form", youtube: %{api_key: api_key, region: "CA"})
    |> render_submit()

    assert Settings.get_setting_value("youtube.primary_api_key") == api_key
    assert Settings.get_setting_value("youtube.region") == "CA"
  end

  test "tests a pending YouTube key and throttles repeated requests", %{conn: conn} do
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")
    configure_credential_client()

    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")
    pending_key = "pending-key-#{System.unique_integer([:positive])}"

    view
    |> form("#youtube-form", youtube: %{api_key: pending_key, region: "US"})
    |> render_change()

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    assert_receive {:credential_request, ^pending_key}
    assert has_element?(view, "#youtube-credential-result", "Credentials are valid")

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    assert has_element?(view, "#youtube-credential-result", "Wait a few seconds")
    refute_receive {:credential_request, _}
  end

  test "tests the effective saved key without rendering it", %{conn: conn} do
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")
    configure_credential_client()

    saved_key = "saved-key-#{System.unique_integer([:positive])}"
    {:ok, _setting} = Settings.put_setting("youtube.primary_api_key", saved_key)
    {:ok, view, html} = live(conn, ~p"/settings?category=youtube")

    refute html =~ saved_key

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    assert_receive {:credential_request, ^saved_key}
    refute render(view) =~ saved_key
  end

  test "shows an actionable empty credential result", %{conn: conn} do
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")

    case Settings.get_app_setting_by_key("youtube.primary_api_key") do
      {:ok, nil} -> :ok
      {:ok, setting} -> Settings.destroy_app_setting!(setting)
      {:error, %Ash.Error.Invalid{}} -> :ok
    end

    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    assert has_element?(
             view,
             "#youtube-credential-result",
             "Configure an API key before testing."
           )
  end

  test "renders environment-managed credentials as read-only", %{conn: conn} do
    preserve_youtube_environment()
    configure_credential_client()
    environment_key = "environment-secret"
    System.put_env("YTDARR_YOUTUBE_API_KEY", environment_key)

    {:ok, view, html} = live(conn, ~p"/settings?category=youtube")

    assert has_element?(view, "#youtube_api_key[disabled]")
    refute has_element?(view, "#clear-youtube-api-key")
    assert html =~ "Managed by YTDARR_YOUTUBE_API_KEY"
    refute html =~ environment_key

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    assert_receive {:credential_request, ^environment_key}
  end

  test "clears a browser-managed YouTube key", %{conn: conn} do
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")

    stored_key = "clear-me-#{System.unique_integer([:positive])}"
    {:ok, _setting} = Settings.put_setting("youtube.primary_api_key", stored_key)
    {:ok, view, html} = live(conn, ~p"/settings?category=youtube")

    refute html =~ stored_key

    view
    |> element("#clear-youtube-api-key")
    |> render_click()

    assert Settings.get_setting_value("youtube.primary_api_key") == nil
    refute has_element?(view, "#clear-youtube-api-key")
  end

  test "maps rejected credentials to safe corrective guidance", %{conn: conn} do
    preserve_youtube_environment()
    System.delete_env("YTDARR_YOUTUBE_API_KEY")

    configure_credential_client(
      {403,
       %{
         "error" => %{
           "message" => "API key not valid",
           "errors" => [%{"reason" => "keyInvalid"}]
         }
       }}
    )

    {:ok, view, _html} = live(conn, ~p"/settings?category=youtube")
    rejected_key = "rejected-key"

    view
    |> form("#youtube-form", youtube: %{api_key: rejected_key, region: "US"})
    |> render_change()

    view
    |> element("#test-youtube-credentials")
    |> render_click()

    result_html = view |> element("#youtube-credential-result") |> render()
    assert result_html =~ "YouTube rejected this API key"
    refute result_html =~ rejected_key
  end

  test "disables destructive actions for protected records", %{conn: conn} do
    {:ok, profile} =
      Settings.create_quality_profile(%{
        name: "Protected profile #{System.unique_integer([:positive])}",
        is_default: true
      })

    {:ok, param_set} =
      Settings.create_yt_dlp_param_set(%{
        name: "Protected set #{System.unique_integer([:positive])}",
        is_default: true
      })

    root = ensure_single_active_root()

    {:ok, media_view, _html} = live(conn, ~p"/settings?category=media")
    assert has_element?(media_view, "#toggle-root-folder-#{root.id}[disabled]")
    assert has_element?(media_view, "#delete-root-folder-#{root.id}[disabled]")

    {:ok, profile_view, _html} = live(conn, ~p"/settings?category=profiles")
    assert has_element?(profile_view, "#delete-profile-#{profile.id}[disabled]")

    {:ok, download_view, _html} = live(conn, ~p"/settings?category=download")
    assert has_element?(download_view, "#delete-param-set-#{param_set.id}[disabled]")
  end

  test "deletes non-protected collection records", %{conn: conn} do
    _protected_root = ensure_single_active_root()
    root_path = create_writable_directory("deletable-root")
    {:ok, root} = Settings.create_media_root_folder(%{path: root_path})

    {:ok, profile} =
      Settings.create_quality_profile(%{
        name: "Deletable profile #{System.unique_integer([:positive])}"
      })

    {:ok, param_set} =
      Settings.create_yt_dlp_param_set(%{
        name: "Deletable set #{System.unique_integer([:positive])}"
      })

    {:ok, media_view, _html} = live(conn, ~p"/settings?category=media")

    media_view
    |> element("#delete-root-folder-#{root.id}")
    |> render_click()

    refute Enum.any?(Settings.list_media_root_folders!(), &(&1.id == root.id))

    {:ok, profile_view, _html} = live(conn, ~p"/settings?category=profiles")

    profile_view
    |> element("#delete-profile-#{profile.id}")
    |> render_click()

    refute Enum.any?(Settings.list_quality_profiles!(), &(&1.id == profile.id))

    {:ok, download_view, _html} = live(conn, ~p"/settings?category=download")

    download_view
    |> element("#delete-param-set-#{param_set.id}")
    |> render_click()

    refute Enum.any?(Settings.list_yt_dlp_param_sets!(), &(&1.id == param_set.id))
  end

  test "rejects a non-positive sync interval without changing the saved value", %{conn: conn} do
    {:ok, _setting} = Settings.put_setting("sync_interval_minutes", 45)
    {:ok, view, _html} = live(conn, ~p"/settings?category=general")

    view
    |> form("#general-form", general: %{sync_interval_minutes: 0})
    |> render_submit()

    assert render(view) =~ "Sync interval must be a positive whole number."
    assert Settings.get_setting_value("sync_interval_minutes") == 45
  end

  test "shows honest effect labels and read-only system information", %{conn: conn} do
    {:ok, media_view, _html} = live(conn, ~p"/settings?category=media")
    assert has_element?(media_view, "#media-file-naming-template", "Stored only")

    {:ok, system_view, _html} = live(conn, ~p"/settings?category=system")
    assert has_element?(system_view, "#system-information")
    assert has_element?(system_view, "#system-version")
    assert has_element?(system_view, "#system-root-folder-health")
    assert has_element?(system_view, "#settings-section-system", "Restart required")
    assert render(system_view) =~ "Local-network access"

    {:ok, _param_set} =
      Settings.create_yt_dlp_param_set(%{
        name: "Effect labels #{System.unique_integer([:positive])}"
      })

    {:ok, download_view, _html} = live(conn, ~p"/settings?category=download")
    assert has_element?(download_view, "#settings-section-download", "Applies to new items")
    assert has_element?(download_view, "#settings-section-download", "Stored only")
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

  defp configure_credential_client(response \\ {200, %{"items" => []}}) do
    previous = Application.get_env(:ytdarr, YtdarrWeb.SettingsLive)

    on_exit(fn ->
      if previous do
        Application.put_env(:ytdarr, YtdarrWeb.SettingsLive, previous)
      else
        Application.delete_env(:ytdarr, YtdarrWeb.SettingsLive)
      end
    end)

    client =
      Req.new(
        plug: {CredentialPlug, test_pid: self(), response: response},
        retry: false
      )

    Application.put_env(
      :ytdarr,
      YtdarrWeb.SettingsLive,
      credential_test_client: client
    )
  end

  defp preserve_youtube_environment do
    previous_api_key = System.get_env("YTDARR_YOUTUBE_API_KEY")

    on_exit(fn ->
      if previous_api_key do
        System.put_env("YTDARR_YOUTUBE_API_KEY", previous_api_key)
      else
        System.delete_env("YTDARR_YOUTUBE_API_KEY")
      end
    end)
  end

  defp ensure_single_active_root do
    case Settings.list_active_media_folders!() do
      [] ->
        path = create_writable_directory("protected-root")
        Settings.create_media_root_folder!(%{path: path})

      [root] ->
        root

      [root | others] ->
        Enum.each(others, &Settings.deactivate_media_root_folder!/1)
        root
    end
  end
end
