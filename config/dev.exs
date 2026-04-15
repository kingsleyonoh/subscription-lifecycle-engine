import Config

# Configure your database
config :sle, SLE.Repo,
  username: "sle",
  password: "sle_password",
  hostname: "localhost",
  port: 5443,
  database: "sle_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :sle, SLEWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "ZizNzlSsaTT19IhbyQBhE/NZzptgYSrpD7xx7+Gdq9Hbh7un8kqmGBzK+Hr+hEi0",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :sle, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
