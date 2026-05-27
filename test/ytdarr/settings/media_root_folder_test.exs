defmodule Ytdarr.Settings.MediaRootFolderTest do
  use Ytdarr.DataCase

  alias Ytdarr.Settings

  describe "media root folders" do
    test "creates and lists media root folders" do
      {:ok, folder} =
        Settings.create_media_root_folder(%{
          path: unique_folder_path(),
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
      {:ok, folder} = Settings.create_media_root_folder(%{path: unique_folder_path()})

      assert {:ok, updated_folder} =
               Settings.update_media_root_folder(folder, %{
                 path: unique_folder_path(),
                 purpose: "podcasts",
                 active: false
               })

      assert updated_folder.path != folder.path
      assert updated_folder.purpose == "podcasts"
      refute updated_folder.active
    end

    test "activate and deactivate toggle the active flag" do
      {:ok, folder} =
        Settings.create_media_root_folder(%{
          path: unique_folder_path(),
          active: false
        })

      refute folder.active

      assert {:ok, activated_folder} = Settings.activate_media_root_folder(folder)
      assert activated_folder.active

      assert {:ok, deactivated_folder} = Settings.deactivate_media_root_folder(activated_folder)
      refute deactivated_folder.active
    end

    test "list_active_media_folders!/0 returns only active folders" do
      deactivate_all_media_folders()

      {:ok, active_folder} = Settings.create_media_root_folder(%{path: unique_folder_path()})

      {:ok, _inactive_folder} =
        Settings.create_media_root_folder(%{
          path: unique_folder_path(),
          active: false
        })

      active_ids =
        Settings.list_active_media_folders!()
        |> Enum.map(& &1.id)

      assert active_ids == [active_folder.id]
    end

    test "destroy_media_root_folder/1 removes the folder" do
      {:ok, folder} = Settings.create_media_root_folder(%{path: unique_folder_path()})

      assert :ok = Settings.destroy_media_root_folder(folder)

      refute Enum.any?(Settings.list_media_root_folders!(), fn listed_folder ->
               listed_folder.id == folder.id
             end)
    end

    test "enforces unique paths" do
      path = unique_folder_path()

      assert {:ok, _folder} = Settings.create_media_root_folder(%{path: path})

      assert {:error,
              %Ash.Error.Invalid{
                errors: [
                  %Ash.Error.Changes.InvalidAttribute{
                    field: :path,
                    message: "has already been taken"
                  }
                ]
              }} = Settings.create_media_root_folder(%{path: path})
    end
  end

  defp unique_folder_path do
    "/downloads/#{System.unique_integer([:positive])}"
  end

  defp deactivate_all_media_folders do
    Enum.each(Settings.list_media_root_folders!(), &Settings.deactivate_media_root_folder/1)
  end
end
