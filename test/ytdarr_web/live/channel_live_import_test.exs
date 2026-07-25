defmodule YtdarrWeb.ChannelLiveImportTest do
  use YtdarrWeb.ConnCase

  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.Imports

  # ---------------------------------------------------------------------------
  # Fixtures: a stubbed ffprobe plus a real, unique source directory containing
  # one importable video and one qualified subtitle sidecar.
  # ---------------------------------------------------------------------------

  setup do
    original_ffprobe_path = Application.get_env(:ytdarr, :ffprobe_path)

    ffprobe_root =
      Path.join(
        System.tmp_dir!(),
        "ytdarr-import-modal-ffprobe-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(ffprobe_root)

    install_ffprobe(
      Path.join(ffprobe_root, "ffprobe"),
      "printf '%s' '{\"streams\":[{\"height\":1080}]}'\n"
    )

    dir_name = "ytdarr-import-modal-src-#{System.unique_integer([:positive])}"
    source_root = Path.join(System.tmp_dir!(), dir_name)
    File.mkdir_p!(source_root)
    source_file = Path.join(source_root, "legacy.mkv")
    File.write!(source_file, "fake-video-bytes")
    File.write!(Path.join(source_root, "legacy.en.srt"), "1\n00:00:00,000 --> 00:00:01,000\nHi\n")

    on_exit(fn ->
      File.rm_rf!(ffprobe_root)
      File.rm_rf!(source_root)

      case original_ffprobe_path do
        nil -> Application.delete_env(:ytdarr, :ffprobe_path)
        path -> Application.put_env(:ytdarr, :ffprobe_path, path)
      end
    end)

    channel =
      channel_fixture(%{name: "Import Modal Channel #{System.unique_integer([:positive])}"})

    video =
      video_fixture(%{
        channel_id: channel.id,
        title: "Legacy Episode",
        upload_date: ~D[2025-06-01]
      })

    playlist = playlist_fixture(%{channel_id: channel.id})

    {:ok, _link} =
      Content.create_playlist_video(%{playlist_id: playlist.id, video_id: video.id, position: 1})

    %{
      channel: channel,
      video: video,
      playlist: playlist,
      dir_name: dir_name,
      source_root: source_root,
      source_file: source_file
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp install_ffprobe(path, body) do
    File.write!(path, "#!/bin/sh\n#{body}")
    File.chmod!(path, 0o755)
    Application.put_env(:ytdarr, :ffprobe_path, path)
  end

  defp table_row_id(table_id, video_id), do: "video-row-#{table_id}-#{video_id}"
  defp import_button_id(table_id, video_id), do: "import-video-#{table_id}-#{video_id}"
  defp retry_button_id(table_id, video_id), do: "retry-import-recovery-#{table_id}-#{video_id}"

  defp occurrences(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)

  defp expand_all_videos(view), do: view |> element("#toggle-all-videos") |> render_click()

  defp expand_playlist(view, playlist_id),
    do: view |> element("#toggle-playlist-#{playlist_id}") |> render_click()

  defp expand_table(view, "all-videos"), do: expand_all_videos(view)

  defp expand_table(view, "videos-" <> playlist_id),
    do: expand_playlist(view, String.to_integer(playlist_id))

  # Filters the current listing down to `name` before clicking the matching
  # folder, so navigation never depends on alphabetical position within the
  # first paginated page of a real, possibly-crowded directory (`/`, `/tmp`).
  defp filter_and_open_folder(view, name) do
    view
    |> form("#video-import-filter-form", %{"filter" => %{"query" => name}})
    |> render_change()

    render_async(view)

    view |> element("button[id^='video-import-folder-']", name) |> render_click()
    render_async(view)
  end

  # Drives the modal from closed through :ready with `legacy.mkv` inspected, by
  # clicking through the real filesystem: root -> /tmp -> the fixture directory.
  defp open_browse_and_inspect(view, video, dir_name, table_id \\ "all-videos") do
    unless has_element?(view, "##{import_button_id(table_id, video.id)}"),
      do: expand_table(view, table_id)

    view |> element("##{import_button_id(table_id, video.id)}") |> render_click()
    render_async(view)

    filter_and_open_folder(view, "tmp")
    filter_and_open_folder(view, dir_name)

    view |> element("button[id^='video-import-file-']", "legacy.mkv") |> render_click()
    render_async(view)

    view
  end

  # ---------------------------------------------------------------------------
  # Duplicate rows and exact control ids
  # ---------------------------------------------------------------------------

  describe "duplicate rows and control ids" do
    test "renders unique row, import, and section-toggle ids across all-videos and a playlist table",
         %{
           conn: conn,
           channel: channel,
           video: video,
           playlist: playlist
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      expand_all_videos(view)
      html = expand_playlist(view, playlist.id)

      assert has_element?(view, "##{table_row_id("all-videos", video.id)}")
      assert has_element?(view, "##{table_row_id("videos-#{playlist.id}", video.id)}")
      assert has_element?(view, "##{import_button_id("all-videos", video.id)}")
      assert has_element?(view, "##{import_button_id("videos-#{playlist.id}", video.id)}")
      assert has_element?(view, "#toggle-all-videos")
      assert has_element?(view, "#toggle-all-videos-chevron")
      assert has_element?(view, "#toggle-playlist-#{playlist.id}")
      assert has_element?(view, "#toggle-playlist-#{playlist.id}-chevron")

      # Both rows use tabindex="-1" so they are only ever focused programmatically
      # (never tab-stops), which is what the modal's close/cancel fallback relies on.
      assert html =~ ~s(id="#{table_row_id("videos-#{playlist.id}", video.id)}" tabindex="-1")
    end
  end

  # ---------------------------------------------------------------------------
  # Open / overlay mechanics
  # ---------------------------------------------------------------------------

  describe "open and overlay mechanics" do
    test "opens exactly one overlay with an inert, aria-hidden app shell and an eventless backdrop",
         %{
           conn: conn,
           channel: channel,
           video: video
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)

      html = view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()

      assert occurrences(html, ~s(id="video-import-overlay")) == 1
      assert html =~ ~s(id="app-shell" inert)
      assert html =~ ~s(aria-hidden="true")
      assert html =~ "video-import-close"
      assert html =~ "video-import-backdrop"
      assert has_element?(view, "#video-import-dialog[phx-hook='Phoenix.FocusWrap']")
      assert has_element?(view, "#video-import-dialog-start[tabindex='0']")
      assert has_element?(view, "#video-import-dialog-end[tabindex='0']")
      refute has_element?(view, "#video-import-backdrop[phx-click-away]")
      refute has_element?(view, "#video-import-dialog[phx-click-away]")
      refute Regex.match?(~r/id="video-import-backdrop"[^>]*phx-click/, html)
    end

    test "a forged table id does not open the modal", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      html =
        render_hook(view, "open-video-import", %{
          "id" => to_string(video.id),
          "table-id" => "videos-999999"
        })

      refute html =~ "video-import-overlay"
    end

    test "a second open-video-import while a modal is already open is ignored", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)

      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      html_before = render(view)
      [_, token_before] = Regex.run(~r/name="token" value="([^"]+)"/, html_before)

      render_hook(view, "open-video-import", %{
        "id" => to_string(video.id),
        "table-id" => "all-videos"
      })

      html_after = render(view)
      [_, token_after] = Regex.run(~r/name="token" value="([^"]+)"/, html_after)

      assert token_after == token_before
      assert occurrences(html_after, ~s(id="video-import-overlay")) == 1
    end

    test "import is unavailable for a video with no upload date and does not render an opener", %{
      conn: conn,
      channel: channel
    } do
      undated = video_fixture(%{channel_id: channel.id, title: "No Date Video", upload_date: nil})
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      html = expand_all_videos(view)

      refute has_element?(view, "##{import_button_id("all-videos", undated.id)}")
      assert html =~ "Import unavailable: refresh video metadata to obtain an upload date"
    end
  end

  # ---------------------------------------------------------------------------
  # Close, cancel, and escape
  # ---------------------------------------------------------------------------

  describe "close, cancel, and escape" do
    test "close-video-import removes the modal, clears the inert boundary, and the opener remains usable",
         %{
           conn: conn,
           channel: channel,
           video: video
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)

      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      assert has_element?(view, "#video-import-overlay")
      assert has_element?(view, ~s(#app-shell[inert]))

      html = view |> element("#video-import-close") |> render_click()

      refute html =~ "video-import-overlay"
      refute has_element?(view, ~s(#app-shell[inert]))
      assert has_element?(view, "##{import_button_id("all-videos", video.id)}")
    end

    test "the cancel button closes the modal", %{conn: conn, channel: channel, video: video} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()

      html = view |> element("#video-import-cancel") |> render_click()
      refute html =~ "video-import-overlay"
    end

    test "escape closes the modal", %{conn: conn, channel: channel, video: video} do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()

      html = view |> element("#video-import-overlay") |> render_keydown()
      refute html =~ "video-import-overlay"
    end

    test "repeated close/cancel/escape once the modal is already gone are harmless no-ops", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()

      view |> element("#video-import-close") |> render_click()
      refute render(view) =~ "video-import-overlay"

      html1 = render_hook(view, "close-video-import", %{"token" => "forged"})
      html2 = render_hook(view, "close-video-import", %{"token" => ""})

      refute html1 =~ "video-import-overlay"
      refute html2 =~ "video-import-overlay"
      # The underlying opener and section toggle remain perfectly functional.
      assert has_element?(view, "##{import_button_id("all-videos", video.id)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Forged and stale tokens
  # ---------------------------------------------------------------------------

  describe "forged and stale tokens" do
    test "a stale token cannot close a newer modal opened after it", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)

      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      html1 = render(view)
      [_, stale_token] = Regex.run(~r/name="token" value="([^"]+)"/, html1)

      view |> element("#video-import-close") |> render_click()
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()

      html2 = render_hook(view, "close-video-import", %{"token" => stale_token})
      assert html2 =~ "video-import-overlay"
    end

    test "a forged token cannot browse the directory listing", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)

      html_before = render(view)
      render_hook(view, "browse-import-directory", %{"token" => "forged", "path" => "/etc"})

      assert html_before == render(view)
    end

    test "an out-of-range page change is rejected and leaves the last successful page unchanged",
         %{
           conn: conn,
           channel: channel,
           video: video,
           dir_name: dir_name
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)
      filter_and_open_folder(view, "tmp")
      filter_and_open_folder(view, dir_name)

      before_html = render(view)
      assert before_html =~ "Page 1 of 1"
      [_, token] = Regex.run(~r/name="token" value="([^"]+)"/, before_html)

      html = render_hook(view, "change-import-page", %{"token" => token, "page" => "999"})

      assert html =~ "Page 1 of 1"
      assert html =~ "legacy.mkv"
    end
  end

  # ---------------------------------------------------------------------------
  # Browsing
  # ---------------------------------------------------------------------------

  describe "browsing" do
    test "navigates from root through a real directory and lists the fixture video file", %{
      conn: conn,
      channel: channel,
      video: video,
      dir_name: dir_name
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)

      assert has_element?(view, "#video-import-root")

      filter_and_open_folder(view, "tmp")
      assert has_element?(view, "#video-import-breadcrumb-0")

      view |> element("button[id^='video-import-folder-']", dir_name) |> render_click()
      render_async(view)
      html = render(view)

      assert html =~ "legacy.mkv"
      assert has_element?(view, "button[id^='video-import-file-']")
      # The subtitle sidecar is not itself a browsable/importable file entry.
      refute html =~ "legacy.en.srt"
    end

    test "filter-import-directory filters entries by query and resets to page 1", %{
      conn: conn,
      channel: channel,
      video: video,
      dir_name: dir_name
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)
      filter_and_open_folder(view, "tmp")
      filter_and_open_folder(view, dir_name)

      assert render(view) =~ "legacy.mkv"

      view
      |> form("#video-import-filter-form", %{"filter" => %{"query" => "nonexistent-xyz"}})
      |> render_change()

      render_async(view)
      html = render(view)
      refute html =~ "legacy.mkv"
      assert html =~ "This folder is empty."

      view
      |> form("#video-import-filter-form", %{"filter" => %{"query" => "legacy"}})
      |> render_change()

      render_async(view)
      assert render(view) =~ "legacy.mkv"
    end
  end

  # ---------------------------------------------------------------------------
  # Inspection and selection
  # ---------------------------------------------------------------------------

  describe "inspection and selection" do
    test "selecting a file inspects it and shows an accurate ready preview with preselected sidecars",
         %{
           conn: conn,
           channel: channel,
           video: video,
           dir_name: dir_name,
           source_file: source_file
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      open_browse_and_inspect(view, video, dir_name)

      html = render(view)
      assert html =~ source_file
      assert html =~ "1080p"
      assert html =~ "legacy.en.srt"
      assert has_element?(view, "#video-import-confirm")
      assert has_element?(view, "#video-import-choose-another")
      assert Regex.match?(~r/id="video-import-sidecar-[^"]+"[^>]*checked/, html)
    end

    test "choose another returns to browsing, preserves the directory, and refocuses the file row",
         %{
           conn: conn,
           channel: channel,
           video: video,
           dir_name: dir_name
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)
      filter_and_open_folder(view, "tmp")
      filter_and_open_folder(view, dir_name)

      browsing_html = render(view)
      [_, entry_id] = Regex.run(~r/id="video-import-file-([^"]+)"/, browsing_html)

      view |> element("#video-import-file-#{entry_id}") |> render_click()
      render_async(view)
      assert has_element?(view, "#video-import-choose-another")

      html = view |> element("#video-import-choose-another") |> render_click()

      assert html =~ "legacy.mkv"
      refute html =~ "video-import-confirm-form"
      assert Regex.match?(~r/id="video-import-file-#{entry_id}"[^>]*phx-mounted=/, html)
    end

    test "a stale inspection result for a superseded token never reaches a newer modal", %{
      conn: conn,
      channel: channel,
      video: video,
      dir_name: dir_name,
      source_root: source_root
    } do
      marker = Path.join(source_root, ".release-ffprobe")

      delayed_root =
        Path.join(
          System.tmp_dir!(),
          "ytdarr-import-modal-delayed-ffprobe-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(delayed_root)

      install_ffprobe(Path.join(delayed_root, "ffprobe"), """
      i=0
      while [ ! -f '#{marker}' ] && [ "$i" -lt 250 ]; do
        i=$((i+1))
        sleep 0.02
      done
      printf '%s' '{"streams":[{"height":1080}]}'
      """)

      on_exit(fn -> File.rm_rf!(delayed_root) end)

      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)
      filter_and_open_folder(view, "tmp")
      filter_and_open_folder(view, dir_name)

      # Selecting the file starts an inspection blocked on the stubbed ffprobe
      # under the CURRENT token; do not await it.
      view |> element("button[id^='video-import-file-']", "legacy.mkv") |> render_click()

      # Close and reopen before it settles: the new modal gets a fresh token.
      view |> element("#video-import-close") |> render_click()
      view |> element("##{import_button_id("all-videos", video.id)}") |> render_click()
      render_async(view)

      fresh_html = render(view)
      refute fresh_html =~ "video-import-confirm-form"
      assert fresh_html =~ "video-import-root"

      # Release the stale, superseded ffprobe call and give it time to deliver
      # its result; it must never mutate the new modal's state.
      File.write!(marker, "go")
      Process.sleep(200)

      settled_html = render(view)
      refute settled_html =~ "video-import-confirm-form"
      assert settled_html =~ "video-import-root"
    end
  end

  # ---------------------------------------------------------------------------
  # Confirm
  # ---------------------------------------------------------------------------

  describe "confirm" do
    test "submitting the confirm form queues the import, closes the modal, flashes, and updates both duplicate rows",
         %{
           conn: conn,
           channel: channel,
           video: video,
           dir_name: dir_name,
           playlist: playlist
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      expand_all_videos(view)
      expand_playlist(view, playlist.id)

      open_browse_and_inspect(view, video, dir_name)
      assert has_element?(view, "#video-import-confirm")

      html =
        view
        |> form("#video-import-confirm-form", %{})
        |> render_submit()

      refute html =~ "video-import-overlay"
      assert html =~ "Import started for “Legacy Episode”."
      assert occurrences(html, "Importing") >= 2

      assert {:ok, updated_video} = Content.get_video(video.id)
      assert updated_video.download_state == :importing

      assert_enqueued(
        worker: Ytdarr.ObanWorkers.VideoImporter,
        args: %{"video_id" => video.id, "channel_id" => channel.id}
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Eligibility and recovery controls
  # ---------------------------------------------------------------------------

  describe "eligibility and recovery controls" do
    test "a failed import with pending recovery shows only the recovery badge/control, and a successful retry restores Import",
         %{
           conn: conn,
           channel: channel,
           video: video
         } do
      {:ok, importing} =
        Content.begin_video_import(video, %{
          import_job_id: 4_242,
          import_manifest: %{"source" => "x"}
        })

      recovery = %{
        "mode" => "restore",
        "entries" => [
          %{
            "kind" => "lock",
            "path" =>
              Path.join(
                System.tmp_dir!(),
                ".canonical-#{System.unique_integer([:positive])}.mkv.ytdarr-import.lock"
              ),
            "original_path" => nil,
            "owner_job_id" => 4_242,
            "major_device" => nil,
            "minor_device" => nil,
            "inode" => nil,
            "size" => nil,
            "mtime" => nil
          }
        ]
      }

      {:ok, _failed} =
        Content.mark_video_import_failed(importing, %{
          import_error: "Ytdarr could not import this file. Check the server logs and try again.",
          import_recovery: recovery
        })

      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      html = expand_all_videos(view)

      assert html =~ "Import failed"
      assert html =~ "Source recovery needed"
      assert has_element?(view, "##{retry_button_id("all-videos", video.id)}")
      refute has_element?(view, "##{import_button_id("all-videos", video.id)}")

      html = view |> element("##{retry_button_id("all-videos", video.id)}") |> render_click()

      assert html =~ "Source recovery completed."
      refute html =~ "Source recovery needed"
      assert has_element?(view, "##{import_button_id("all-videos", video.id)}")
    end
  end

  # ---------------------------------------------------------------------------
  # State invalidation
  # ---------------------------------------------------------------------------

  describe "state invalidation" do
    test "a lifecycle event for the modal's own video disables it with the state-changed message",
         %{
           conn: conn,
           channel: channel,
           video: video,
           dir_name: dir_name
         } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")
      open_browse_and_inspect(view, video, dir_name)
      assert has_element?(view, "#video-import-confirm")

      {:ok, _importing} =
        Content.begin_video_import(video, %{
          import_job_id: 9_001,
          import_manifest: %{"source" => "elsewhere"}
        })

      Imports.broadcast({:video_import_started, channel.id, video.id})

      html = render(view)

      assert html =~
               "This video&#39;s state changed in another session. Close Import and try again." or
               html =~
                 "This video's state changed in another session. Close Import and try again."

      refute html =~ "video-import-confirm-form"
      assert has_element?(view, "#video-import-close")
      assert has_element?(view, "#video-import-overlay")
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-view convergence
  # ---------------------------------------------------------------------------

  describe "multi-view convergence" do
    test "retry-import-recovery in one view updates a second connected view without a duplicate flash",
         %{
           conn: conn,
           channel: channel,
           video: video
         } do
      {:ok, importing} =
        Content.begin_video_import(video, %{
          import_job_id: 5_150,
          import_manifest: %{"source" => "x"}
        })

      recovery = %{
        "mode" => "delete",
        "entries" => [
          %{
            "kind" => "quarantine_owner",
            "path" => Path.join([System.tmp_dir!(), ".ytdarr-import-5150", ".owner"]),
            "original_path" => nil,
            "owner_job_id" => 5_150,
            "major_device" => nil,
            "minor_device" => nil,
            "inode" => nil,
            "size" => nil,
            "mtime" => nil
          }
        ]
      }

      {:ok, _downloaded} =
        Content.mark_video_imported(importing, %{
          download_path:
            Path.join(
              System.tmp_dir!(),
              "ytdarr-nonexistent-media-#{System.unique_integer([:positive])}.mp4"
            ),
          file_size: 42,
          download_quality: "1080p",
          import_recovery: recovery
        })

      conn2 = Phoenix.ConnTest.build_conn()
      {:ok, view1, _html1} = live(conn, ~p"/channels/#{channel}")
      {:ok, view2, _html2} = live(conn2, ~p"/channels/#{channel}")

      expand_all_videos(view1)
      html2 = expand_all_videos(view2)

      assert render(view1) =~ "Source cleanup needed"
      assert html2 =~ "Source cleanup needed"

      html1 = view1 |> element("##{retry_button_id("all-videos", video.id)}") |> render_click()

      assert html1 =~ "Source cleanup completed."
      refute html1 =~ "Source cleanup needed"

      html2 = render(view2)

      refute html2 =~ "Source cleanup needed"
      refute html2 =~ "Source cleanup completed."
    end

    test "a lifecycle event for a different channel does not flash or affect this view", %{
      conn: conn,
      channel: channel,
      video: video
    } do
      {:ok, view, _html} = live(conn, ~p"/channels/#{channel}")

      other_channel = channel_fixture()
      Imports.broadcast({:video_import_completed, other_channel.id, video.id})

      html = render(view)

      refute html =~ "Imported “"
      assert html =~ channel.name
    end
  end
end
