defmodule Ytdarr.Settings.YtDlpParamSet.ClearOtherDefaults do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      if result.is_default do
        require Ash.Query

        Ytdarr.Settings.YtDlpParamSet
        |> Ash.Query.filter(id != ^result.id and is_default == true)
        |> Ash.bulk_update!(:update, %{is_default: false},
          domain: Ytdarr.Settings,
          strategy: :stream
        )
      end

      {:ok, result}
    end)
  end
end
