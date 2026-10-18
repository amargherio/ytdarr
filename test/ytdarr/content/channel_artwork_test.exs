defmodule Ytdarr.Content.ChannelArtworkTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.{Content, Settings}
  alias Ytdarr.Cache.ImageCache
  alias Ytdarr.Services.YouTube.QuotaTracker

  setup do
    root =
      Path.join(System.tmp_dir!(), "ytdarr-channel-artwork-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    Enum.each(Settings.list_active_media_folders!(), &Settings.deactivate_media_root_folder!/1)
    Settings.create_media_root_folder!(%{path: root, purpose: "videos", active: true})
    {group, 0} = System.cmd("id", ["-gn"])
    {:ok, _} = Settings.put_setting("media.owner_group", String.trim(group))
    {:ok, _} = Settings.put_setting("media.file_mode", "0640")
    {:ok, _} = Settings.put_setting("media.directory_mode", "0750")

    {:ok, state} = start_supervised({Agent, fn -> %{version: 1, image_status: 200} end})

    {:ok, server} =
      start_supervised(
        {Bandit, scheme: :http, port: 0, plug: fn conn, _ -> serve(conn, state) end}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    QuotaTracker.reset()
    on_exit(fn -> QuotaTracker.reset() end)
    {:ok, base: "http://127.0.0.1:#{port}", state: state}
  end

  test "creation persists Jellyfin artwork, escaped show metadata and configured permissions", %{
    base: base
  } do
    channel =
      channel_fixture(%{
        name: "Art & <Science>",
        description: "A <show> & its creator",
        avatar_url: base <> "/avatar",
        banner_url: base <> "/banner"
      })

    clear_cache_on_exit(channel)

    assert File.dir?(channel.generic_video_path)
    assert File.read!(Path.join(channel.base_path, "poster.png")) == "/avatar-v1"
    assert File.read!(Path.join(channel.base_path, "banner.png")) == "/banner-v1"
    nfo = File.read!(Path.join(channel.base_path, "tvshow.nfo"))
    assert nfo =~ "<title>Art &amp; &lt;Science&gt;</title>"
    assert nfo =~ "<plot>A &lt;show&gt; &amp; its creator</plot>"
    assert nfo =~ ~s(<uniqueid type="youtube" default="true">#{channel.external_id}</uniqueid>)
    assert nfo =~ ~s(<thumb aspect="poster">poster.png</thumb>)
    assert nfo =~ ~s(<thumb aspect="banner">banner.png</thumb>)

    for filename <- ~w(poster.png banner.png avatar.meta banner.meta tvshow.nfo) do
      stat = File.stat!(Path.join(channel.base_path, filename))
      assert Bitwise.band(stat.mode, 0o7777) == 0o640
      assert stat.gid == File.stat!(channel.base_path).gid
    end

    for directory <- [channel.base_path, channel.generic_video_path] do
      assert Bitwise.band(File.stat!(directory).mode, 0o7777) == 0o750
    end
  end

  test "full channel sync follows changed URLs and refreshes persisted and served images", %{
    base: base,
    state: state
  } do
    channel =
      channel_fixture(%{avatar_url: base <> "/old-avatar", banner_url: base <> "/old-banner"})

    clear_cache_on_exit(channel)
    Agent.update(state, &%{&1 | version: 2})
    client = Req.new(base_url: base, retry: false)

    assert {:ok, :synced} =
             Content.sync_channel_content(channel.external_id,
               client: client,
               skip_quota_tracking: true
             )

    updated = Content.get_channel!(channel.id)
    assert updated.avatar_url == base <> "/avatar"
    assert updated.banner_url == base <> "/banner"
    assert File.read!(Path.join(updated.base_path, "poster.png")) == "/avatar-v2"
    assert File.read!(Path.join(updated.base_path, "banner.png")) == "/banner-v2"
    assert {:ok, "/avatar-v2", "image/png"} = ImageCache.get_image(updated, "avatar")
    assert {:ok, "/banner-v2", "image/png"} = ImageCache.get_image(updated, "banner")
  end

  test "missing or unavailable artwork does not create dangling NFO references and a later refresh repairs it",
       %{base: base, state: state} do
    Agent.update(state, &%{&1 | image_status: 404})
    channel = channel_fixture(%{avatar_url: base <> "/avatar", banner_url: base <> "/banner"})
    clear_cache_on_exit(channel)
    nfo_path = Path.join(channel.base_path, "tvshow.nfo")
    refute File.read!(nfo_path) =~ "<thumb"
    Agent.update(state, &%{&1 | image_status: 200})
    assert :ok = Content.refresh_channel_images(channel)
    assert File.read!(nfo_path) =~ ~s(<thumb aspect="poster">poster.png</thumb>)
    assert File.read!(nfo_path) =~ ~s(<thumb aspect="banner">banner.png</thumb>)
  end

  defp clear_cache_on_exit(channel) do
    on_exit(fn -> Enum.each(~w(avatar banner), &ImageCache.delete_entry(channel, &1)) end)
  end

  defp serve(%{request_path: "/channels"} = conn, _state) do
    conn = Plug.Conn.fetch_query_params(conn)
    channel_id = conn.query_params["id"]
    base = "http://127.0.0.1:#{conn.port}"
    response = Ytdarr.YouTubeMocks.channel_response(channel_id)
    [channel] = response["items"]

    channel =
      channel
      |> put_in(["snippet", "thumbnails", "high", "url"], base <> "/avatar")
      |> put_in(["brandingSettings", "image", "bannerExternalUrl"], base <> "/banner")

    json_response(conn, %{response | "items" => [channel]})
  end

  defp serve(%{request_path: path} = conn, _state)
       when path in ["/playlistItems", "/playlists"] do
    json_response(conn, %{"items" => [], "pageInfo" => %{"totalResults" => 0}})
  end

  defp serve(conn, state) do
    %{version: version, image_status: status} = Agent.get(state, & &1)
    # Deliberately shared across URLs: validators must never cross URL boundaries.
    etag = "\"shared-etag\""

    if status == 200 and Plug.Conn.get_req_header(conn, "if-none-match") == [etag] do
      Plug.Conn.send_resp(conn, 304, "")
    else
      conn
      |> Plug.Conn.put_resp_header("content-type", "image/png")
      |> Plug.Conn.put_resp_header("etag", etag)
      |> Plug.Conn.send_resp(status, "#{conn.request_path}-v#{version}")
    end
  end

  defp json_response(conn, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end
end
