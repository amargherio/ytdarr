defmodule Ytdarr.Settings.MediaRootFolder.Validations.PathCheck do
  @moduledoc """
  Validates that a media root folder path exists, is a directory, and is writable
  when the path attribute is being set or changed.

  Delegates to `Ytdarr.Settings.validate_path/1` for the underlying checks.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    path = Ash.Changeset.get_attribute(changeset, :path)

    cond do
      is_nil(path) or path == "" ->
        # Handled by the non-blank validation
        :ok

      not Ash.Changeset.changing_attribute?(changeset, :path) ->
        # Path unchanged on an update — skip re-validation
        :ok

      true ->
        case Ytdarr.Settings.validate_path(path) do
          {:ok, _} ->
            :ok

          {:error, _reason, message} ->
            {:error, field: :path, message: message}
        end
    end
  end
end
