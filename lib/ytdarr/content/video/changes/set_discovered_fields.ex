defmodule Ytdarr.Content.Video.Changes.SetDiscoveredFields do
  @moduledoc "Sets discovered_at and position_in_uploads based on discovered_from"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    discovered_from = Ash.Changeset.get_attribute(changeset, :discovered_from)
    discovered_at = Ash.Changeset.get_attribute(changeset, :discovered_at)
    position = Ash.Changeset.get_attribute(changeset, :position_in_uploads)

    changeset =
      if is_binary(discovered_from) and byte_size(discovered_from) > 0 and is_nil(discovered_at) do
        Ash.Changeset.force_change_attribute(
          changeset,
          :discovered_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )
      else
        changeset
      end

    # If discovered_from indicates uploads playlist, set position if unset
    case {discovered_from, position} do
      {"uploads" <> _rest, nil} ->
        Ash.Changeset.force_change_attribute(changeset, :position_in_uploads, 0)

      _ ->
        changeset
    end
  end
end
