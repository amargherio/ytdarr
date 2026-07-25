defmodule Ytdarr.Media.VideoArtifacts do
  @moduledoc """
  Builds and manages the canonical on-disk artifacts for a channel video.
  """

  alias Ytdarr.Content.{Channel, Video}
  alias Ytdarr.MediaPermissions
  alias Ytdarr.MediaPermissions.Policy

  require Ash.Query

  @video_extensions MapSet.new([
                      ".mp4",
                      ".mkv",
                      ".webm",
                      ".mov",
                      ".m4v",
                      ".avi",
                      ".mpg",
                      ".mpeg",
                      ".ts",
                      ".m2ts",
                      ".wmv",
                      ".flv",
                      ".ogv"
                    ])

  defmodule Destination do
    @moduledoc false

    @enforce_keys [
      :season_directory,
      :basename,
      :media_path,
      :nfo_path,
      :episode_number,
      :extension
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            season_directory: Path.t(),
            basename: String.t(),
            media_path: Path.t(),
            nfo_path: Path.t(),
            episode_number: pos_integer(),
            extension: String.t()
          }
  end

  @doc "Builds the canonical media and NFO paths for a video."
  @spec build_destination(%Channel{}, %Video{}, String.t()) ::
          {:ok, Destination.t()}
          | {:error, :missing_upload_date | :unsupported_extension | term()}
  def build_destination(%Channel{} = channel, %Video{} = video, extension) do
    with {:ok, extension} <- normalize_extension(extension),
         {:ok, year} <- upload_year(video),
         {:ok, episode_number} <- episode_number(video),
         {:ok, base_path} <- channel_base_path(channel) do
      season_directory = Path.join(base_path, "Season #{year}")

      basename =
        "#{sanitize_filename_segment(channel.name)} - " <>
          "S#{year}E#{String.pad_leading(Integer.to_string(episode_number), 3, "0")} - " <>
          "#{sanitize_filename_segment(video.title)}#{extension}"

      media_path = Path.join(season_directory, basename)

      {:ok,
       %Destination{
         season_directory: season_directory,
         basename: basename,
         media_path: media_path,
         nfo_path: Path.rootname(media_path) <> ".nfo",
         episode_number: episode_number,
         extension: extension
       }}
    end
  end

  @doc "Returns the one-based episode number in the video's channel and upload year."
  @spec episode_number(%Video{}) :: {:ok, pos_integer()} | {:error, term()}
  def episode_number(%Video{upload_date: nil}), do: {:error, :missing_upload_date}

  def episode_number(%Video{upload_date: %Date{} = upload_date, channel_id: channel_id, id: id})
      when is_integer(channel_id) and is_integer(id) do
    year_string = Integer.to_string(upload_date.year)

    query =
      Video
      |> Ash.Query.filter(channel_id == ^channel_id)
      |> Ash.Query.filter(fragment("strftime('%Y', ?)", upload_date) == ^year_string)
      |> Ash.Query.filter(
        upload_date < ^upload_date or
          (upload_date == ^upload_date and id < ^id)
      )

    case Ash.read(query) do
      {:ok, videos} -> {:ok, length(videos) + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  def episode_number(_video), do: {:error, :invalid_video}

  @doc "Writes Ytdarr's canonical episode NFO file using the configured file policy."
  @spec write_nfo(Path.t(), %Video{}, pos_integer(), Policy.t()) :: :ok | {:error, term()}
  def write_nfo(_path, %Video{upload_date: nil}, _episode_number, %Policy{}) do
    {:error, :missing_upload_date}
  end

  def write_nfo(
        path,
        %Video{upload_date: %Date{} = upload_date} = video,
        episode_number,
        %Policy{} = policy
      )
      when is_binary(path) and is_integer(episode_number) and episode_number > 0 do
    contents = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n",
      "<episodedetails>\n",
      "  <title>",
      xml_escape(video.title),
      "</title>\n",
      "  <season>",
      xml_escape(upload_date.year),
      "</season>\n",
      "  <episode>",
      xml_escape(episode_number),
      "</episode>\n",
      "  <plot>",
      xml_escape(video.description),
      "</plot>\n",
      "  <aired>",
      xml_escape(Date.to_iso8601(upload_date)),
      "</aired>\n",
      "  <uniqueid type=\"youtube\" default=\"true\">",
      xml_escape(video.external_id),
      "</uniqueid>\n",
      "  <url>",
      xml_escape(video.url),
      "</url>\n",
      "</episodedetails>\n"
    ]

    MediaPermissions.write_file(path, contents, policy)
  end

  def write_nfo(_path, _video, _episode_number, _policy), do: {:error, :invalid_nfo_arguments}

  @doc "Lists regular canonical media artifacts without following symbolic links."
  @spec existing_artifacts(Path.t()) :: {:ok, [Path.t()]} | {:error, term()}
  def existing_artifacts(media_path) when is_binary(media_path) do
    directory = Path.dirname(media_path)
    prefix = Path.rootname(Path.basename(media_path)) <> "."

    with {:ok, entries} <- File.ls(directory) do
      entries
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, artifacts} ->
        if String.starts_with?(entry, prefix) do
          path = Path.join(directory, entry)

          case File.lstat(path) do
            {:ok, %{type: :regular}} -> {:cont, {:ok, [path | artifacts]}}
            {:ok, _stat} -> {:cont, {:ok, artifacts}}
            {:error, reason} -> {:halt, {:error, {:lstat, path, reason}}}
          end
        else
          {:cont, {:ok, artifacts}}
        end
      end)
      |> sort_artifacts()
    end
  end

  def existing_artifacts(_media_path), do: {:error, :invalid_media_path}

  defp normalize_extension(extension) when is_binary(extension) do
    extension = String.downcase(extension)

    if MapSet.member?(@video_extensions, extension) do
      {:ok, extension}
    else
      {:error, :unsupported_extension}
    end
  end

  defp normalize_extension(_extension), do: {:error, :unsupported_extension}

  defp upload_year(%Video{upload_date: %Date{year: year}}), do: {:ok, year}
  defp upload_year(%Video{upload_date: nil}), do: {:error, :missing_upload_date}
  defp upload_year(_video), do: {:error, :missing_upload_date}

  defp channel_base_path(%Channel{base_path: base_path})
       when is_binary(base_path) and base_path != "",
       do: {:ok, base_path}

  defp channel_base_path(_channel), do: {:error, :missing_channel_base_path}

  defp sanitize_filename_segment(nil), do: ""

  defp sanitize_filename_segment(value) do
    value
    |> to_string()
    |> String.replace(~r/[\/\\?%*:|"<>]/, "_")
    |> String.trim()
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

  defp sort_artifacts({:ok, artifacts}), do: {:ok, Enum.sort(artifacts)}
  defp sort_artifacts({:error, reason}), do: {:error, reason}
end
