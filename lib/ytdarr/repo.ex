defmodule Ytdarr.Repo do
  use AshSqlite.Repo,
    otp_app: :ytdarr

  def min_sqlite_version do
    %Version{major: 3, minor: 46, patch: 1}
  end
end
