defmodule Ytdarr.Settings.YtDlpParamSet.Validations.PreventDefaultDelete do
  @moduledoc """
  Prevents deletion of the current default yt-dlp parameter set.

  The caller must first promote another parameter set to default (via `:set_as_default`)
  before the previous default can be deleted.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    if changeset.data.is_default do
      {:error,
       field: :is_default,
       message:
         "cannot delete the default yt-dlp parameter set; set another parameter set as default first"}
    else
      :ok
    end
  end
end
