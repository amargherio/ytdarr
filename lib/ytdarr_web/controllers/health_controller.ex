defmodule YtdarrWeb.HealthController do
  use YtdarrWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    health_check = Application.get_env(:ytdarr, :health_check, Ytdarr.Health)

    if health_check.ready?() do
      json(conn, %{status: "ready"})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable"})
    end
  end
end
