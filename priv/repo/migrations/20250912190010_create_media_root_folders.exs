defmodule Ytdarr.Repo.Migrations.CreateMediaRootFolders do
  use Ecto.Migration

  def change do
    create table(:media_root_folders) do
      add :path, :string, null: false
      add :purpose, :string, null: false, default: "videos"
      add :active, :boolean, null: false, default: true
      timestamps()
    end

    create unique_index(:media_root_folders, [:path])
  end
end
