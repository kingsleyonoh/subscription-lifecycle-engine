import Config

config :sle, SLEWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      paths: ["/api/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Structured JSON logging in production for log shipping (BetterStack)
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id, :module, :function]}

# Sentry integration — capture logged errors as Sentry events
config :logger, :sentry_handler,
  config: %{
    metadata: [:request_id, :module, :function],
    capture_log_messages: true,
    level: :error
  }

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
