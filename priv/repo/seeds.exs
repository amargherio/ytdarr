# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This script uses Ash domain functions to create seed data.

alias Ytdarr.Content
alias Ytdarr.Content.PlaylistVideo

require Ash.Query

# Helper to get or create a channel
defmodule Seeds do
  require Ash.Query

  def get_or_create_channel(attrs) do
    case Content.get_channel_by_external_id(attrs.external_id) do
      {:ok, channel} ->
        IO.puts("Channel '#{channel.name}' already exists")
        channel

      {:error, _} ->
        case Content.create_channel(attrs) do
          {:ok, channel} ->
            IO.puts("Created channel '#{channel.name}'")
            channel

          {:error, error} ->
            raise "Failed to create channel: #{inspect(error)}"
        end
    end
  end

  def get_or_create_playlist(channel_id, attrs) do
    case Content.get_playlist_by_external_id(attrs.external_id) do
      {:ok, playlist} ->
        IO.puts("Playlist '#{playlist.name}' already exists")
        playlist

      {:error, _} ->
        case Content.create_playlist(channel_id, attrs) do
          {:ok, playlist} ->
            IO.puts("Created playlist '#{playlist.name}'")
            playlist

          {:error, error} ->
            raise "Failed to create playlist: #{inspect(error)}"
        end
    end
  end

  def get_or_create_video(channel_id, attrs) do
    case Content.get_video_by_external_id(attrs.external_id) do
      {:ok, video} ->
        IO.puts("Video '#{video.title}' already exists")
        video

      {:error, _} ->
        case Content.create_video(channel_id, attrs) do
          {:ok, video} ->
            IO.puts("Created video '#{video.title}'")
            video

          {:error, error} ->
            raise "Failed to create video: #{inspect(error)}"
        end
    end
  end

  def link_video_to_playlist(playlist_id, video_id, position) do
    # Check if already linked
    case Ash.read(
           Ash.Query.filter(PlaylistVideo, playlist_id == ^playlist_id and video_id == ^video_id)
         ) do
      {:ok, [_existing | _]} ->
        IO.puts("Video #{video_id} already linked to playlist #{playlist_id}")
        :ok

      {:ok, []} ->
        case Ash.create(PlaylistVideo, %{
               playlist_id: playlist_id,
               video_id: video_id,
               position: position
             }) do
          {:ok, _} ->
            IO.puts("Linked video #{video_id} to playlist #{playlist_id} at position #{position}")
            :ok

          {:error, error} ->
            IO.puts("Failed to link video: #{inspect(error)}")
            :error
        end

      {:error, error} ->
        IO.puts("Error checking playlist_video: #{inspect(error)}")
        :error
    end
  end
end

# Create the Dirty Civilian channel
channel =
  Seeds.get_or_create_channel(%{
    name: "Dirty Civilian",
    external_id: "UC7X2IY5-ZHKU83nyb6KejgQ",
    url: "https://www.youtube.com/@dirty-civilian",
    platform: "YouTube",
    avatar_url:
      "https://yt3.ggpht.com/6wKGx6egmT19yKwew0Ij8O7wlI0DRFMLcA95tfKUnHioR-JX48hTSZ1A5NAB7lfZ7Fqraz9jrJ4=s800-c-k-c0x00ffffff-no-rj",
    banner_url:
      "https://yt3.googleusercontent.com/7nfUr0b3CNS01SeLm63TJhU1cdME-OkFgVDPGnE0-R1UgSuW7dODJnjX1osYOAQcfhIzlMvORw",
    description:
      "Our mission is to inspire and inform capable men to build strong families and resilient communities.\nWe cover a variety of topics and subjects involving survival, bushcraft, modern military tech, and marksmanship fundamentals.\nMerch and resources available at https://www.dirtycivilian.com\n\nHosts: Drew Hopkins & Josh Lowry\nVideographer: Chad Barber (RIP Nick Jones)\nScript & Research: Jonathan Fisher\n",
    platform_username: "@dirty-civilian",
    is_monitored: true
  })

# Create Uploads playlist
uploads_playlist =
  Seeds.get_or_create_playlist(channel.id, %{
    name: "Uploads",
    external_id: "UU7X2IY5-ZHKU83nyb6KejgQ",
    url: "https://www.youtube.com/playlist?list=UU7X2IY5-ZHKU83nyb6KejgQ",
    description: "All uploads from Dirty Civilian",
    video_count: 100,
    is_monitored: true
  })

# Create Skills playlist
_skills_playlist =
  Seeds.get_or_create_playlist(channel.id, %{
    name: "Skills, Mindset, & Education",
    external_id: "PLsiqs19rXW_CSQbkftlmUzaJJPo5Na9_N",
    url: "https://www.youtube.com/playlist?list=PLsiqs19rXW_CSQbkftlmUzaJJPo5Na9_N",
    description:
      "A collection of our videos that focus on developing our hard skills, mindset, and education on specific subjects.",
    video_count: 63,
    is_monitored: true
  })

# Load videos from scratch output if available
list_videos_path = Path.expand("../../scratch-output/list-video.yt.json", __DIR__)

if File.exists?(list_videos_path) do
  IO.puts("\nLoading videos from #{list_videos_path}...")

  with {:ok, raw} <- File.read(list_videos_path),
       body <- raw |> String.split("\n") |> Enum.drop(6) |> Enum.join("\n"),
       {:ok, %{"items" => items}} <- Jason.decode(body) do
    items
    |> Enum.take(4)
    |> Enum.with_index(1)
    |> Enum.each(fn {item, idx} ->
      snippet = item["snippet"] || %{}
      video_id = item["id"]
      title = snippet["title"] || "(no title)"
      description = snippet["description"]
      published_at = snippet["publishedAt"]

      upload_date =
        case DateTime.from_iso8601(published_at || "") do
          {:ok, dt, _} -> DateTime.to_date(dt)
          _ -> nil
        end

      thumb_url =
        get_in(snippet, ["thumbnails", "high", "url"]) ||
          get_in(snippet, ["thumbnails", "default", "url"]) ||
          get_in(snippet, ["thumbnails", "medium", "url"]) ||
          get_in(snippet, ["thumbnails", "standard", "url"]) ||
          get_in(snippet, ["thumbnails", "maxres", "url"])

      video =
        Seeds.get_or_create_video(channel.id, %{
          title: title,
          external_id: video_id,
          url: "https://www.youtube.com/watch?v=#{video_id}",
          description: description,
          upload_date: upload_date,
          thumbnail_url: thumb_url
        })

      # Link video to uploads playlist
      Seeds.link_video_to_playlist(uploads_playlist.id, video.id, idx)
    end)

    IO.puts("\nSeeding complete!")
  else
    error ->
      IO.puts("Could not parse videos JSON: #{inspect(error)}")
  end
else
  IO.puts("\nNo videos JSON found at #{list_videos_path}, skipping video seeding.")
  IO.puts("Seeding complete!")
end
