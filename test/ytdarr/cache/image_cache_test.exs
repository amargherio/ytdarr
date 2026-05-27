defmodule Ytdarr.Cache.ImageCacheTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Cache.ImageCache

  test "get/2 fetches cache misses remotely and serves later hits from memory" do
    {base_url, state_pid} =
      start_image_server(%{
        body: "avatar-v1",
        etag: "etag-v1",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("memory-hit", base_url)

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1
    assert File.exists?(Path.join(channel.base_path, "avatar.png"))

    Agent.update(state_pid, &Map.merge(&1, %{body: "avatar-v2", etag: "etag-v2"}))

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1
  end

  test "evict/1 clears the in-memory entry and falls back to disk" do
    {base_url, state_pid} =
      start_image_server(%{
        body: "avatar-v1",
        etag: "etag-v1",
        content_type: "image/png",
        requests: 0
      })

    channel = build_channel("disk-hit", base_url)

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1

    assert :ok = ImageCache.evict(channel.id)
    Agent.update(state_pid, &Map.merge(&1, %{body: "avatar-v2", etag: "etag-v2"}))

    assert {:ok, "avatar-v1", "image/png"} = ImageCache.get(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 1

    assert {:ok, {"avatar-v1", "image/png"}} =
             Cachex.get(:image_cache, cache_key(channel.id, "avatar"))
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

    assert :ok = ImageCache.evict(channel.id)
    assert :not_modified = ImageCache.refresh(channel, "avatar")
    assert Agent.get(state_pid, & &1.requests) == 2

    assert {:ok, {"avatar-v1", "image/png"}} =
             Cachex.get(:image_cache, cache_key(channel.id, "avatar"))
  end

  test "get/2 returns an error when no remote URL is configured" do
    channel = %{build_channel("missing-url", "http://127.0.0.1:1") | avatar_url: nil}

    assert {:error, :no_url} = ImageCache.get(channel, "avatar")
  end

  defp build_channel(prefix, base_url) do
    cache_root = cache_root(prefix)
    File.rm_rf(cache_root)
    on_exit(fn -> File.rm_rf(cache_root) end)

    channel = channel_fixture()
    ImageCache.evict(channel.id)
    on_exit(fn -> ImageCache.evict(channel.id) end)

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
        updated_state = Map.update!(state, :requests, &(&1 + 1))
        {updated_state, updated_state}
      end)

    request_etag = conn.req_headers |> Map.new() |> Map.get("if-none-match")

    if request_etag == state.etag do
      Plug.Conn.send_resp(conn, 304, "")
    else
      conn
      |> Plug.Conn.put_resp_header("content-type", state.content_type)
      |> Plug.Conn.put_resp_header("etag", state.etag)
      |> Plug.Conn.send_resp(200, state.body)
    end
  end
end
