defmodule Ytdarr.Repo.Migrations.AddChannelsColumns do
	use Ecto.Migration

	@moduledoc false

	# This migration backfills any new columns added to the Channel schema
	# after the initial CreateContentTables migration. Currently only :banner_url
	# is missing from the original channels table definition.
	def change do
		alter table(:channels) do
			add :banner_url, :string
		end
	end
end
