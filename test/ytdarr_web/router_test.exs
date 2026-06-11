defmodule YtdarrWeb.RouterTest do
  @moduledoc """
  Smoke tests that exercise the auth-related routes in `YtdarrWeb.Router`
  so they show up in coverage. The actual response shape isn't important
  here — we only need each route to be reachable.
  """
  use YtdarrWeb.ConnCase, async: true

  describe "auth routes" do
    test "GET /sign-in renders or redirects", %{conn: conn} do
      conn = get(conn, ~p"/sign-in")
      assert conn.status in [200, 302]
    end

    test "GET /register renders or redirects", %{conn: conn} do
      conn = get(conn, ~p"/register")
      assert conn.status in [200, 302]
    end

    test "GET /reset renders or redirects", %{conn: conn} do
      conn = get(conn, ~p"/reset")
      assert conn.status in [200, 302]
    end

    test "GET /sign-out is reachable", %{conn: conn} do
      conn = get(conn, "/sign-out")
      assert conn.status in [200, 302]
    end
  end
end
