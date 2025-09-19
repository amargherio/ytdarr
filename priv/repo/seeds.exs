# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ytdarr.Repo.insert!(%Ytdarr.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Ytdarr.Repo
alias Ytdarr.Content.{Channel, Playlist, Video}

# Insert two tracked channels if they don't already exist
Repo.insert!(%Channel{
  name: "Example Channel 1",
  external_id: "UC_x5XG1OV2P6uZZ5FSM9Ttw", # Example YouTube channel ID
  is_monitored: true,
  is_monitored_since: DateTime.utc_now()
}, on_conflict: :nothing, conflict_target: :external_id)


Repo.insert!(%Channel{
  name: "Dirty Civilian",
  external_id: "UC7X2IY5-ZHKU83nyb6KejgQ",
  url: "https://www.youtube.com/@dirty-civilian",
  platform: "YouTube",
  avatar_url: "https://yt3.ggpht.com/6wKGx6egmT19yKwew0Ij8O7wlI0DRFMLcA95tfKUnHioR-JX48hTSZ1A5NAB7lfZ7Fqraz9jrJ4=s800-c-k-c0x00ffffff-no-rj",
  banner_url: "https://yt3.googleusercontent.com/7nfUr0b3CNS01SeLm63TJhU1cdME-OkFgVDPGnE0-R1UgSuW7dODJnjX1osYOAQcfhIzlMvORw",
  description: "Our mission is to inspire and inform capable men to build strong families and resilient communities.\nWe cover a variety of topics and subjects involving survival, bushcraft, modern military tech, and marksmanship fundamentals.\nMerch and resources available at https://www.dirtycivilian.com\n\nHosts: Drew Hopkins & Josh Lowry\nVideographer: Chad Barber (RIP Nick Jones)\nScript & Research: Jonathan Fisher\n",

  is_monitored: true,
  is_monitored_since: DateTime.utc_now(),
  last_checked_at: DateTime.utc_now(),

  base_path: "dirty-civilian",
  generic_video_path: "dirty-civilian/videos"
}, on_conflict: :nothing, conflict_target: :external_id)


# Insert uploads playlists for Dirty Civilian
channel = Repo.get_by(Channel, external_id: "UC7X2IY5-ZHKU83nyb6KejgQ")
if channel do
  Repo.insert!(%Playlist{
    name: "Uploads",
    external_id: "UU7X2IY5-ZHKU83nyb6KejgQ", # YouTube uploads playlist ID
    url: "https://www.youtube.com/playlist?list=UU7X2IY5-ZHKU83nyb6KejgQ",
    description: "All uploads from Dirty Civilian",
    video_count: 100, # Example count
    is_monitored: true,
    is_monitored_since: DateTime.utc_now(),
    download_path: Path.join([channel.base_path, "Uploads"]),
    channel_id: channel.id
  }, on_conflict: :nothing, conflict_target: :external_id)

  Repo.insert!(%Playlist{
    name: "Skills, Mindset, & Education",
    external_id: "PLsiqs19rXW_CSQbkftlmUzaJJPo5Na9_N",
    url: "https://www.youtube.com/playlist?list=PLsiqs19rXW_CSQbkftlmUzaJJPo5Na9_N",
    description: "A collection of our videos that focus on developing our hard skills, mindset, and education on specific subjects.",
    video_count: 63,
    is_monitored: true,
    is_monitored_since: DateTime.utc_now(),
    download_path: Path.join([channel.base_path, "Skills_Mindset_Education"]),
    channel_id: channel.id
  }, on_conflict: :nothing, conflict_target: :external_id)

  # Insert first up to four videos from the scratch output JSON and associate to the Uploads playlist
  uploads_playlist = Repo.get_by(Playlist, external_id: "UU7X2IY5-ZHKU83nyb6KejgQ")

  if uploads_playlist do
    list_videos_path = Path.expand("../../scratch-output/list-video.yt.json", __DIR__)

    with true <- File.exists?(list_videos_path),
         {:ok, body} <- File.read(list_videos_path),
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
            get_in(snippet, ["thumbnails", "maxres", "url"]) # preference order, falling back if needed

        video_attrs = %{
          title: title,
          external_id: video_id,
          url: "https://www.youtube.com/watch?v=#{video_id}",
          description: description,
          upload_date: upload_date,
          thumbnail_url: thumb_url,
          channel_id: channel.id
        }

        # Insert the video if it does not exist
        {:ok, video} =
          case Repo.insert(Video.changeset(%Video{}, video_attrs), on_conflict: :nothing, conflict_target: :external_id) do
            {:ok, struct} -> {:ok, struct}
            {:error, changeset} -> raise "Video insert failed: #{inspect(changeset.errors)}"
          end

        # If the video already existed, fetch it to get its id
        video = if video.id, do: video, else: Repo.get_by!(Video, external_id: video_id)

        # Associate to uploads playlist through join table (ignore duplicates)
        # Note: join table name per migration: playlist_videos
        Repo.insert_all(
          "playlist_videos",
          [
            %{
              playlist_id: uploads_playlist.id,
              video_id: video.id,
              position: idx, # position in uploads ordering (best effort)
              added_at: DateTime.utc_now(),
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }
          ],
          on_conflict: :nothing
        )
      end)
    else
      _ -> :noop
    end
  end
end
