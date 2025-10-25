defmodule Ytdarr.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 12)
  end

  # Specify version 1 to ensure we roll all the way back down if required,
  # regardless of target migrate version.
  def down do
    Oban.Migrations.down(version: 1)
  end
end
