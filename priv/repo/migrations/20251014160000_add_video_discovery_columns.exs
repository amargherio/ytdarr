defmodule Ytdarr.Repo.Migrations.AddVideoDiscoveryColumns do
  use Ecto.Migration

  @moduledoc false

  def change do
    alter table(:videos) do
      add :discovered_from, :string
      add :discovered_at, :utc_datetime
      add :position_in_uploads, :integer
    end

    create index(:videos, [:discovered_from])
    create index(:videos, [:position_in_uploads])
  end
end
