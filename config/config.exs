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
       {"0 * * * *", SLE.Jobs.DunningEscalationJob},
       {"0 2 * * *", SLE.Jobs.MetricsComputeJob},
       {"0 4 * * *", SLE.Jobs.StaleCleanupJob},
       {"0 8 * * *", SLE.Jobs.TrialEndingCheckJob}
     ]}
  ]

# Dunning retry intervals in hours: attempt 1 (+24h), 2 (+72h), 3 (+120h), 4 (+168h)
config :sle, :dunning_retry_intervals, "24,72,120,168"

# ETS cache TTL (milliseconds) — default 5 minutes
config :sle, :cache_ttl, 300_000

# Stripe client module (overridden in test.exs with mock)
config :sle, :stripe_client, SLE.Stripe.Client

# Ecosystem feature flags (all disabled by default, enabled per-env)
config :sle,
  notification_hub_enabled: false,
  notification_hub_client: SLE.Ecosystem.NotificationHub,
  workflow_engine_enabled: false,
  workflow_engine_client: SLE.Ecosystem.WorkflowEngine,
  recon_engine_enabled: false,
  recon_engine_client: SLE.Ecosystem.ReconEngine,
  client_portal_enabled: false,
  client_portal_client: SLE.Ecosystem.ClientPortal

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
