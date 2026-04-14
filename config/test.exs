import Config

# Configure your database for async sandbox mode
config :sle, SLE.Repo,
  username: "sle",
  password: "sle_password",
  hostname: "localhost",
  port: 5443,
  database: "sle_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sle, SLEWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9RMQ/JAufL/jA4PeJWi/zetyCTSD5ixUwd5poirgXOk1bnT9WbGopjA71/PQRz2n",
  server: false

# Disable Oban job processing in tests
config :sle, Oban, testing: :inline

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Use mock Stripe client in tests
config :sle, :stripe_client, SLE.Stripe.ClientMock
