defmodule Ytdarr.Cache.ImageCache do
  @moduledoc """
  Two-tier image cache for channel avatars and banners.

  Read-through flow: Cachex (in-memory) → filesystem → remote URL.
  Images are stored on disk alongside channel content in base_path,
  with a metadata sidecar file tracking content type and ETag.
  """
  use Nebulex.Cache,
    otp_app: :ytdarr,
    adapter: Nebulex.Adapters.Local

  require Logger

  alias Ytdarr.MediaPermissions

  @type_config %{
    "avatar" => :avatar_url,
    "banner" => :banner_url
  }

  @doc """
  Get a cached image for a channel. Falls through from memory → disk → remote.

  Returns `{:ok, binary, content_type}` or `{:error, reason}`.
  """
  def get_image(channel, type) when type in ~w(avatar banner) do
    cache_key = cache_key(channel.id, type)

    case fetch(cache_key) do
      {:ok, {data, content_type}} when is_binary(data) ->
        {:ok, data, content_type}

      {:error, %Nebulex.KeyError{}} ->
        # Memory miss — try disk, then remote
        case read_from_disk(channel, type) do
          {:ok, data, content_type} ->
            put(cache_key, {data, content_type})
            {:ok, data, content_type}

          :miss ->
            remote_url = Map.get(channel, @type_config[type])
            fetch_and_store(channel, type, remote_url)
        end

      {:error, reason} ->
        Logger.warning(
          "ImageCache: error fetching #{type} for channel #{channel.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Force-refresh a channel's image using ETag-based conditional requests.

  Returns `:not_modified`, `:refreshed`, or `{:error, reason}`.
  """
  def refresh(channel, type) when type in ~w(avatar banner) do
    remote_url = Map.get(channel, @type_config[type])

    if is_nil(remote_url) do
      {:error, :no_url}
    else
      do_refresh(channel, type, remote_url)
    end
  end

  @doc """
  Evict a channel's image from the in-memory cache. This won't delete files from disk if the
  channel isn't destroyed.
  """
  def delete_entry(channel, type) when type in ~w(avatar banner) do
    delete(cache_key(channel.id, type))
    :ok
  end

  # --- Private ---

  defp cache_key(channel_id, type), do: "channel:#{channel_id}:#{type}"

  defp do_refresh(channel, type, remote_url) do
    meta = read_meta(channel, type)
    etag = meta["etag"]
    headers = if etag, do: [{"if-none-match", etag}], else: []

    case Req.get(remote_url, headers: headers, redirect: true, max_redirects: 3) do
      {:ok, %Req.Response{status: 304}} ->
        # Not modified — warm the memory cache from disk if needed
        cache_key = cache_key(channel.id, type)

        case read_from_disk(channel, type) do
          {:ok, data, content_type} ->
            put(cache_key, {data, content_type})

          :miss ->
            :ok
        end

        :not_modified

      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} ->
        content_type = get_resp_header(resp_headers, "content-type") || "image/jpeg"
        new_etag = get_resp_header(resp_headers, "etag")
        ext = extension_from_content_type(content_type)

        write_to_disk(channel, type, body, ext)

        write_meta(channel, type, %{
          "content_type" => content_type,
          "etag" => new_etag,
          "ext" => ext
        })

        cache_key = cache_key(channel.id, type)
        put(cache_key, {body, content_type})

        Logger.debug("ImageCache: refreshed #{type} for channel #{channel.id}")
        :refreshed

      {:ok, %Req.Response{status: status}} ->
        Logger.warning(
          "ImageCache: unexpected status #{status} refreshing #{type} for channel #{channel.id}"
        )

        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning(
          "ImageCache: error refreshing #{type} for channel #{channel.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp fetch_and_store(_channel, _type, nil), do: {:error, :no_url}

  defp fetch_and_store(channel, type, remote_url) do
    case Req.get(remote_url, redirect: true, max_redirects: 3) do
      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} ->
        content_type = get_resp_header(resp_headers, "content-type") || "image/jpeg"
        etag = get_resp_header(resp_headers, "etag")
        ext = extension_from_content_type(content_type)

        write_to_disk(channel, type, body, ext)
        write_meta(channel, type, %{"content_type" => content_type, "etag" => etag, "ext" => ext})

        cache_key = cache_key(channel.id, type)
        put(cache_key, {body, content_type})

        Logger.debug("ImageCache: fetched #{type} for channel #{channel.id}")
        {:ok, body, content_type}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning(
          "ImageCache: unexpected status #{status} fetching #{type} for channel #{channel.id}"
        )

        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning(
          "ImageCache: error fetching #{type} for channel #{channel.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Disk I/O

  defp read_from_disk(channel, type) do
    meta = read_meta(channel, type)
    ext = meta["ext"]
    content_type = meta["content_type"]

    if ext do
      path = image_path(channel, type, ext)

      case File.read(path) do
        {:ok, data} -> {:ok, data, content_type}
        {:error, _} -> :miss
      end
    else
      :miss
    end
  end

  defp write_to_disk(channel, type, data, ext) do
    path = image_path(channel, type, ext)
    policy = load_media_policy!()
    :ok = apply_permissions!(MediaPermissions.mkdir_p(Path.dirname(path), policy))
    :ok = apply_permissions!(MediaPermissions.write_file(path, data, policy))
  end

  defp image_path(channel, type, ext) do
    Path.join(channel.base_path, "#{type}.#{ext}")
  end

  # Metadata sidecar (JSON)

  defp meta_path(channel, type) do
    Path.join(channel.base_path, "#{type}.meta")
  end

  defp read_meta(channel, type) do
    path = meta_path(channel, type)

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, meta} -> meta
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp write_meta(channel, type, meta) do
    path = meta_path(channel, type)
    policy = load_media_policy!()
    :ok = apply_permissions!(MediaPermissions.mkdir_p(Path.dirname(path), policy))
    :ok = apply_permissions!(MediaPermissions.write_file(path, Jason.encode!(meta), policy))
  end

  defp load_media_policy! do
    case MediaPermissions.load_policy() do
      {:ok, policy} -> policy
      {:error, reason} -> raise MediaPermissions.error_message(reason)
    end
  end

  defp apply_permissions!(:ok), do: :ok

  defp apply_permissions!({:error, reason}) do
    raise MediaPermissions.error_message(reason)
  end

  # Header helpers (Req v0.5 uses %{String.t() => [String.t()]} format)

  defp get_resp_header(headers, key) do
    case Map.get(headers, key) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp extension_from_content_type(content_type) do
    case content_type do
      "image/jpeg" <> _ -> "jpg"
      "image/png" <> _ -> "png"
      "image/webp" <> _ -> "webp"
      "image/gif" <> _ -> "gif"
      _ -> "jpg"
    end
  end
end
