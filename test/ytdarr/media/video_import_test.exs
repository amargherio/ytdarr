defmodule Ytdarr.Media.VideoImportTest do
  use Ytdarr.DataCase, async: false

  import Ytdarr.ContentFixtures

  alias Ytdarr.Media.VideoImport
  alias Ytdarr.MediaPermissions
  alias Ytdarr.TestSupport.VideoImportFileOps

  defmodule Probe do
    def probe(_path, _timeout), do: {:ok, %{height: 1080, quality: "1080p"}}
  end

  defmodule NoVideoProbe do
    def probe(_path, _timeout), do: {:error, :no_video_stream}
  end

  defmodule DenyWriteProbeOps do
    def lstat(_context, path), do: File.lstat(path, time: :posix)
    def create_exclusive(_context, _path, _contents), do: {:error, :eacces}
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "ytdarr-video-import-#{System.unique_integer([:positive])}")

    source_root = Path.join(root, "source")
    media_root = Path.join(root, "media")
    File.mkdir_p!(source_root)
    File.mkdir_p!(media_root)

    channel = channel_fixture()
    channel = %{channel | base_path: media_root, name: "Import / Channel"}

    policy = media_policy(media_root)

    on_exit(fn -> File.rm_rf!(root) end)

    %{source_root: source_root, media_root: media_root, channel: channel, policy: policy}
  end

  test "imports selected companions with no-overwrite hard-link staging and cleanup", context do
    source = Path.join(context.source_root, "legacy.mkv")
    subtitle = Path.join(context.source_root, "legacy.en.srt")
    forced_subtitle = Path.join(context.source_root, "legacy.en.forced.vtt")
    artwork = Path.join(context.source_root, "legacy.jpg")
    old_nfo = Path.join(context.source_root, "legacy.nfo")
    mtime = 1_700_000_000

    File.write!(source, "legacy video")
    File.write!(subtitle, "subtitle")
    File.write!(forced_subtitle, "forced subtitle")
    File.write!(artwork, "artwork")
    File.write!(old_nfo, "old metadata")
    Enum.each([source, subtitle, forced_subtitle], fn path -> :ok = File.touch(path, mtime) end)

    video =
      video_fixture(%{
        channel_id: context.channel.id,
        title: "Imported : Episode",
        external_id: "imported-#{System.unique_integer([:positive])}",
        upload_date: ~D[2025-04-09]
      })

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    selected_ids = for sidecar <- preview.sidecars, sidecar.kind == :subtitle, do: sidecar.id
    assert {:ok, manifest} = VideoImport.build_manifest(preview, selected_ids)

    assert {:ok, placement} =
             VideoImport.stage(41_001, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    assert placement.file_size == byte_size("legacy video")
    assert placement.quality == "1080p"
    assert File.read!(manifest.destination.media_path) == "legacy video"

    assert File.read!(manifest.destination.nfo_path) =~
             "<uniqueid type=\"youtube\" default=\"true\">#{video.external_id}</uniqueid>"

    final_subtitle = Path.rootname(manifest.destination.media_path) <> ".en.srt"
    final_forced_subtitle = Path.rootname(manifest.destination.media_path) <> ".en.forced.vtt"
    refute File.exists?(Path.rootname(manifest.destination.media_path) <> ".jpg")
    assert File.exists?(final_subtitle)
    assert File.exists?(final_forced_subtitle)
    assert File.stat!(manifest.destination.media_path, time: :posix).mtime == mtime
    assert File.stat!(final_subtitle, time: :posix).mtime == mtime

    media_pair = Enum.find(placement.destination_pairs, &(&1.kind == :media))
    assert File.lstat!(media_pair.marker_path).inode == File.lstat!(media_pair.final_path).inode
    assert File.exists?(placement.lock_path)
    assert File.exists?(placement.quarantine_owner_path)
    refute File.exists?(source)
    refute File.exists?(subtitle)
    refute File.exists?(forced_subtitle)
    refute File.exists?(old_nfo)
    assert File.exists?(artwork)

    assert %{"mode" => "delete", "entries" => entries} =
             VideoImport.recovery_map(placement, :delete)

    assert Enum.any?(entries, &(&1["kind"] == "destination_marker"))
    assert Enum.any?(entries, &(&1["kind"] == "source_quarantine"))

    assert {:ok, []} = VideoImport.commit_cleanup(placement)
    refute File.exists?(media_pair.marker_path)
    refute File.exists?(placement.lock_path)
    refute File.exists?(placement.source_quarantine_directory)
    assert File.exists?(manifest.destination.media_path)
  end

  test "rejects stale source companion sets and forged sidecar selection", context do
    {video, source} = create_source_video(context, "stale")

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    assert {:error, :invalid_sidecar_selection} =
             VideoImport.build_manifest(preview, ["not-from-preview"])

    assert {:ok, manifest} = VideoImport.build_manifest(preview, [])

    File.write!(Path.join(context.source_root, "stale.de.srt"), "new sidecar")

    assert {:error, :source_changed, []} =
             VideoImport.stage(41_002, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )
  end

  test "keeps inspection failures typed", context do
    {video, source} = create_source_video(context, "unprobeable")

    assert {:error, :no_video_stream} =
             VideoImport.inspect_source(context.channel, video, source, probe: NoVideoProbe)
  end

  test "rejects sources whose directory cannot pass the exclusive write probe", context do
    {video, source} = create_source_video(context, "readonly")

    assert {:error, :source_not_writable} =
             VideoImport.inspect_source(context.channel, video, source,
               file_ops: {DenyWriteProbeOps, nil},
               probe: Probe
             )
  end

  test "post-operation copy link and quarantine faults restore source ownership", context do
    for operation <- [:copy, :link, :quarantine] do
      {video, source} = create_source_video(context, Atom.to_string(operation))

      assert {:ok, preview} =
               VideoImport.inspect_source(context.channel, video, source, probe: Probe)

      assert {:ok, manifest} = VideoImport.build_manifest(preview, [])
      assert {:ok, agent} = VideoImportFileOps.start_link(fail_after: %{operation => 1})

      assert {:error, :video_not_importable, []} =
               VideoImport.stage(
                 42_000 + System.unique_integer([:positive]),
                 manifest,
                 context.channel,
                 video,
                 file_ops: {VideoImportFileOps, agent},
                 probe: Probe,
                 policy: context.policy
               )

      assert File.exists?(source)
      refute File.exists?(manifest.destination.media_path)
    end
  end

  test "post-operation restore faults are recognized as restored and cleanup faults retain evidence",
       context do
    {video, source} = create_source_video(context, "recovery")

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    assert {:ok, manifest} = VideoImport.build_manifest(preview, [])

    assert {:ok, placement} =
             VideoImport.stage(43_001, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    assert {:ok, restore_agent} = VideoImportFileOps.start_link(fail_after: %{restore: 1})

    assert {:ok, []} =
             VideoImport.rollback(placement, file_ops: {VideoImportFileOps, restore_agent})

    assert File.exists?(source)
    refute File.exists?(manifest.destination.media_path)

    assert {:ok, placement} =
             VideoImport.stage(43_002, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    assert {:ok, cleanup_agent} = VideoImportFileOps.start_link(fail_before: %{remove: 1})

    assert {:error, entries} =
             VideoImport.commit_cleanup(placement, file_ops: {VideoImportFileOps, cleanup_agent})

    assert [_ | _] = entries

    assert %{"mode" => "delete", "entries" => ^entries} =
             VideoImport.recovery_map(entries, :delete)

    assert File.exists?(manifest.destination.media_path)
  end

  test "reconstructs an authoritative persisted recovery journal without a job or manifest",
       context do
    {video, source} = create_source_video(context, "persisted")

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    assert {:ok, manifest} = VideoImport.build_manifest(preview, [])

    assert {:ok, placement} =
             VideoImport.stage(44_001, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    recovery = VideoImport.recovery_map(placement, :restore)
    assert {:ok, []} = VideoImport.recover(nil, nil, :import_failed, recovery: recovery)
    assert File.exists?(source)
    refute File.exists?(manifest.destination.media_path)
  end

  test "never overwrites a source path that reappears during rollback", context do
    {video, source} = create_source_video(context, "reappeared")

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    assert {:ok, manifest} = VideoImport.build_manifest(preview, [])

    assert {:ok, placement} =
             VideoImport.stage(45_001, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    File.write!(source, "replacement source")

    assert {:error, entries} = VideoImport.rollback(placement)
    assert File.read!(source) == "replacement source"
    assert Enum.any?(entries, &(&1["kind"] == "source_quarantine"))
    refute File.exists?(manifest.destination.media_path)
  end

  test "never unlinks a final whose staging marker no longer matches", context do
    {video, source} = create_source_video(context, "marker-owner")

    assert {:ok, preview} =
             VideoImport.inspect_source(context.channel, video, source, probe: Probe)

    assert {:ok, manifest} = VideoImport.build_manifest(preview, [])

    assert {:ok, placement} =
             VideoImport.stage(46_001, manifest, context.channel, video,
               probe: Probe,
               policy: context.policy
             )

    media_pair = Enum.find(placement.destination_pairs, &(&1.kind == :media))
    File.rm!(media_pair.marker_path)
    File.write!(media_pair.marker_path, "replacement marker")

    assert {:error, entries} = VideoImport.rollback(placement)
    assert File.exists?(media_pair.final_path)

    assert Enum.any?(
             entries,
             &(&1["kind"] == "destination_marker" and &1["path"] == media_pair.marker_path)
           )

    assert File.exists?(source)
  end

  defp create_source_video(context, stem) do
    source = Path.join(context.source_root, "#{stem}.mkv")
    File.write!(source, "#{stem} video")

    video =
      video_fixture(%{
        channel_id: context.channel.id,
        title: "#{stem} #{System.unique_integer([:positive])}",
        external_id: "#{stem}-#{System.unique_integer([:positive])}",
        upload_date: ~D[2025-04-09]
      })

    {video, source}
  end

  defp media_policy(path) do
    gid = File.stat!(path).gid

    {:ok, policy} =
      MediaPermissions.build_policy(
        %{owner_group: "test-media", file_mode: "0644", directory_mode: "0755"},
        group_resolver: fn "test-media" -> {:ok, gid} end,
        current_gids: [gid]
      )

    policy
  end
end
