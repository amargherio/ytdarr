# lib/video_downloader/services/youtube/models.ex
defmodule Ytdarr.Services.YouTube.Models do
  @moduledoc """
  Data structures for YouTube API responses.
  """

  defmodule APIResponse do
    defstruct [:kind, :next_page_token, :prev_page_token, :page_info, :items]

    def from_api(data) do
      %__MODULE__{
        kind: data["kind"],
        next_page_token: data["nextPageToken"],
        prev_page_token: data["prevPageToken"],
        page_info: data["pageInfo"],
        items: data["items"] || []
      }
    end
  end

  defmodule Channel do
    @enforce_keys [:id, :title, :url]
    defstruct [
      :id,
      :title,
      :description,
      :url,
      :thumbnail_url,
      :subscriber_count,
      :video_count,
      :view_count,
      :banner_url,
      :custom_url,
      :uploads_playlist_id,
      :status,
      :contentDetails
    ]

    def from_api(%{"id" => id, "snippet" => snippet} = data) do
      brandSettings = Map.get(data, "brandingSettings", %{}) || %{}
      status = Map.get(data, "status", %{}) || %{}
      statistics = Map.get(data, "statistics", %{})
      contentDetails = Map.get(data, "contentDetails", %{})

      url =
        if snippet["customUrl"] do
          "https://www.youtube.com/#{snippet["customUrl"]}"
        else
          "https://www.youtube.com/channel/#{id}"
        end

      %__MODULE__{
        id: id,
        title: snippet["title"],
        description: snippet["description"],
        url: url,
        thumbnail_url: get_in(snippet, ["thumbnails", "high", "url"]),
        subscriber_count: parse_int(statistics["subscriberCount"]),
        video_count: parse_int(statistics["videoCount"]),
        view_count: parse_int(statistics["viewCount"]),
        banner_url: get_in(brandSettings, ["image", "bannerExternalUrl"]),
        custom_url: snippet["customUrl"],
        uploads_playlist_id: get_in(contentDetails, ["relatedPlaylists", "uploads"]),
        status: status,
        contentDetails: contentDetails
      }
    end

    defp parse_int(nil), do: nil
    defp parse_int(str) when is_binary(str), do: String.to_integer(str)
    defp parse_int(int) when is_integer(int), do: int
  end

  defmodule Video do
    @enforce_keys [:id, :title, :url]
    defstruct [
      :id,
      :title,
      :description,
      :url,
      :thumbnail_url,
      :published_at,
      :duration,
      :view_count,
      :channel_id
    ]

    def from_api(%{"id" => id_data, "snippet" => snippet}) when is_map(id_data) do
      video_id = id_data["videoId"]
      from_api(%{"id" => video_id, "snippet" => snippet})
    end

    def from_api(%{"id" => video_id, "snippet" => snippet}) do
      %__MODULE__{
        id: video_id,
        title: snippet["title"],
        description: snippet["description"],
        url: "https://www.youtube.com/watch?v=#{video_id}",
        thumbnail_url: get_in(snippet, ["thumbnails", "high", "url"]),
        published_at: parse_date(snippet["publishedAt"]),
        channel_id: snippet["channelId"]
      }
    end

    def from_api(%{"snippet" => %{"resourceId" => %{"videoId" => video_id}} = snippet}) do
      from_api(%{"id" => video_id, "snippet" => snippet})
    end

    # delegate to Parser for date parsing (avoids reflective send/2 usage)
    defp parse_date(d), do: Ytdarr.Services.YouTube.Parser.parse_date(d)
  end

  defmodule Playlist do
    @enforce_keys [:id, :title, :url]
    defstruct [:id, :title, :description, :url, :thumbnail_url, :video_count, :channel_id]

    def from_api(%{"id" => id, "snippet" => snippet} = data) do
      content_details = Map.get(data, "contentDetails", %{})

      %__MODULE__{
        id: id,
        title: snippet["title"],
        description: snippet["description"],
        url: "https://www.youtube.com/playlist?list=#{id}",
        thumbnail_url: get_in(snippet, ["thumbnails", "high", "url"]),
        video_count: content_details["itemCount"],
        channel_id: snippet["channelId"]
      }
    end
  end

  defmodule PlaylistImages do
    @moduledoc """
    Holds the different thumbnail image variants for a playlist (or playlist item video).

    Each field is a map with the raw data for that resolution, typically containing
    width, height, and url, or nil if not provided by the API.
    """
    defstruct [:default, :medium, :high, :standard, :maxres]

    def from_api(nil), do: %__MODULE__{}

    def from_api(data) when is_map(data) do
      %__MODULE__{
        default: Map.get(data, "default"),
        medium: Map.get(data, "medium"),
        high: Map.get(data, "high"),
        standard: Map.get(data, "standard"),
        maxres: Map.get(data, "maxres")
      }
    end

    def from_api(_), do: %__MODULE__{}
  end

  defmodule PlaylistItem do
    @moduledoc """
    Represents an item within a YouTube playlist (playlistItems endpoint).

    Fields are derived from the playlistItems API resource:
    https://developers.google.com/youtube/v3/docs/playlistItems#resource
    """
    @enforce_keys [:id, :playlist_id, :video_id, :title, :url]
    defstruct [
      :id,
      :playlist_id,
      :video_id,
      :title,
      :description,
      :position,
      :url,
      :thumbnail_url,
      :published_at,
      :video_published_at,
      :channel_id,
      :channel_title,
      :video_owner_channel_title,
      :video_owner_channel_id,
      :status,
      :images
    ]

    # Accepts a raw playlistItems resource map and converts to struct
    def from_api(%{"id" => id, "snippet" => snippet} = data) do
      content_details = Map.get(data, "contentDetails", %{})
      status = Map.get(data, "status", %{})
      thumbnails = Map.get(snippet, "thumbnails")
      video_id = get_in(snippet, ["resourceId", "videoId"]) || content_details["videoId"]
      playlist_id = snippet["playlistId"]

      %__MODULE__{
        id: id,
        playlist_id: playlist_id,
        video_id: video_id,
        title: snippet["title"],
        description: snippet["description"],
        position: snippet["position"],
        url:
          if(video_id,
            do: "https://www.youtube.com/watch?v=#{video_id}&list=#{playlist_id}",
            else: nil
          ),
        thumbnail_url:
          get_in(thumbnails, ["high", "url"]) || get_in(thumbnails, ["default", "url"]),
        published_at: parse_date(snippet["publishedAt"]),
        video_published_at: parse_date(content_details["videoPublishedAt"]),
        channel_id: snippet["channelId"],
        channel_title: snippet["channelTitle"],
        video_owner_channel_title: snippet["videoOwnerChannelTitle"],
        video_owner_channel_id: snippet["videoOwnerChannelId"],
        status: status,
        images: Ytdarr.Services.YouTube.Models.PlaylistImages.from_api(thumbnails)
      }
    end

    def from_api(_), do: nil

    # Local date parsing duplicated from Video module; may be refactored.
    defp parse_date(d), do: Ytdarr.Services.YouTube.Parser.parse_date(d)
  end

  defmodule DownloadInfo do
    defstruct [:url, :title, :formats, :duration, :file_size]

    def from_json(data) do
      %__MODULE__{
        url: data["webpage_url"],
        title: data["title"],
        formats: parse_formats(data["formats"]),
        duration: data["duration"],
        file_size: get_best_format_filesize(data["formats"])
      }
    end

    defp parse_formats(formats) when is_list(formats) do
      formats
      # Video formats only
      |> Enum.filter(&(&1["vcodec"] != "none"))
      |> Enum.map(fn format ->
        %{
          format_id: format["format_id"],
          ext: format["ext"],
          quality: format["height"],
          filesize: format["filesize"]
        }
      end)
    end

    defp parse_formats(_), do: []

    defp get_best_format_filesize(formats) when is_list(formats) do
      formats
      |> Enum.filter(&(&1["vcodec"] != "none" && &1["filesize"]))
      |> Enum.max_by(&(&1["height"] || 0), fn -> %{"filesize" => nil} end)
      |> Map.get("filesize")
    end

    defp get_best_format_filesize(_), do: nil
  end
end
