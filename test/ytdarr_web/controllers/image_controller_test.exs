defmodule YtdarrWeb.ImageControllerTest do
  use YtdarrWeb.ConnCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Cache.ImageCache

  describe "GET /images/channels/:channel_id/:type" do
    test "returns 200 with cache headers when the image is served from the cache",
         %{conn: conn} do
      channel = channel_fixture()
      cache_key = "channel:#{channel.id}:avatar"

      on_exit(fn -> ImageCache.delete(cache_key) end)
      ImageCache.put(cache_key, {"fake-bytes", "image/png"})

      conn = get(conn, ~p"/images/channels/#{channel.id}/avatar")

      assert conn.status == 200
      assert conn.resp_body == "fake-bytes"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
      assert get_resp_header(conn, "content-type") |> List.first() =~ "image/png"
    end

    test "returns 404 when the channel does not exist", %{conn: conn} do
      conn = get(conn, ~p"/images/channels/9999999/avatar")

      assert conn.status == 404
      assert conn.resp_body == "Channel not found"
    end

    test "returns 404 when the channel has no remote image URL", %{conn: conn} do
      channel = channel_fixture()

      Ash.Changeset.for_update(channel, :update, %{avatar_url: nil})
      |> Ash.update!()

      conn = get(conn, ~p"/images/channels/#{channel.id}/avatar")

      assert conn.status == 404
      assert conn.resp_body == "Image not found"
    end

    test "returns 400 for unsupported image types", %{conn: conn} do
      channel = channel_fixture()

      conn = get(conn, ~p"/images/channels/#{channel.id}/wallpaper")

      assert conn.status == 400
      assert conn.resp_body == "Invalid image type"
    end
  end
end
