defmodule Ytdarr.Cache.ImageCacheTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.{Settings, Cache.ImageCache}

  setup do
    {group, 0} = System.cmd("id", ["-gn"])
    {:ok, _} = Settings.put_setting("media.owner_group", String.trim(group))
    {:ok, _} = Settings.put_setting("media.file_mode", "0644")
    {:ok, _} = Settings.put_setting("media.directory_mode", "0755")

    root =
      Path.join(System.tmp_dir!(), "ytdarr-cache-channels-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Enum.each(Settings.list_active_media_folders!(), &Settings.deactivate_media_root_folder!/1)
    Settings.create_media_root_folder!(%{path: root, purpose: "videos", active: true})
    :ok
  end

  test "get_image/2 fetches cache misses remotely and serves later hits from memory" do
    {base_url, state_pid} =
      start_image_server(%{
        body: "avatar-v1",
        etag: "etag-v1",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("memory-hit", base_url)

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1
    image_path = Path.join(channel.base_path, "poster.png")
    meta_path = Path.join(channel.base_path, "avatar.meta")
    assert File.exists?(image_path)
    assert Bitwise.band(File.stat!(image_path).mode, 0o7777) == 0o644
    assert Bitwise.band(File.stat!(meta_path).mode, 0o7777) == 0o644
    assert Bitwise.band(File.stat!(channel.base_path).mode, 0o7777) == 0o755

    Agent.update(state_pid, &Map.merge(&1, %{body: "avatar-v2", etag: "etag-v2"}))

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1
  end

  test "delete_entry/2 clears the in-memory entry and falls back to disk" do
    {base_url, state_pid} =
      start_image_server(%{
        body: "avatar-v1",
        etag: "etag-v1",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("disk-hit", base_url)

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1

    assert :ok = ImageCache.delete_entry(channel, "avatar")
    Agent.update(state_pid, &Map.merge(&1, %{body: "avatar-v2", etag: "etag-v2"}))

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1

    assert {:ok, {"avatar-v1", "image/png"}} =
             ImageCache.fetch(cache_key(channel.id, "avatar"))
  end

  test "refresh/2 updates cached content and honors not-modified responses" do
    {base_url, state_pid} =
      start_image_server(%{
        body: "avatar-v1",
        etag: "etag-v1",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("refresh", base_url)

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1

    assert :ok = ImageCache.delete_entry(channel, "avatar")
    assert :not_modified = ImageCache.refresh(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 2

    assert {:ok, {"avatar-v1", "image/png"}} =
             ImageCache.fetch(cache_key(channel.id, "avatar"))
  end

  test "refresh replaces warm memory and persists validators with the source URL" do
    {url, server} =
      start_image_server(%{body: "old", etag: "old", content_type: "image/png", requests: 0})

    channel = build_channel("changed", url)
    assert {:ok, "old", _} = ImageCache.get_image(channel, "avatar")

    Agent.update(
      server,
      &Map.merge(&1, %{body: "new", etag: "new", last_modified: "Tue, 03 Nov 2026 10:00:00 GMT"})
    )

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    assert {:ok, "new", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert File.read!(Path.join(channel.base_path, "poster.png")) == "new"
    meta = read_meta(channel, "avatar")
    assert meta["source_url"] == channel.avatar_url
    assert meta["etag"] == "new"
    assert meta["last_modified"] == "Tue, 03 Nov 2026 10:00:00 GMT"
    assert Agent.get(server, & &1.last_headers)["if-none-match"] == "old"
  end

  test "changed source URLs never reuse colliding validators" do
    {url, server} =
      start_image_server(%{
        body: "old",
        etag: "same",
        last_modified: "Tue, 03 Nov 2026 10:00:00 GMT",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("changed-url", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    channel = %{channel | avatar_url: url <> "/different"}
    Agent.update(server, &Map.put(&1, :body, "new source"))

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    refute Map.has_key?(Agent.get(server, & &1.last_headers), "if-none-match")
    refute Map.has_key?(Agent.get(server, & &1.last_headers), "if-modified-since")
    assert {:ok, "new source", _} = ImageCache.get_image(channel, "avatar")
    assert read_meta(channel, "avatar")["source_url"] == channel.avatar_url
  end

  test "Last-Modified alone supports conditional refresh and warms memory" do
    modified = "Tue, 03 Nov 2026 10:00:00 GMT"

    {url, server} =
      start_image_server(%{
        body: "image",
        etag: nil,
        last_modified: modified,
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("last-modified", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    assert :ok = ImageCache.delete_entry(channel, "avatar")
    assert :not_modified = ImageCache.refresh(channel, "avatar")
    assert Agent.get(server, & &1.last_headers)["if-modified-since"] == modified
    assert {:ok, {"image", "image/png"}} = ImageCache.fetch(cache_key(channel.id, "avatar"))
  end

  test "identical unconditional bytes preserve the image while updating validators" do
    {url, server} =
      start_image_server(%{body: "same", etag: "one", content_type: "image/png", requests: 0})

    channel = build_channel("unchanged", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    path = Path.join(channel.base_path, "poster.png")
    timestamp = {{2020, 1, 2}, {3, 4, 5}}
    File.touch!(path, timestamp)
    Agent.update(server, &Map.merge(&1, %{etag: "two", force_status: 200}))

    assert :not_modified = ImageCache.refresh(channel, "avatar")
    assert File.stat!(path).mtime == timestamp
    assert read_meta(channel, "avatar")["etag"] == "two"
    assert {:ok, "same", "image/png"} = ImageCache.get_image(channel, "avatar")
  end

  test "missing disk artwork fetches unconditionally even with warm memory and validators" do
    {url, server} =
      start_image_server(%{body: "image", etag: "same", content_type: "image/png", requests: 0})

    channel = build_channel("missing-image", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    File.rm!(Path.join(channel.base_path, "poster.png"))
    assert ImageCache.image_filename(channel, "avatar") == nil

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    refute Map.has_key?(Agent.get(server, & &1.last_headers), "if-none-match")
    assert ImageCache.image_filename(channel, "avatar") == "poster.png"
  end

  test "MIME changes replace artwork and remove obsolete poster and legacy extensions" do
    {url, server} =
      start_image_server(%{
        body: "same bytes",
        etag: "one",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("format-change", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    File.write!(Path.join(channel.base_path, "avatar.gif"), "stale")
    File.write!(Path.join(channel.base_path, "poster.webp"), "stale")
    Agent.update(server, &Map.merge(&1, %{content_type: "image/jpeg", etag: "two"}))

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    assert ImageCache.image_filename(channel, "avatar") == "poster.jpg"
    refute File.exists?(Path.join(channel.base_path, "poster.png"))
    refute File.exists?(Path.join(channel.base_path, "poster.webp"))
    refute File.exists?(Path.join(channel.base_path, "avatar.gif"))
    assert {:ok, "same bytes", "image/jpeg"} = ImageCache.get_image(channel, "avatar")
  end

  test "banner persistence honors configured permissions across refreshes" do
    {:ok, _} = Settings.put_setting("media.file_mode", "0660")
    {:ok, _} = Settings.put_setting("media.directory_mode", "0770")

    {url, server} =
      start_image_server(%{body: "banner", etag: "one", content_type: "image/webp", requests: 0})

    channel = build_channel("banner-permissions", url)
    assert :refreshed = ImageCache.refresh(channel, "banner")
    Agent.update(server, &Map.merge(&1, %{body: "new banner", etag: "two"}))
    assert :refreshed = ImageCache.refresh(channel, "banner")

    assert ImageCache.image_filename(channel, "banner") == "banner.webp"

    for name <- ["banner.webp", "banner.meta"] do
      stat = File.stat!(Path.join(channel.base_path, name))
      assert Bitwise.band(stat.mode, 0o7777) == 0o660
      assert stat.gid == File.stat!(channel.base_path).gid
    end

    assert Bitwise.band(File.stat!(channel.base_path).mode, 0o7777) == 0o770
  end

  test "legacy avatar artwork migrates to poster without network access" do
    {url, server} =
      start_image_server(%{body: "remote", etag: "one", content_type: "image/png", requests: 0})

    channel = build_channel("legacy", url)
    File.mkdir_p!(channel.base_path)
    File.write!(Path.join(channel.base_path, "avatar.png"), "legacy")

    File.write!(
      Path.join(channel.base_path, "avatar.meta"),
      Jason.encode!(%{"ext" => "png", "content_type" => "image/png", "etag" => "legacy"})
    )

    assert {:ok, "legacy", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert ImageCache.image_filename(channel, "avatar") == "poster.png"
    assert File.read!(Path.join(channel.base_path, "poster.png")) == "legacy"
    refute File.exists?(Path.join(channel.base_path, "avatar.png"))
    assert Agent.get(server, & &1.requests) == 0
  end

  test "refresh migrates legacy artwork but does not trust validators without a source URL" do
    {url, server} =
      start_image_server(%{
        body: "updated",
        etag: "colliding",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("legacy-refresh", url)
    File.mkdir_p!(channel.base_path)
    File.write!(Path.join(channel.base_path, "avatar.png"), "legacy")

    File.write!(
      Path.join(channel.base_path, "avatar.meta"),
      Jason.encode!(%{"ext" => "png", "content_type" => "image/png", "etag" => "colliding"})
    )

    assert :refreshed = ImageCache.refresh(channel, "avatar")
    refute Map.has_key?(Agent.get(server, & &1.last_headers), "if-none-match")
    assert File.read!(Path.join(channel.base_path, "poster.png")) == "updated"
    refute File.exists?(Path.join(channel.base_path, "avatar.png"))
  end

  test "an unsolicited 304 cannot report success without a persisted image" do
    {url, _server} =
      start_image_server(%{
        body: "",
        etag: "one",
        content_type: "image/png",
        requests: 0,
        force_status: 304
      })

    channel = build_channel("missing-304", url)

    assert {:error, {:http_status, 304}} = ImageCache.refresh(channel, "avatar")
    assert ImageCache.image_filename(channel, "avatar") == nil
    assert {:error, %Nebulex.KeyError{}} = ImageCache.fetch(cache_key(channel.id, "avatar"))
  end

  test "failed downloads retain good artwork and memory" do
    {url, server} =
      start_image_server(%{body: "good", etag: "one", content_type: "image/png", requests: 0})

    channel = build_channel("failed-download", url)
    assert :refreshed = ImageCache.refresh(channel, "avatar")
    old_meta = read_meta(channel, "avatar")
    Agent.update(server, &Map.put(&1, :force_status, 404))

    assert {:error, {:http_status, 404}} = ImageCache.refresh(channel, "avatar")
    assert {:ok, "good", "image/png"} = ImageCache.get_image(channel, "avatar")
    assert File.read!(Path.join(channel.base_path, "poster.png")) == "good"
    assert read_meta(channel, "avatar") == old_meta
  end

  test "disk failures return errors instead of claiming a persisted refresh" do
    {url, _server} =
      start_image_server(%{body: "image", etag: "one", content_type: "image/png", requests: 0})

    channel = build_channel("disk-error", url)
    File.mkdir_p!(Path.join(channel.base_path, "poster.png"))

    assert {:error, _} = ImageCache.refresh(channel, "avatar")
    assert {:error, %Nebulex.KeyError{}} = ImageCache.fetch(cache_key(channel.id, "avatar"))
  end

  defp read_meta(channel, type) do
    channel.base_path |> Path.join("#{type}.meta") |> File.read!() |> Jason.decode!()
  end

  test "get_image/2 returns an error when no remote URL is configured" do
    channel = %{build_channel("missing-url", "http://127.0.0.1:1") | avatar_url: nil}

    assert {:error, :no_url} = ImageCache.get_image(channel, "avatar")
    assert {:error, :no_url} = ImageCache.refresh(channel, "avatar")
    assert ImageCache.image_filename(channel, "avatar") == nil
  end

  defp build_channel(prefix, base_url) do
    cache_root = cache_root(prefix)
    File.rm_rf(cache_root)
    on_exit(fn -> File.rm_rf(cache_root) end)

    channel = channel_fixture()
    ImageCache.delete(cache_key(channel.id, "avatar"))
    ImageCache.delete(cache_key(channel.id, "banner"))

    on_exit(fn ->
      ImageCache.delete(cache_key(channel.id, "avatar"))
      ImageCache.delete(cache_key(channel.id, "banner"))
    end)

    %{
      channel
      | base_path: cache_root,
        avatar_url: base_url <> "/avatar",
        banner_url: base_url <> "/banner"
    }
  end

  defp cache_root(prefix) do
    Path.join(File.cwd!(), "scratch-output/#{prefix}-#{System.unique_integer([:positive])}")
  end

  defp cache_key(channel_id, type), do: "channel:#{channel_id}:#{type}"

  defp start_image_server(initial_state) do
    {:ok, state_pid} = start_supervised({Agent, fn -> initial_state end})

    {:ok, server_pid} =
      start_supervised(
        {Bandit, scheme: :http, port: 0, plug: fn conn, _opts -> serve_image(conn, state_pid) end}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server_pid)
    {"http://127.0.0.1:#{port}", state_pid}
  end

  defp serve_image(conn, state_pid) do
    state =
      Agent.get_and_update(state_pid, fn state ->
        updated_state =
          state
          |> Map.update!(:requests, &(&1 + 1))
          |> Map.put(:last_headers, Map.new(conn.req_headers))

        {updated_state, updated_state}
      end)

    headers = Map.new(conn.req_headers)
    etag = Map.get(state, :etag)
    modified = Map.get(state, :last_modified)

    not_modified =
      (not is_nil(etag) and headers["if-none-match"] == etag) or
        (is_nil(etag) and not is_nil(modified) and headers["if-modified-since"] == modified)

    status = Map.get(state, :force_status, if(not_modified, do: 304, else: 200))

    conn
    |> Plug.Conn.put_resp_header("content-type", state.content_type)
    |> maybe_put_header("etag", etag)
    |> maybe_put_header("last-modified", modified)
    |> Plug.Conn.send_resp(status, if(status == 304, do: "", else: state.body))
  end

  defp maybe_put_header(conn, _key, nil), do: conn
  defp maybe_put_header(conn, key, value), do: Plug.Conn.put_resp_header(conn, key, value)
end
