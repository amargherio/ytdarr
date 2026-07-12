defmodule Ytdarr.Settings.MediaRootFolder.Validations.LastActiveCheck do
  @moduledoc """
  Prevents deactivating or destroying the last remaining active media root folder.

  Used in both the `:deactivate` and `:destroy` actions. If the folder being
  acted on is the only active folder, the action is rejected with a clear error.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    if removing_active_folder?(changeset) do
      active_count = count_active_folders()

      if active_count <= 1 do
        {:error,
         field: :active, message: "cannot remove or deactivate the last active media root folder"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp removing_active_folder?(changeset) do
    action_name = changeset.action && changeset.action.name
    target_active = Ash.Changeset.get_attribute(changeset, :active)

    changeset.data.active and
      (changeset.action_type == :destroy or action_name == :deactivate or target_active == false)
  end

  defp count_active_folders do
    Ytdarr.Settings.MediaRootFolder
    |> Ash.Query.filter(active == true)
    |> Ash.read!(domain: Ytdarr.Settings)
    |> length()
  end
end
