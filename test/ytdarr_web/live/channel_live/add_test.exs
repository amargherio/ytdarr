defmodule YtdarrWeb.ChannelLive.AddTest do
  @moduledoc """
  Tests for the Direct Add tab on the Add Channel LiveView.
  """
  use YtdarrWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Add page renders correctly" do
    test "shows both Search and Direct Add tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      assert has_element?(view, "#add-method-tabs")
      assert has_element?(view, "button", "Search")
      assert has_element?(view, "button", "Direct Add")
    end

    test "defaults to Search tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      assert has_element?(view, "#search-tab")
      refute has_element?(view, "#direct-add-tab")
    end
  end

  describe "Tab switching" do
    test "switching to Direct Add tab shows the resolve form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      view
      |> element("button", "Direct Add")
      |> render_click()

      assert has_element?(view, "#direct-add-tab")
      assert has_element?(view, "#resolve-form")
      assert has_element?(view, "#direct-input")
      refute has_element?(view, "#search-tab")
    end

    test "switching back to Search tab hides direct add", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      view
      |> element("button", "Direct Add")
      |> render_click()

      view
      |> element("button", "Search")
      |> render_click()

      assert has_element?(view, "#search-tab")
      refute has_element?(view, "#direct-add-tab")
    end
  end

  describe "Direct Add form" do
    test "resolve form is present with input and submit button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      view
      |> element("button", "Direct Add")
      |> render_click()

      assert has_element?(view, "#resolve-form")
      assert has_element?(view, "#direct-input")
    end

    test "shows error for empty identifier submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      view
      |> element("button", "Direct Add")
      |> render_click()

      view
      |> form("#resolve-form", %{"identifier" => ""})
      |> render_submit()

      # Wait for async message to arrive
      :timer.sleep(100)
      html = render(view)

      assert html =~ "Please enter a YouTube handle"
    end

    test "shows error for unrecognized input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      view
      |> element("button", "Direct Add")
      |> render_click()

      view
      |> form("#resolve-form", %{"identifier" => "just some random text"})
      |> render_submit()

      :timer.sleep(100)
      html = render(view)

      assert html =~ "Unrecognized format"
    end
  end

  describe "Search tab retains existing functionality" do
    test "search form is present on search tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      assert has_element?(view, "#search-form")
    end

    test "tab state resets when switching", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/channels/add")

      # Switch to Direct Add and back
      view |> element("button", "Direct Add") |> render_click()
      view |> element("button", "Search") |> render_click()

      # Search tab should be clean
      assert has_element?(view, "#search-form")
    end
  end
end
