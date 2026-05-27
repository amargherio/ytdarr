defmodule Ytdarr.Content.Channel.Changes.SetFilesystemPaths do
  @moduledoc "Sets base_path and generic_video_path when name changes"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        configured_base_path = Ytdarr.Settings.get_app_media_root_folder!()
        sanitized_name = sanitize_filename(name)
        base_path = Path.join([configured_base_path, sanitized_name])
        generic_video_path = Path.join([base_path, "videos"])

        changeset
        |> Ash.Changeset.force_change_attribute(:base_path, base_path)
        |> Ash.Changeset.force_change_attribute(:generic_video_path, generic_video_path)
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end
