defmodule Ytdarr.Repo.Migrations.CreateQualityProfiles do
  use Ecto.Migration

  def change do
    create table(:quality_profiles) do
      add :name, :string, null: false
      add :max_height, :integer
      add :max_bitrate_kbps, :integer
      add :preferred_codecs, {:array, :string}, default: []
      add :allow_hdr, :boolean, null: false, default: true
      add :format_selector, :string
      add :is_default, :boolean, null: false, default: false
      timestamps()
    end

    create unique_index(:quality_profiles, [:name])
    create index(:quality_profiles, [:is_default])
  end
end
