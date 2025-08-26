defmodule Ytdarr.Repo do
  use Ecto.Repo,
    otp_app: :ytdarr,
    adapter: Ecto.Adapters.SQLite3
end
