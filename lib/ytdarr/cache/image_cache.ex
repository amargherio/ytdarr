defmodule Ytdarr.Cache.ImageCache do
  @moduledoc """
  Two-tier image cache for channel avatars and banners.

  Read-through flow: Nebulex (in-memory) → filesystem → remote URL.
  Jellyfin artwork is persisted as `poster.<ext>` for avatars and `banner.<ext>`
  for banners. The `avatar.meta` and `banner.meta` sidecars track the source URL,
  content type, ETag and Last-Modified validators. Legacy `avatar.<ext>` files
  migrate on disk reads without downloading the image again.
  """
  use Nebulex.Cache,
    otp_app: :ytdarr,
    adapter: Nebulex.Adapters.Local

  alias Ytdarr.MediaPermissions

  @type_config %{"avatar" => :avatar_url, "banner" => :banner_url}
  @extensions ~w(jpg jpeg png webp gif)

  @doc """
  Get a cached image for a channel. Falls through from memory → disk → remote.

  Returns `{:ok, binary, content_type}` or `{:error, reason}`.
  """
  def get_image(channel, type) when type in ~w(avatar banner) do
    case fetch(cache_key(channel.id, type)) do
      {:ok, {data, content_type}} when is_binary(data) ->
        {:ok, data, content_type}

      {:error, %Nebulex.KeyError{}} ->
        case read_from_disk(channel, type) do
          {:ok, data, content_type} ->
            put(cache_key(channel.id, type), {data, content_type})
            {:ok, data, content_type}

          :miss ->
            fetch_and_store(channel, type, Map.get(channel, @type_config[type]))

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the basename of persisted artwork, or `nil` if it is unavailable.

  Legacy avatar artwork is migrated to the canonical poster filename on read.
  This function never downloads artwork.
  """
  def image_filename(channel, type) when type in ~w(avatar banner) do
    with {:ok, %{"ext" => ext} = meta} when ext in @extensions <- read_meta(channel, type) do
      path = image_path(channel, type, ext)

      case File.stat(path) do
        {:ok, %File.Stat{type: :regular}} ->
          Path.basename(path)

        {:error, :enoent} ->
          case read_from_disk(channel, type, meta) do
            {:ok, _, _} -> Path.basename(path)
            _ -> nil
          end

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  @doc """
  Refresh artwork, using validators only for an existing image from the same URL.

  Returns `:not_modified`, `:refreshed`, or `{:error, reason}`. Identical bytes,
  content type and source URL do not rewrite the persisted image.
  """
  def refresh(channel, type) when type in ~w(avatar banner) do
    case Map.get(channel, @type_config[type]) do
      nil ->
        {:error, :no_url}

      remote_url ->
        case do_refresh(channel, type, remote_url) do
          {:ok, status, _data, _content_type} -> status
          {:error, _} = error -> error
        end
    end
  end

  @doc """
  Evict a channel's image from the in-memory cache without deleting disk files.
  """
  def delete_entry(channel, type) when type in ~w(avatar banner) do
    delete(cache_key(channel.id, type))
    :ok
  end

  defp cache_key(channel_id, type), do: "channel:#{channel_id}:#{type}"

  defp do_refresh(channel, type, remote_url) do
    with {:ok, meta} <- read_meta(channel, type),
         disk when disk == :miss or elem(disk, 0) == :ok <-
           read_from_disk(channel, type, meta),
         {:ok, response} <-
           Req.get(remote_url,
             headers: conditional_headers(meta, disk, remote_url),
             redirect: true,
             max_redirects: 3,
             decode_body: false,
             retry: false
           ) do
      store_response(channel, type, remote_url, meta, disk, response)
    end
  end

  defp conditional_headers(%{"source_url" => url} = meta, {:ok, _, _}, url) do
    Enum.flat_map([{"etag", "if-none-match"}, {"last_modified", "if-modified-since"}], fn
      {key, header} -> if meta[key], do: [{header, meta[key]}], else: []
    end)
  end

  defp conditional_headers(_meta, _disk, _url), do: []

  defp store_response(
         channel,
         type,
         url,
         %{"source_url" => url},
         {:ok, data, content_type},
         %Req.Response{status: 304}
       ) do
    put(cache_key(channel.id, type), {data, content_type})
    {:ok, :not_modified, data, content_type}
  end

  defp store_response(channel, type, url, old_meta, disk, %Req.Response{
         status: 200,
         body: data,
         headers: headers
       }) do
    content_type = get_resp_header(headers, "content-type") || "image/jpeg"
    ext = extension_from_content_type(content_type)

    meta = %{
      "source_url" => url,
      "content_type" => content_type,
      "etag" => get_resp_header(headers, "etag"),
      "last_modified" => get_resp_header(headers, "last-modified"),
      "ext" => ext
    }

    unchanged =
      disk == {:ok, data, content_type} and old_meta["source_url"] == url and
        old_meta["ext"] == ext

    path = image_path(channel, type, ext)

    with {:ok, policy} <- MediaPermissions.load_policy(),
         :ok <- MediaPermissions.mkdir_p(channel.base_path, policy),
         :ok <- persist_image(path, data, unchanged, policy),
         :ok <- persist_meta(channel, type, old_meta, meta, policy),
         :ok <- remove_obsolete_images(channel, type, path) do
      put(cache_key(channel.id, type), {data, content_type})
      {:ok, if(unchanged, do: :not_modified, else: :refreshed), data, content_type}
    end
  end

  defp store_response(_channel, _type, _url, _meta, _disk, %Req.Response{status: status}) do
    {:error, {:http_status, status}}
  end

  defp fetch_and_store(_channel, _type, nil), do: {:error, :no_url}

  defp fetch_and_store(channel, type, remote_url) do
    case do_refresh(channel, type, remote_url) do
      {:ok, _status, data, content_type} -> {:ok, data, content_type}
      {:error, _} = error -> error
    end
  end

  defp read_from_disk(channel, type) do
    with {:ok, meta} <- read_meta(channel, type) do
      read_from_disk(channel, type, meta)
    end
  end

  defp read_from_disk(channel, type, %{"ext" => ext, "content_type" => content_type})
       when ext in @extensions and is_binary(content_type) do
    path = image_path(channel, type, ext)

    case File.read(path) do
      {:ok, data} -> {:ok, data, content_type}
      {:error, :enoent} -> read_legacy_image(channel, type, ext, content_type)
      {:error, _} = error -> error
    end
  end

  defp read_from_disk(_channel, _type, _meta), do: :miss

  defp read_legacy_image(channel, "avatar", ext, content_type) do
    legacy_path = Path.join(channel.base_path, "avatar.#{ext}")

    case File.read(legacy_path) do
      {:ok, data} ->
        with {:ok, policy} <- MediaPermissions.load_policy(),
             :ok <- MediaPermissions.mkdir_p(channel.base_path, policy),
             :ok <- MediaPermissions.apply_file(legacy_path, policy),
             :ok <- MediaPermissions.apply_file(meta_path(channel, "avatar"), policy),
             :ok <- File.rename(legacy_path, image_path(channel, "avatar", ext)),
             :ok <- remove_obsolete_images(channel, "avatar", image_path(channel, "avatar", ext)) do
          {:ok, data, content_type}
        end

      {:error, :enoent} ->
        :miss

      {:error, _} = error ->
        error
    end
  end

  defp read_legacy_image(_channel, _type, _ext, _content_type), do: :miss

  defp image_path(channel, type, ext) do
    basename = if type == "avatar", do: "poster", else: "banner"
    Path.join(channel.base_path, "#{basename}.#{ext}")
  end

  defp meta_path(channel, type), do: Path.join(channel.base_path, "#{type}.meta")

  defp read_meta(channel, type) do
    case File.read(meta_path(channel, type)) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, meta} when is_map(meta) -> {:ok, meta}
          _ -> {:ok, %{}}
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, _} = error ->
        error
    end
  end

  defp persist_image(_path, _data, true, _policy), do: :ok
  defp persist_image(path, data, false, policy), do: atomic_write(path, data, policy)

  defp persist_meta(_channel, _type, meta, meta, _policy), do: :ok

  defp persist_meta(channel, type, _old_meta, meta, policy) do
    atomic_write(meta_path(channel, type), Jason.encode!(meta), policy)
  end

  # Apply permissions before replacing the destination, so a failed write or
  # permission change cannot truncate existing artwork.
  defp atomic_write(path, data, policy) do
    temporary = path <> ".#{System.unique_integer([:positive])}.tmp"

    try do
      with :ok <- MediaPermissions.write_file(temporary, data, policy) do
        File.rename(temporary, path)
      end
    after
      File.rm(temporary)
    end
  end

  defp remove_obsolete_images(channel, type, current_path) do
    basenames = if type == "avatar", do: ["poster", "avatar"], else: ["banner"]

    for basename <- basenames, ext <- @extensions, reduce: :ok do
      :ok ->
        path = Path.join(channel.base_path, "#{basename}.#{ext}")

        if path == current_path do
          :ok
        else
          case File.rm(path) do
            :ok -> :ok
            {:error, :enoent} -> :ok
            {:error, _} = error -> error
          end
        end

      error ->
        error
    end
  end

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
