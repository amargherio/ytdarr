defmodule Ytdarr.Content.Playlist.Changes.SetDownloadPath do
  @moduledoc "Sets download_path based on channel base_path and playlist name"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    name = Ash.Changeset.get_attribute(changeset, :name)

    # Try to get channel from the data or load it
    channel =
      case Ash.Changeset.get_data(changeset, :channel) do
        %Ytdarr.Content.Channel{} = ch -> ch
        _ -> nil
      end

    case {channel, name} do
      {%{base_path: base_path}, name} when not is_nil(name) and not is_nil(base_path) ->
        sanitized_name = sanitize_filename(name)
        download_path = Path.join([base_path, sanitized_name])
        Ash.Changeset.force_change_attribute(changeset, :download_path, download_path)

      _ ->
        changeset
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end
