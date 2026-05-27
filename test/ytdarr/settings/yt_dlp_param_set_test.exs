defmodule Ytdarr.Settings.YtDlpParamSetTest do
  use Ytdarr.DataCase

  alias Ytdarr.Settings

  describe "yt-dlp parameter sets" do
    test "creates, lists, updates, and destroys parameter sets" do
      {:ok, param_set} =
        Settings.create_yt_dlp_param_set(%{
          name: unique_param_set_name(),
          format: "bestvideo+bestaudio",
          extra_args: "--no-playlist --quiet",
          rate_limit_kbps: 5_000,
          concurrency: 2
        })

      listed_param_set =
        Settings.list_yt_dlp_param_sets!()
        |> Enum.find(&(&1.id == param_set.id))

      assert listed_param_set
      assert listed_param_set.extra_args == "--no-playlist --quiet"

      assert {:ok, updated_param_set} =
               Settings.update_yt_dlp_param_set(param_set, %{
                 format: "best[height<=1080]",
                 extra_args: "--no-playlist --write-info-json",
                 rate_limit_kbps: 1_500,
                 concurrency: 4
               })

      assert updated_param_set.format == "best[height<=1080]"
      assert updated_param_set.extra_args == "--no-playlist --write-info-json"
      assert updated_param_set.rate_limit_kbps == 1_500
      assert updated_param_set.concurrency == 4

      assert :ok = Settings.destroy_yt_dlp_param_set(updated_param_set)

      refute Enum.any?(Settings.list_yt_dlp_param_sets!(), fn listed_param_set ->
               listed_param_set.id == updated_param_set.id
             end)
    end

    test "set_default_yt_dlp_param_set/1 marks a param set as default and clears the previous default" do
      {:ok, first_param_set} =
        Settings.create_yt_dlp_param_set(%{
          name: unique_param_set_name(),
          is_default: true
        })

      {:ok, second_param_set} = Settings.create_yt_dlp_param_set(%{name: unique_param_set_name()})

      assert {:ok, updated_param_set} = Settings.set_default_yt_dlp_param_set(second_param_set)
      assert updated_param_set.is_default

      refute Settings.get_yt_dlp_param_set!(first_param_set.id).is_default
      assert Settings.get_yt_dlp_param_set!(second_param_set.id).is_default
      assert Settings.get_default_yt_dlp_param_set!().id == second_param_set.id
    end

    test "updating a param set to the default clears other defaults" do
      {:ok, first_param_set} =
        Settings.create_yt_dlp_param_set(%{
          name: unique_param_set_name(),
          is_default: true
        })

      {:ok, second_param_set} = Settings.create_yt_dlp_param_set(%{name: unique_param_set_name()})

      assert {:ok, updated_param_set} =
               Settings.update_yt_dlp_param_set(second_param_set, %{is_default: true})

      assert updated_param_set.is_default
      refute Settings.get_yt_dlp_param_set!(first_param_set.id).is_default
      assert Settings.get_yt_dlp_param_set!(second_param_set.id).is_default
    end

    test "enforces unique names" do
      name = unique_param_set_name()

      assert {:ok, _param_set} = Settings.create_yt_dlp_param_set(%{name: name})

      assert {:error,
              %Ash.Error.Invalid{
                errors: [
                  %Ash.Error.Changes.InvalidAttribute{
                    field: :name,
                    message: "has already been taken"
                  }
                ]
              }} = Settings.create_yt_dlp_param_set(%{name: name})
    end
  end

  defp unique_param_set_name do
    "Param Set #{System.unique_integer([:positive])}"
  end
end
