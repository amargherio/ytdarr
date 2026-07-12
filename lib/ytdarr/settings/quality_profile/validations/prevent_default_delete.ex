defmodule Ytdarr.Settings.QualityProfile.Validations.PreventDefaultDelete do
  @moduledoc """
  Prevents deletion of the current default quality profile.

  The caller must first promote another profile to default (via `:set_as_default`)
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
       message: "cannot delete the default quality profile; set another profile as default first"}
    else
      :ok
    end
  end
end
