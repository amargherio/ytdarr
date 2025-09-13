defmodule Ytdarr.Repo.Migrations.CreateAppSettings do
  use Ecto.Migration

  def change do
    create table(:app_settings) do
      add :key, :string, null: false
      add :value, :map, null: false
      add :type, :string, null: false
      timestamps()
    end

    create unique_index(:app_settings, [:key])
  end
end
