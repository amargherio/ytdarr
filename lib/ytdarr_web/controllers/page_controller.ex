defmodule YtdarrWeb.PageController do
  use YtdarrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
