defmodule Ytdarr.Repo.Migrations.CreateYtDlpParamSets do
  use Ecto.Migration

  def change do
    create table(:yt_dlp_param_sets) do
      add :name, :string, null: false
      add :format, :string
      add :extra_args, :text
      add :rate_limit_kbps, :integer
      add :concurrency, :integer
      add :is_default, :boolean, null: false, default: false
      timestamps()
    end

    create unique_index(:yt_dlp_param_sets, [:name])
    create index(:yt_dlp_param_sets, [:is_default])
  end
end
