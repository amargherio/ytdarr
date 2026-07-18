defmodule Ytdarr.ObanWorkers.MediaPermissionsWorkerTest do
  use Ytdarr.DataCase
  use Oban.Testing, repo: Ytdarr.Repo, engine: Oban.Engines.Lite

  alias Ytdarr.{MediaPermissions, Repo, Settings}
  alias Ytdarr.ObanWorkers.MediaPermissionsWorker

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ytdarr-media-permissions-worker-#{System.unique_integer([:positive])}"
      )

    nested = Path.join(root, "nested")
    inactive_root = root <> "-inactive"
    File.mkdir_p!(nested)
    File.mkdir_p!(inactive_root)
    File.write!(Path.join(nested, "video.mp4"), "media")
    File.write!(Path.join(inactive_root, "archived.mp4"), "media")
    gid = File.stat!(root).gid

    on_exit(fn ->
      File.rm_rf!(root)
      File.rm_rf!(inactive_root)
    end)

    {:ok, policy} =
      MediaPermissions.build_policy(
        %{owner_group: "test-media", file_mode: "0640", directory_mode: "0750"},
        group_resolver: fn "test-media" -> {:ok, gid} end,
        current_gids: [gid]
      )

    {:ok, root: root, nested: nested, inactive_root: inactive_root, policy: policy}
  end

  test "normalizes all configured roots and persists a summary", %{
    root: root,
    nested: nested,
    inactive_root: inactive_root,
    policy: policy
  } do
    assert {:ok, _root_folder} =
             Settings.create_media_root_folder(%{path: root, active: true, purpose: "videos"})

    assert {:ok, _inactive_folder} =
             Settings.create_media_root_folder(%{
               path: inactive_root,
               active: false,
               purpose: "videos"
             })

    assert {:ok, job} =
             policy
             |> MediaPermissions.policy_args()
             |> MediaPermissionsWorker.new()
             |> Oban.insert()

    assert :ok = MediaPermissionsWorker.perform(job)

    updated_job = Repo.get!(Oban.Job, job.id)
    assert updated_job.meta["status"] == "completed"
    assert updated_job.meta["files"] == 2
    assert updated_job.meta["directories"] == 3
    assert updated_job.meta["failed"] == 0
    assert Bitwise.band(File.stat!(Path.join(nested, "video.mp4")).mode, 0o7777) == 0o640

    assert Bitwise.band(File.stat!(Path.join(inactive_root, "archived.mp4")).mode, 0o7777) ==
             0o640

    assert Bitwise.band(File.stat!(nested).mode, 0o7777) == 0o750
  end

  test "deduplicates nested configured roots", %{root: root, nested: nested} do
    assert {:ok, _root_folder} =
             Settings.create_media_root_folder(%{path: root, active: true, purpose: "videos"})

    assert {:ok, _nested_folder} =
             Settings.create_media_root_folder(%{path: nested, active: false, purpose: "videos"})

    assert MediaPermissionsWorker.configured_roots() == [Path.expand(root)]
  end

  test "coalesces duplicate active jobs for the same policy", %{policy: policy} do
    args = MediaPermissions.policy_args(policy)

    assert {:ok, first_job} = args |> MediaPermissionsWorker.new() |> Oban.insert()
    assert {:ok, duplicate_job} = args |> MediaPermissionsWorker.new() |> Oban.insert()

    assert duplicate_job.id == first_job.id
    assert duplicate_job.conflict?
  end
end
