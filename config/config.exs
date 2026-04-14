import Config

config :sle,
  ecto_repos: [SLE.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :sle, SLEWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SLEWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SLE.PubSub,
  live_view: [signing_salt: "DKv/ep+n"]

# Oban job processing
config :sle, Oban,
  repo: SLE.Repo,
  queues: [
    default: 10,
    webhooks: 20,
    dunning: 5,
    metrics: 3,
    ecosystem: 10
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", SLE.Jobs.DunningEscalationJob}
     ]}
  ]

# Dunning retry intervals in hours: attempt 1 (+24h), 2 (+72h), 3 (+120h), 4 (+168h)
config :sle, :dunning_retry_intervals, "24,72,120,168"

# ETS cache TTL (milliseconds) — default 5 minutes
config :sle, :cache_ttl, 300_000

# Stripe client module (overridden in test.exs with mock)
config :sle, :stripe_client, SLE.Stripe.Client

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
