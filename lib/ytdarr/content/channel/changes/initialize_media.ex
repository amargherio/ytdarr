defmodule Ytdarr.Content.Channel.Changes.InitializeMedia do
  @moduledoc "Populates channel artwork and metadata after a successful creation."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, channel} = result ->
        Ytdarr.Content.refresh_channel_images(channel)
        result

      _changeset, result ->
        result
    end)
  end
end
