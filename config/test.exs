import Config
config :ytdarr, token_signing_secret: "LDDL3X1ZjiOU9IC9OWyYLPXD3LK60tLX"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ytdarr, Ytdarr.Repo,
  database: Path.expand("../ytdarr_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ytdarr, YtdarrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YCFi/qRCzl/9tj7af9E+O/L71GWwysTH7Q6fqpm41n+CDFz5/nAW1te6vHYri/9e",
  server: false

# In test we don't send emails
config :ytdarr, Ytdarr.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable YouTube client supervisor to avoid external HTTP client setup in tests
config :ytdarr, :enable_youtube_client, false

# Oban
config :ytdarr, Oban, testing: :manual, engine: Oban.Engines.Lite
