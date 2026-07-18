defmodule Ytdarr.MediaPermissionsTest do
  use ExUnit.Case, async: true

  alias Ytdarr.MediaPermissions

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ytdarr-media-permissions-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    gid = File.stat!(root).gid

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, policy} =
      MediaPermissions.build_policy(
        %{owner_group: "test-media", file_mode: "640", directory_mode: "0750"},
        group_resolver: fn "test-media" -> {:ok, gid} end,
        current_gids: [gid]
      )

    {:ok, root: root, gid: gid, policy: policy}
  end

  test "normalizes modes and validates group membership", %{gid: gid} do
    assert {:ok, policy} =
             MediaPermissions.build_policy(
               %{owner_group: " media ", file_mode: "644", directory_mode: "0755"},
               group_resolver: fn "media" -> {:ok, gid} end,
               current_gids: [gid]
             )

    assert policy.owner_group == "media"
    assert policy.file_mode == "0644"
    assert policy.file_mode_value == 0o644
    assert policy.directory_mode == "0755"
    assert policy.directory_mode_value == 0o755

    assert {:error, {:invalid_mode, :file_mode, "888"}} =
             MediaPermissions.build_policy(
               %{owner_group: "media", file_mode: "888", directory_mode: "755"},
               group_resolver: fn "media" -> {:ok, gid} end,
               current_gids: [gid]
             )

    assert {:error, {:group_not_available, "media"}} =
             MediaPermissions.build_policy(
               %{owner_group: "media", file_mode: "644", directory_mode: "755"},
               group_resolver: fn "media" -> {:ok, gid + 1} end,
               current_gids: [gid]
             )
  end

  test "applies exact file and directory modes", %{root: root, gid: gid, policy: policy} do
    directory = Path.join(root, "Season 2026")
    file = Path.join(directory, "episode.mp4")

    assert :ok = MediaPermissions.mkdir_p(directory, policy)
    File.write!(file, "media")
    assert :ok = MediaPermissions.apply_file(file, policy)

    assert Bitwise.band(File.stat!(directory).mode, 0o7777) == 0o750
    assert Bitwise.band(File.stat!(file).mode, 0o7777) == 0o640
    assert File.stat!(directory).gid == gid
    assert File.stat!(file).gid == gid
  end

  test "normalizes a tree without following symlinks", %{root: root, policy: policy} do
    media_root = Path.join(root, "media")
    external_root = Path.join(root, "external")
    media_file = Path.join(media_root, ".hidden.mp4")
    external_file = Path.join(external_root, "outside.mp4")
    link = Path.join(media_root, "outside")

    File.mkdir_p!(media_root)
    File.mkdir_p!(external_root)
    File.write!(media_file, "media")
    File.write!(external_file, "external")
    File.chmod!(external_file, 0o600)
    File.ln_s!(external_root, link)

    assert {:ok, summary} = MediaPermissions.normalize_tree(media_root, policy)

    assert summary.files == 1
    assert summary.directories == 1
    assert summary.skipped == 1
    assert summary.failed == 0
    assert Bitwise.band(File.stat!(media_file).mode, 0o7777) == 0o640
    assert Bitwise.band(File.stat!(media_root).mode, 0o7777) == 0o750
    assert Bitwise.band(File.stat!(external_file).mode, 0o7777) == 0o600
    assert File.lstat!(link).type == :symlink
  end

  test "applies permissions to all regular download sidecars", %{root: root, policy: policy} do
    output = Path.join(root, "episode.mp4")
    nfo = Path.join(root, "episode.nfo")
    subtitle = Path.join(root, "episode.en.vtt")
    unrelated = Path.join(root, "episode-two.mp4")

    Enum.each([output, nfo, subtitle, unrelated], &File.write!(&1, "data"))
    Enum.each([output, nfo, subtitle, unrelated], &File.chmod!(&1, 0o600))

    assert {:ok, 3} = MediaPermissions.apply_download_artifacts(output, policy)

    assert Bitwise.band(File.stat!(output).mode, 0o7777) == 0o640
    assert Bitwise.band(File.stat!(nfo).mode, 0o7777) == 0o640
    assert Bitwise.band(File.stat!(subtitle).mode, 0o7777) == 0o640
    assert Bitwise.band(File.stat!(unrelated).mode, 0o7777) == 0o600
  end
end
