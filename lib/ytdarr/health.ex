defmodule Ytdarr.Health do
  @moduledoc false

  def ready? do
    case Ecto.Adapters.SQL.query(Ytdarr.Repo, "SELECT 1", [], timeout: 1_000, log: false) do
      {:ok, _result} -> true
      {:error, _reason} -> false
    end
  catch
    :exit, _reason -> false
  end
end
