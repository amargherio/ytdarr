defmodule Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp do
  @moduledoc "Sets is_monitored_since when transitioning to monitored"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    is_monitored = Ash.Changeset.get_attribute(changeset, :is_monitored)
    existing_since = Ash.Changeset.get_attribute(changeset, :is_monitored_since)

    cond do
      is_monitored == true and is_nil(existing_since) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :is_monitored_since,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      is_monitored == false ->
        Ash.Changeset.force_change_attribute(changeset, :is_monitored_since, nil)

      true ->
        changeset
    end
  end
end
