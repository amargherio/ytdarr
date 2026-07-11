defmodule YtdarrWeb.HealthControllerTest do
  use YtdarrWeb.ConnCase, async: false

  defmodule ReadyHealth do
    def ready?, do: true
  end

  defmodule UnavailableHealth do
    def ready?, do: false
  end

  setup do
    previous = Application.get_env(:ytdarr, :health_check)

    on_exit(fn ->
      if previous do
        Application.put_env(:ytdarr, :health_check, previous)
      else
        Application.delete_env(:ytdarr, :health_check)
      end
    end)
  end

  test "GET /health/live reports a live endpoint", %{conn: conn} do
    conn = get(conn, ~p"/health/live")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready reports readiness", %{conn: conn} do
    Application.put_env(:ytdarr, :health_check, ReadyHealth)

    conn = get(conn, ~p"/health/ready")

    assert json_response(conn, 200) == %{"status" => "ready"}
  end

  test "GET /health/ready reports an unavailable dependency without details", %{conn: conn} do
    Application.put_env(:ytdarr, :health_check, UnavailableHealth)

    conn = get(conn, ~p"/health/ready")

    assert json_response(conn, 503) == %{"status" => "unavailable"}
  end
end
