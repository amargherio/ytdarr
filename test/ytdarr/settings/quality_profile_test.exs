defmodule Ytdarr.Settings.QualityProfileTest do
  use Ytdarr.DataCase

  alias Ytdarr.Settings

  describe "quality profiles" do
    test "creates, lists, updates, and destroys quality profiles" do
      {:ok, profile} =
        Settings.create_quality_profile(%{
          name: unique_profile_name(),
          max_height: 1080,
          max_bitrate_kbps: 8_000,
          preferred_codecs: ["av1", "h264"],
          allow_hdr: true,
          format_selector: "bestvideo[height<=1080]+bestaudio/best"
        })

      listed_profile =
        Settings.list_quality_profiles!()
        |> Enum.find(&(&1.id == profile.id))

      assert listed_profile
      assert listed_profile.preferred_codecs == ["av1", "h264"]

      assert {:ok, updated_profile} =
               Settings.update_quality_profile(profile, %{
                 max_height: 720,
                 max_bitrate_kbps: 4_000,
                 preferred_codecs: ["h264"],
                 allow_hdr: false,
                 format_selector: "bestvideo[height<=720]+bestaudio/best"
               })

      assert updated_profile.max_height == 720
      assert updated_profile.max_bitrate_kbps == 4_000
      assert updated_profile.preferred_codecs == ["h264"]
      refute updated_profile.allow_hdr
      assert updated_profile.format_selector == "bestvideo[height<=720]+bestaudio/best"

      assert :ok = Settings.destroy_quality_profile(updated_profile)

      refute Enum.any?(Settings.list_quality_profiles!(), fn listed_profile ->
               listed_profile.id == updated_profile.id
             end)
    end

    test "set_default_quality_profile/1 marks a profile as default and clears the previous default" do
      {:ok, first_profile} =
        Settings.create_quality_profile(%{
          name: unique_profile_name(),
          is_default: true
        })

      {:ok, second_profile} = Settings.create_quality_profile(%{name: unique_profile_name()})

      assert {:ok, updated_profile} = Settings.set_default_quality_profile(second_profile)
      assert updated_profile.is_default

      refute Settings.get_quality_profile!(first_profile.id).is_default
      assert Settings.get_quality_profile!(second_profile.id).is_default
      assert Settings.get_default_quality_profile!().id == second_profile.id
    end

    test "updating a profile to the default clears other defaults" do
      {:ok, first_profile} =
        Settings.create_quality_profile(%{
          name: unique_profile_name(),
          is_default: true
        })

      {:ok, second_profile} = Settings.create_quality_profile(%{name: unique_profile_name()})

      assert {:ok, updated_profile} =
               Settings.update_quality_profile(second_profile, %{is_default: true})

      assert updated_profile.is_default
      refute Settings.get_quality_profile!(first_profile.id).is_default
      assert Settings.get_quality_profile!(second_profile.id).is_default
    end

    test "enforces unique names" do
      name = unique_profile_name()

      assert {:ok, _profile} = Settings.create_quality_profile(%{name: name})

      assert {:error,
              %Ash.Error.Invalid{
                errors: [
                  %Ash.Error.Changes.InvalidAttribute{
                    field: :name,
                    message: "has already been taken"
                  }
                ]
              }} = Settings.create_quality_profile(%{name: name})
    end
  end

  defp unique_profile_name do
    "Profile #{System.unique_integer([:positive])}"
  end
end
