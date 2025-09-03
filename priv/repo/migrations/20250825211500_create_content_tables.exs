defmodule Ytdarr.Repo.Migrations.CreateContentTables do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :external_id, :string, null: false
      add :url, :string, null: false
      add :description, :text
      add :platform, :string, null: false
      add :avatar_url, :string
      add :is_monitored, :boolean, default: false, null: false
      add :is_monitored_since, :utc_datetime
      add :last_checked_at, :utc_datetime
      add :base_path, :string
      add :generic_video_path, :string

      timestamps()
    end

    create table(:playlists) do
      add :name, :string, null: false
      add :external_id, :string, null: false
      add :url, :string, null: false
      add :description, :text
      add :video_count, :integer
      add :is_monitored, :boolean, default: false, null: false
      add :is_monitored_since, :utc_datetime
      add :last_checked_at, :utc_datetime
      add :download_path, :string
      add :channel_id, references(:channels, on_delete: :delete_all), null: false

      timestamps()
    end

    create table(:videos) do
      add :title, :string, null: false
      add :external_id, :string, null: false
      add :url, :string, null: false
      add :description, :text
      add :duration, :integer
      add :upload_date, :date
      add :thumbnail_url, :string
      add :is_downloaded, :boolean, default: false, null: false
      add :downloaded_at, :utc_datetime
      add :download_path, :string
      add :file_size, :integer
      add :download_quality, :string
      add :channel_id, references(:channels, on_delete: :delete_all), null: false

      timestamps()
    end

    create table(:playlist_videos) do
      add :playlist_id, references(:playlists, on_delete: :delete_all), null: false
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :position, :integer # order of the video in the playlist

      timestamps()
    end

    create unique_index(:channels, [:external_id])
    create unique_index(:playlists, [:external_id])
    create unique_index(:videos, [:external_id])
    create unique_index(:playlist_videos, [:playlist_id, :video_id])
    create index(:playlists, [:channel_id])
    create index(:videos, [:channel_id])
    create index(:videos, [:is_downloaded])
    create index(:channels, [:is_monitored])
  end
end
