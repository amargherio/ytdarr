defmodule Ytdarr.Media.VideoArtifactsTest do
  use Ytdarr.DataCase

  import Ytdarr.ContentFixtures

  alias Ytdarr.Content.{Channel, Video}
  alias Ytdarr.Media.VideoArtifacts
  alias Ytdarr.MediaPermissions

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ytdarr-video-artifacts-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    gid = File.stat!(root).gid

    {:ok, policy} =
      MediaPermissions.build_policy(
        %{owner_group: "test-media", file_mode: "644", directory_mode: "755"},
        group_resolver: fn "test-media" -> {:ok, gid} end,
        current_gids: [gid]
      )

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, policy: policy}
  end

  test "builds the canonical season path with a lowercased retained extension", %{root: root} do
    channel = channel_fixture()

    video =
      video_fixture(%{
        channel_id: channel.id,
        title: "  Video:Title*?  ",
        upload_date: ~D[2025-03-01]
      })

    destination_channel = %Channel{name: "  Channel/Name?  ", base_path: root}

    assert {:ok, mkv} = VideoArtifacts.build_destination(destination_channel, video, ".MKV")
    assert {:ok, webm} = VideoArtifacts.build_destination(destination_channel, video, ".webm")
    assert {:ok, mp4} = VideoArtifacts.build_destination(destination_channel, video, ".mp4")

    expected_stem = "Channel_Name_ - S2025E001 - Video_Title__"
    expected_season = Path.join(root, "Season 2025")

    assert mkv.season_directory == expected_season
    assert mkv.basename == expected_stem <> ".mkv"
    assert mkv.media_path == Path.join(expected_season, expected_stem <> ".mkv")
    assert mkv.nfo_path == Path.join(expected_season, expected_stem <> ".nfo")
    assert mkv.episode_number == 1
    assert mkv.extension == ".mkv"
    assert webm.media_path == Path.join(expected_season, expected_stem <> ".webm")
    assert mp4.media_path == Path.join(expected_season, expected_stem <> ".mp4")
  end

  test "rejects missing upload dates and unsupported containers", %{root: root} do
    channel = %Channel{name: "Channel", base_path: root}
    undated_video = %Video{upload_date: nil}

    assert {:error, :missing_upload_date} =
             VideoArtifacts.build_destination(channel, undated_video, ".mkv")

    dated_video = %Video{upload_date: ~D[2025-01-01]}

    assert {:error, :unsupported_extension} =
             VideoArtifacts.build_destination(channel, dated_video, ".exe")
  end

  test "orders same-day videos by id within their channel and year" do
    channel = channel_fixture()

    first_video =
      video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-01]})

    second_video =
      video_fixture(%{channel_id: channel.id, upload_date: ~D[2025-01-01]})

    _other_channel_video =
      video_fixture(%{channel_id: channel_fixture().id, upload_date: ~D[2025-01-01]})

    _other_year_video =
      video_fixture(%{channel_id: channel.id, upload_date: ~D[2024-12-31]})

    assert {:ok, 1} = VideoArtifacts.episode_number(first_video)
    assert {:ok, 2} = VideoArtifacts.episode_number(second_video)
  end

  test "writes escaped NFO metadata with the external video id", %{root: root, policy: policy} do
    video =
      video_fixture(%{
        title: "Title <&> \"'",
        description: nil,
        external_id: "external<&>\"'",
        url: "https://example.test/watch?a=1&b=<two>",
        upload_date: ~D[2025-03-01]
      })

    path = Path.join(root, "episode.nfo")

    assert :ok = VideoArtifacts.write_nfo(path, video, 7, policy)

    contents = File.read!(path)

    assert contents =~ "<title>Title &lt;&amp;&gt; &quot;&apos;</title>"
    assert contents =~ "<season>2025</season>"
    assert contents =~ "<episode>7</episode>"
    assert contents =~ "<plot></plot>"
    assert contents =~ "<aired>2025-03-01</aired>"

    assert contents =~
             "<uniqueid type=\"youtube\" default=\"true\">external&lt;&amp;&gt;&quot;&apos;</uniqueid>"

    assert contents =~ "<url>https://example.test/watch?a=1&amp;b=&lt;two&gt;</url>"
    refute contents =~ "<uniqueid type=\"youtube\" default=\"true\">#{video.id}</uniqueid>"
  end

  test "finds only regular same-stem artifacts without following symlinks", %{root: root} do
    media_path = Path.join(root, "episode.mkv")
    nfo_path = Path.join(root, "episode.nfo")
    subtitle_path = Path.join(root, "episode.en.forced.srt")
    unrelated_path = Path.join(root, "episode-other.mkv")
    symlink_path = Path.join(root, "episode.outside.srt")
    directory_path = Path.join(root, "episode.artwork")
    outside_path = Path.join(root, "outside.srt")

    Enum.each(
      [media_path, nfo_path, subtitle_path, unrelated_path, outside_path],
      &File.write!(&1, "data")
    )

    File.mkdir_p!(directory_path)
    File.ln_s!(outside_path, symlink_path)

    assert {:ok, artifacts} = VideoArtifacts.existing_artifacts(media_path)

    assert artifacts == Enum.sort([media_path, nfo_path, subtitle_path])
    refute symlink_path in artifacts
    refute unrelated_path in artifacts
    refute directory_path in artifacts
    assert File.lstat!(symlink_path).type == :symlink
  end
end
