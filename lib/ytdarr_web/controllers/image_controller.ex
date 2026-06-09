defmodule YtdarrWeb.ImageController do
  use YtdarrWeb, :controller

  alias Ytdarr.Content
  alias Ytdarr.Cache.ImageCache

  @valid_types ~w(avatar banner)

  def show(conn, %{"channel_id" => channel_id, "type" => type})
      when type in @valid_types do
    case Content.get_channel(channel_id) do
      {:ok, channel} ->
        case ImageCache.get_image(channel, type) do
          {:ok, data, content_type} ->
            conn
            |> put_resp_content_type(content_type, nil)
            |> put_resp_header("cache-control", "public, max-age=86400")
            |> send_resp(200, data)

          {:error, _reason} ->
            send_resp(conn, 404, "Image not found")
        end

      {:error, _} ->
        send_resp(conn, 404, "Channel not found")
    end
  end

  def show(conn, _params) do
    send_resp(conn, 400, "Invalid image type")
  end
end
