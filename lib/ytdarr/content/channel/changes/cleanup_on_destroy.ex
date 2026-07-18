defmodule Ytdarr.Content.Channel.Changes.CleanupOnDestroy do
  @moduledoc "Optionally deletes channel files and evicts images from cache on destroy"
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    delete_files? = Ash.Changeset.get_argument(changeset, :delete_files)

    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      base_path = result.base_path

      if delete_files? && base_path && File.dir?(base_path) do
        case File.rm_rf(base_path) do
          {:ok, _} ->
            Logger.info("CleanupOnDestroy: removed #{base_path} for channel #{result.id}")

          {:error, reason, file} ->
            Logger.warning(
              "CleanupOnDestroy: failed to remove #{file} in #{base_path}: #{inspect(reason)}"
            )
        end
      end

      Ytdarr.Cache.ImageCache.delete_entry(result, "avatar")
      Ytdarr.Cache.ImageCache.delete_entry(result, "banner")

      {:ok, result}
    end)
  end
end
