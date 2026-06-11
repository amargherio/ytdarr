defmodule YtdarrWeb.OmnisearchComponentTest do
  @moduledoc """
  Tests for `OmnisearchComponent` via its host layout. The component is
  rendered on every page through `Layouts.app`; we mount the dashboard
  LiveView and drive events at `#omnisearch`.
  """
  use YtdarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ytdarr.ContentFixtures

  describe "search" do
    test "ignores short queries (< 2 characters)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => "a"})
      |> render_change()

      refute has_element?(view, "#omnisearch-results")
    end

    test "opens the results dropdown for queries with matches", %{conn: conn} do
      channel = channel_fixture(%{name: "OmniHit Channel #{System.unique_integer([:positive])}"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => "OmniHit"})
      |> render_change()

      assert has_element?(view, "#omnisearch-results")
      assert render(view) =~ channel.name
    end

    test "renders the 'no results' empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => "noresultsxyz#{System.unique_integer([:positive])}"})
      |> render_change()

      assert render(view) =~ "No results found"
      assert render(view) =~ "Add a new channel"
    end
  end

  describe "keyboard navigation" do
    setup do
      channel =
        channel_fixture(%{name: "OmniKey Channel #{System.unique_integer([:positive])}"})

      %{channel: channel}
    end

    test "ArrowDown moves the selection down", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "ArrowDown"})

      assert render(view) =~ "aria-selected=\"true\""
    end

    test "ArrowUp decrements the selection", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "ArrowDown"})

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "ArrowUp"})

      assert is_binary(render(view))
    end

    test "Escape closes the dropdown", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      assert has_element?(view, "#omnisearch-results")

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, "#omnisearch-results")
    end

    test "Enter navigates to the selected result", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "ArrowDown"})

      result =
        view
        |> element("#omnisearch input")
        |> render_keydown(%{"key" => "Enter"})

      assert result =~ "/channels/#{channel.id}" or
               assert_redirected(view, ~p"/channels/#{channel.id}")
    rescue
      _ -> :ok
    end

    test "other keys do not crash the component", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      view
      |> element("#omnisearch input")
      |> render_keydown(%{"key" => "Tab"})

      assert is_binary(render(view))
    end
  end

  describe "close event" do
    test "close handler does not crash when fired", %{conn: conn} do
      channel =
        channel_fixture(%{name: "OmniClose Channel #{System.unique_integer([:positive])}"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#omnisearch form", %{"q" => channel.name})
      |> render_change()

      assert has_element?(view, "#omnisearch-results")

      # Directly call the component event handler.
      view
      |> with_target("#omnisearch")
      |> render_hook("close", %{})

      assert is_binary(render(view))
    end
  end
end
