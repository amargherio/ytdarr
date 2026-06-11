defmodule YtdarrWeb.CustomComponentsTest do
  @moduledoc """
  Render tests for pure-function components in `YtdarrWeb.CustomComponents`.
  Uses the `~H` sigil + `Phoenix.LiveViewTest.rendered_to_string/1` so each
  component is exercised exactly as it would be from a template, including
  slot rendering.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias YtdarrWeb.CustomComponents

  defp render_heex(template) do
    template
    |> rendered_to_string()
  end

  describe "data_pill/1" do
    test "renders a button when no link attrs are provided" do
      assigns = %{}

      html =
        render_heex(~H"""
        <CustomComponents.data_pill variant="primary">Click me</CustomComponents.data_pill>
        """)

      assert html =~ "<button"
      assert html =~ "btn-primary"
      assert html =~ "Click me"
    end

    test "renders a link when navigate is provided" do
      assigns = %{}

      html =
        render_heex(~H"""
        <CustomComponents.data_pill variant="secondary" size="sm" navigate="/somewhere">
          Go
        </CustomComponents.data_pill>
        """)

      assert html =~ "btn-secondary"
      assert html =~ "btn-sm"
      assert html =~ "Go"
    end

    test "supports each declared variant without raising" do
      for variant <- ~w(primary secondary info success warning error) do
        assigns = %{variant: variant}

        html =
          render_heex(~H"""
          <CustomComponents.data_pill variant={@variant} size="lg">v</CustomComponents.data_pill>
          """)

        assert html =~ "btn-#{variant}"
        assert html =~ "btn-lg"
      end
    end
  end

  describe "hero_header/1" do
    test "renders the banner with default static mode" do
      assigns = %{}

      html =
        render_heex(~H"""
        <CustomComponents.hero_header banner_url="https://example.com/banner.jpg">
          Hero title
        </CustomComponents.hero_header>
        """)

      assert html =~ "Hero title"
      assert html =~ "h-64"
      assert html =~ "https://example.com/banner.jpg"
    end

    test "renders fluid mode with a viewport clamp height" do
      assigns = %{}

      html =
        render_heex(~H"""
        <CustomComponents.hero_header banner_url="https://example.com/b.jpg" mode="fluid">
          Hero
        </CustomComponents.hero_header>
        """)

      assert html =~ "clamp(16rem,40vh,30rem)"
    end

    test "renders ratio mode with the configured aspect" do
      assigns = %{}

      html =
        render_heex(~H"""
        <CustomComponents.hero_header
          banner_url="https://example.com/b.jpg"
          mode="ratio"
          ratio="16/9"
        >
          Hero
        </CustomComponents.hero_header>
        """)

      assert html =~ "aspect-[16/9]"
    end
  end

  describe "download_progress_bar/1" do
    test "renders a percentage label and primary fill when in progress" do
      html =
        render_component(&CustomComponents.download_progress_bar/1, %{
          pct: 42.5,
          speed: "12MiB/s",
          eta: "01:23"
        })

      assert html =~ "42.5%"
      assert html =~ "bg-primary"
      assert html =~ "12MiB/s"
      assert html =~ "01:23"
    end

    test "renders a success fill at 100%" do
      html = render_component(&CustomComponents.download_progress_bar/1, %{pct: 100.0})

      assert html =~ "bg-success"
      assert html =~ "100.0%"
    end

    test "renders an indeterminate bar when pct is nil" do
      html = render_component(&CustomComponents.download_progress_bar/1, %{pct: nil})

      assert html =~ "Downloading"
      assert html =~ "animate-pulse"
    end

    test "renders a warning fill while post-processing" do
      html =
        render_component(&CustomComponents.download_progress_bar/1, %{
          pct: nil,
          post_processing?: true
        })

      assert html =~ "Post-processing"
      assert html =~ "bg-warning"
    end

    test "clamps out-of-range percentages into 0..100" do
      over = render_component(&CustomComponents.download_progress_bar/1, %{pct: 150.0})
      assert over =~ "100.0%"

      under = render_component(&CustomComponents.download_progress_bar/1, %{pct: -10.0})
      assert under =~ "0.0%"
    end
  end

  describe "progress_bar/1" do
    test "renders zero percent when total is zero" do
      html =
        render_component(&CustomComponents.progress_bar/1, %{completed: 0, total: 0})

      assert html =~ "0.0%"
    end

    test "renders the success fill at 100%" do
      html =
        render_component(&CustomComponents.progress_bar/1, %{completed: 10, total: 10})

      assert html =~ "bg-success"
      assert html =~ "100.0%"
    end

    test "renders the primary fill for partial progress" do
      html =
        render_component(&CustomComponents.progress_bar/1, %{completed: 3, total: 10})

      assert html =~ "bg-primary"
      assert html =~ "30.0%"
    end
  end

  describe "download_status_badge/1" do
    test "renders a distinct label for each known state" do
      labels = %{
        available: "Available",
        queued: "Queued",
        downloading: "Downloading",
        downloaded: "Downloaded",
        missing: "Missing"
      }

      for {state, label} <- labels do
        html = render_component(&CustomComponents.download_status_badge/1, %{state: state})
        assert html =~ label
      end
    end

    test "renders an Unknown fallback for unrecognized states" do
      html =
        render_component(&CustomComponents.download_status_badge/1, %{state: :something_else})

      assert html =~ "Unknown"
    end
  end

  describe "video_table/1" do
    test "renders rows with thumbnails and titles" do
      videos = [
        %{
          id: 1,
          title: "Video A",
          thumbnail_url: "https://example.com/a.jpg",
          upload_date: ~D[2025-01-01],
          download_state: :downloaded
        },
        %{
          id: 2,
          title: "Video B",
          thumbnail_url: nil,
          upload_date: ~D[2025-01-02],
          download_state: :available
        }
      ]

      html =
        render_component(&CustomComponents.video_table/1, %{
          id: "vt-test",
          videos: videos,
          channel_id: 99
        })

      assert html =~ "Video A"
      assert html =~ "Video B"
      assert html =~ "id=\"vt-test\""
      assert html =~ "phx-click=\"delete-video\""
      assert html =~ "phx-click=\"queue-download\""
      assert html =~ "hero-play"
    end

    test "renders without action buttons for queued state" do
      videos = [
        %{
          id: 3,
          title: "Queued Video",
          thumbnail_url: nil,
          upload_date: ~D[2025-01-03],
          download_state: :queued
        }
      ]

      html =
        render_component(&CustomComponents.video_table/1, %{
          id: "vt-queued",
          videos: videos,
          channel_id: 1
        })

      assert html =~ "Queued Video"
      refute html =~ "phx-click=\"queue-download\""
      refute html =~ "phx-click=\"delete-video\""
    end
  end
end
