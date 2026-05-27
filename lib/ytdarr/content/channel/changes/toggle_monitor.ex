defmodule Ytdarr.Content.Channel.Changes.ToggleMonitor do
  @moduledoc "Toggles the is_monitored status"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    current = Ash.Changeset.get_attribute(changeset, :is_monitored)
    new_value = not current

    changeset =
      Ash.Changeset.force_change_attribute(changeset, :is_monitored, new_value)

    if new_value do
      Ash.Changeset.after_action(changeset, fn _changeset, result ->
        %{"source_type" => "channel", "source_id" => result.id}
        |> Ytdarr.ObanWorkers.SyncWorker.new()
        |> Oban.insert()

        {:ok, result}
      end)
    else
      changeset
    end
  end
end
