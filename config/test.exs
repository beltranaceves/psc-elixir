import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :psc, Psc.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "psc_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :psc, PscWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Xts/fDImyMJWylRWPBN9c9VQODy9Te8H2q9likJ1nE5YAk0ZA8bDHzVnfIYTdJYg",
  server: false

# In test we don't send emails
config :psc, Psc.Mailer, adapter: Swoosh.Adapters.Test

# No background event sweeping during tests — tests exercise sweep/0 directly
config :psc, Psc.EventsSweeper, enabled: false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Tests drive the agent with explicit scripts (Psc.Agent.Turn's `script:`
# option), so no request leaves the process. The alias deliberately names a
# provider that does not exist: a turn that is *not* scripted fails immediately
# with :unknown_provider instead of quietly calling a real API.
# No deployment-wide key in tests: the tab is gated purely on the user's own key,
# which is what the LiveView tests exercise.
config :psc, :agent_enabled, false

config :jido_ai,
  model_aliases: %{
    default: "test:scripted",
    fast: "test:scripted"
  }
