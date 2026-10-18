defmodule Ytdarr.Media.ChannelArtifacts do
  @moduledoc "Creates the channel's Jellyfin show directory and local metadata."

  alias Ytdarr.Cache.ImageCache
  alias Ytdarr.MediaPermissions

  def prepare(channel, policy) do
    with :ok <- MediaPermissions.mkdir_p(channel.base_path, policy),
         :ok <- MediaPermissions.mkdir_p(channel.generic_video_path, policy) do
      :ok
    end
  end

  def write_nfo(channel, policy) do
    contents =
      IO.iodata_to_binary([
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n",
        "<tvshow>\n",
        "  <title>",
        xml_escape(channel.name),
        "</title>\n",
        "  <plot>",
        xml_escape(channel.description),
        "</plot>\n",
        "  <uniqueid type=\"youtube\" default=\"true\">",
        xml_escape(channel.external_id),
        "</uniqueid>\n",
        "  <url>",
        xml_escape(channel.url),
        "</url>\n",
        image_tag(channel, "avatar", "poster"),
        image_tag(channel, "banner", "banner"),
        "</tvshow>\n"
      ])

    path = Path.join(channel.base_path, "tvshow.nfo")

    case File.read(path) do
      {:ok, ^contents} -> :ok
      _ -> MediaPermissions.write_file(path, contents, policy)
    end
  end

  defp image_tag(channel, type, aspect) do
    case ImageCache.image_filename(channel, type) do
      nil -> []
      filename -> ["  <thumb aspect=\"", aspect, "\">", xml_escape(filename), "</thumb>\n"]
    end
  end

  defp xml_escape(nil), do: ""

  defp xml_escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
