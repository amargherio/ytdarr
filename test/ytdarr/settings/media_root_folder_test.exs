defmodule Ytdarr.Settings.MediaRootFolderTest do
  use Ytdarr.DataCase

  alias Ytdarr.Settings

  # ---------------------------------------------------------------------------
  # Test directory helpers (path validation requires real, writable directories)
  # ---------------------------------------------------------------------------

  defp create_test_dir do
    base = Path.join(File.cwd!(), ".test_media_roots")
    dir = Path.join(base, "dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  # ---------------------------------------------------------------------------

  describe "media root folders" do
    test "creates and lists media root folders" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, folder} =
        Settings.create_media_root_folder(%{
          path: dir,
          purpose: "music"
        })

      assert folder.active

      listed_folder =
        Settings.list_media_root_folders!()
        |> Enum.find(&(&1.id == folder.id))

      assert listed_folder
      assert listed_folder.path == folder.path
      assert listed_folder.purpose == "music"
    end

    test "updates an existing folder" do
      dir1 = create_test_dir()
      dir2 = create_test_dir()
      fallback_dir = create_test_dir()

      on_exit(fn ->
        File.rm_rf!(dir1)
        File.rm_rf!(dir2)
        File.rm_rf!(fallback_dir)
      end)

      {:ok, _fallback} = Settings.create_media_root_folder(%{path: fallback_dir})
      {:ok, folder} = Settings.create_media_root_folder(%{path: dir1})

      assert {:ok, updated_folder} =
               Settings.update_media_root_folder(folder, %{
                 path: dir2,
                 purpose: "podcasts",
                 active: false
               })

      assert updated_folder.path == dir2
      assert updated_folder.purpose == "podcasts"
      refute updated_folder.active
    end

    test "activate and deactivate toggle the active flag" do
      dir = create_test_dir()
      dir2 = create_test_dir()

      on_exit(fn ->
        File.rm_rf!(dir)
        File.rm_rf!(dir2)
      end)

      # Create a second active folder so deactivation is allowed
      {:ok, _other} = Settings.create_media_root_folder(%{path: dir2})

      {:ok, folder} =
        Settings.create_media_root_folder(%{
          path: dir,
          active: false
        })

      refute folder.active

      assert {:ok, activated_folder} = Settings.activate_media_root_folder(folder)
      assert activated_folder.active

      # Deactivation is allowed because _other is still active
      assert {:ok, deactivated_folder} = Settings.deactivate_media_root_folder(activated_folder)
      refute deactivated_folder.active
    end

    test "list_active_media_folders!/0 returns only active folders" do
      deactivate_all_media_folders()

      dir_active = create_test_dir()
      dir_inactive = create_test_dir()

      on_exit(fn ->
        File.rm_rf!(dir_active)
        File.rm_rf!(dir_inactive)
      end)

      {:ok, active_folder} = Settings.create_media_root_folder(%{path: dir_active})

      {:ok, _inactive_folder} =
        Settings.create_media_root_folder(%{
          path: dir_inactive,
          active: false
        })

      active_ids =
        Settings.list_active_media_folders!()
        |> Enum.map(& &1.id)

      assert active_ids == [active_folder.id]
    end

    test "destroy_media_root_folder/1 removes the folder" do
      dir1 = create_test_dir()
      dir2 = create_test_dir()

      on_exit(fn ->
        File.rm_rf!(dir1)
        File.rm_rf!(dir2)
      end)

      # Keep a second active folder so delete is allowed
      {:ok, _other} = Settings.create_media_root_folder(%{path: dir2})
      {:ok, folder} = Settings.create_media_root_folder(%{path: dir1})

      assert :ok = Settings.destroy_media_root_folder(folder)

      refute Enum.any?(Settings.list_media_root_folders!(), fn listed_folder ->
               listed_folder.id == folder.id
             end)
    end

    test "enforces unique paths" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, _folder} = Settings.create_media_root_folder(%{path: dir})

      assert {:error,
              %Ash.Error.Invalid{
                errors: [
                  %Ash.Error.Changes.InvalidAttribute{
                    field: :path,
                    message: "has already been taken"
                  }
                ]
              }} = Settings.create_media_root_folder(%{path: dir})
    end
  end

  # ---------------------------------------------------------------------------
  # Path validation in saves
  # ---------------------------------------------------------------------------

  describe "path validation on create" do
    test "rejects non-existent path" do
      fake_path = "/nonexistent/ytdarr_test_#{System.unique_integer()}"

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_media_root_folder(%{path: fake_path})

      assert Enum.any?(errors, &(&1.field == :path))
    end

    test "rejects blank path" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_media_root_folder(%{path: ""})

      assert Enum.any?(errors, &(&1.field == :path))
    end

    test "rejects invalid purpose" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.create_media_root_folder(%{path: dir, purpose: "invalid_purpose"})

      assert Enum.any?(errors, &(&1.field == :purpose))
    end
  end

  # ---------------------------------------------------------------------------
  # Last active folder protection
  # ---------------------------------------------------------------------------

  describe "last active folder protection" do
    test "cannot deactivate the last active folder" do
      deactivate_all_media_folders()

      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, folder} = Settings.create_media_root_folder(%{path: dir})

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.deactivate_media_root_folder(folder)

      assert Enum.any?(errors, &(&1.field == :active))
    end

    test "cannot destroy the last active folder" do
      deactivate_all_media_folders()

      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, folder} = Settings.create_media_root_folder(%{path: dir})

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.destroy_media_root_folder(folder)

      assert Enum.any?(errors, &(&1.field == :active))
    end

    test "cannot deactivate the last active folder through the general update action" do
      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, folder} = Settings.create_media_root_folder(%{path: dir})

      Settings.list_active_media_folders!()
      |> Enum.reject(&(&1.id == folder.id))
      |> Enum.each(&Settings.deactivate_media_root_folder!/1)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Settings.update_media_root_folder(folder, %{active: false})

      assert Enum.any?(errors, &(&1.field == :active))
    end

    test "can destroy an inactive folder even if it is the only one" do
      deactivate_all_media_folders()

      dir = create_test_dir()
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, folder} = Settings.create_media_root_folder(%{path: dir, active: false})

      assert :ok = Settings.destroy_media_root_folder(folder)
    end

    test "can deactivate when another active folder exists" do
      deactivate_all_media_folders()

      dir1 = create_test_dir()
      dir2 = create_test_dir()

      on_exit(fn ->
        File.rm_rf!(dir1)
        File.rm_rf!(dir2)
      end)

      {:ok, _folder1} = Settings.create_media_root_folder(%{path: dir1})
      {:ok, folder2} = Settings.create_media_root_folder(%{path: dir2})

      assert {:ok, deactivated} = Settings.deactivate_media_root_folder(folder2)
      refute deactivated.active
    end
  end

  defp deactivate_all_media_folders do
    Enum.each(Settings.list_media_root_folders!(), &Settings.deactivate_media_root_folder/1)
  end
end
