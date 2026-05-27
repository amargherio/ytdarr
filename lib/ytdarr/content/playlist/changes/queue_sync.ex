defmodule Ytdarr.Content.Playlist.Changes.QueueSync do
  @moduledoc "Queues a sync job after the playlist is monitored"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      %{"source_type" => "playlist", "source_id" => result.id}
      |> Ytdarr.ObanWorkers.SyncWorker.new()
      |> Oban.insert()

      {:ok, result}
    end)
  end
end
