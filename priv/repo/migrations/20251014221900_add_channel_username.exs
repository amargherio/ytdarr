defmodule Ytdarr.Repo.Migrations.AddChannelUsernameColumns do
	use Ecto.Migration

	@moduledoc false

	# This migration backfills any new columns added to the Channel schema
	# after the initial CreateContentTables migration. Currently only :banner_url
	# is missing from the original channels table definition.
	def change do
		alter table(:channels) do
			add :platform_username, :string
		end
	end
end
