defmodule Ytdarr.ObanWorkers.VideoDownloaderTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo

  import Ytdarr.ContentFixtures

  alias Ytdarr.{Content, Settings}
  alias Ytdarr.ObanWorkers.VideoDownloader

  setup do
    artifact_root =
      Path.join([
        File.cwd!(),
        ".test-artifacts",
        "video_downloader_test",
        Integer.to_string(System.unique_integer([:positive]))
      ])

    bin_dir = Path.join(artifact_root, "bin")
    downloads_root = Path.join(artifact_root, "downloads")
    script_path = Path.join(bin_dir, "yt-dlp")

    File.mkdir_p!(bin_dir)

    File.write!(script_path, yt_dlp_stub_script())
    File.chmod!(script_path, 0o755)

    original_path = System.get_env("PATH", "")
    System.put_env("PATH", "#{bin_dir}:#{original_path}")

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf!(artifact_root)
    end)

    {:ok, downloads_root: downloads_root}
  end

  describe "calculate_episode_number/3" do
    test "returns 1 for the first video in a year" do
      channel = channel_fixture()
      video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-01]})

      assert VideoDownloader.calculate_episode_number(channel, 2025, video) == 1
    end

    test "orders videos by upload date within the same channel and year" do
      channel = channel_fixture()

      first_video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-01]})
      second_video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-15]})
      third_video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-02-01]})

      assert VideoDownloader.calculate_episode_number(channel, 2025, first_video) == 1
      assert VideoDownloader.calculate_episode_number(channel, 2025, second_video) == 2
      assert VideoDownloader.calculate_episode_number(channel, 2025, third_video) == 3
    end

    test "counts only videos from the same channel and year" do
      channel = channel_fixture()
      other_channel = channel_fixture()

      _previous_year_video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2024-12-31]})

      _other_channel_video =
        video_fixture(%{channel_id: other_channel.id, upload_date: ~D[2025-01-01]})

      target_video = video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-01]})

      assert VideoDownloader.calculate_episode_number(channel, 2025, target_video) == 1
    end
  end

  describe "retrieve_ytdlp_parameters/0" do
    test "returns the built-in defaults when no default param set exists" do
      clear_default_param_sets()

      params = VideoDownloader.retrieve_ytdlp_parameters()

      assert "--embed-chapters" in params
      assert "--embed-thumbnails" in params
      assert "--embed-subs" in params
      refute "-f" in params
    end

    test "merges the default param set format and extra args" do
      assert {:ok, _param_set} =
               Settings.create_yt_dlp_param_set(%{
                 name: "Default #{System.unique_integer([:positive])}",
                 format: "bestvideo+bestaudio",
                 extra_args: "--no-playlist --quiet",
                 is_default: true
               })

      params = VideoDownloader.retrieve_ytdlp_parameters()

      assert "--embed-chapters" in params
      assert "-f" in params
      assert "bestvideo+bestaudio" in params
      assert "--no-playlist" in params
      assert "--quiet" in params
    end
  end

  describe "perform/1" do
    test "downloads to a sanitized filename and generates an nfo file", %{
      downloads_root: downloads_root
    } do
      deactivate_all_media_root_folders()
      assert {:ok, _folder} = Settings.create_media_root_folder(%{path: downloads_root})

      unique = System.unique_integer([:positive])

      channel =
        channel_fixture(%{
          name: "Channel/Name?",
          external_id: "channel-#{unique}"
        })

      video =
        video_fixture(%{
          channel_id: channel.id,
          title: "Video:Title*?",
          description: "Generated description",
          external_id: "video-#{unique}",
          upload_date: ~D[2025-03-01]
        })

      assert :ok =
               perform_job(VideoDownloader, %{
                 "video_id" => video.id,
                 "channel_id" => channel.id
               })

      updated_video = Content.get_video!(video.id)

      expected_path =
        Path.join([
          channel.base_path,
          "Season 2025",
          "Channel_Name_ - S2025E001 - Video_Title__.mp4"
        ])

      assert updated_video.is_downloaded
      assert updated_video.download_state == :downloaded
      assert updated_video.download_path == expected_path
      assert File.exists?(expected_path)

      nfo_path = String.replace_suffix(expected_path, ".mp4", ".nfo")
      assert File.exists?(nfo_path)

      nfo_contents = File.read!(nfo_path)
      assert nfo_contents =~ "<title>Video:Title*?</title>"
      assert nfo_contents =~ "<season>2025</season>"
      assert nfo_contents =~ "<episode>1</episode>"
      assert nfo_contents =~ "<plot>Generated description</plot>"
      assert nfo_contents =~ "<aired>2025-03-01</aired>"
      assert nfo_contents =~ "<uniqueid type=\"youtube\" default=\"true\">#{video.id}</uniqueid>"
      assert nfo_contents =~ "<url>#{video.url}</url>"
    end
  end

  defp clear_default_param_sets do
    Enum.each(Settings.list_yt_dlp_param_sets!(), fn param_set ->
      Settings.update_yt_dlp_param_set(param_set, %{is_default: false})
    end)
  end

  defp deactivate_all_media_root_folders do
    Enum.each(Settings.list_media_root_folders!(), &Settings.deactivate_media_root_folder/1)
  end

  defp yt_dlp_stub_script do
    """
    #!/bin/sh
    output=""
    previous=""

    for arg in "$@"; do
      if [ "$previous" = "-o" ]; then
        output="$arg"
      fi

      previous="$arg"
    done

    if [ -n "$output" ]; then
      mkdir -p "$(dirname "$output")"
      printf 'stub video' > "$output"
    fi

    exit 0
    """
  end
end
