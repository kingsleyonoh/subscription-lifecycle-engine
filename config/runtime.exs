import Config

# Enable server when PHX_SERVER is set (used in releases)
if System.get_env("PHX_SERVER") do
  config :sle, SLEWeb.Endpoint, server: true
end

config :sle, SLEWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :sle, SLE.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "subscriptions.kingsleyonoh.com"

  config :sle, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :sle, SLEWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # Stripe configuration
  config :stripity_stripe,
    api_key: System.get_env("STRIPE_SECRET_KEY")

  # Ecosystem feature flags and URLs
  config :sle,
    notification_hub_enabled: System.get_env("NOTIFICATION_HUB_ENABLED") == "true",
    notification_hub_url: System.get_env("NOTIFICATION_HUB_URL"),
    notification_hub_api_key: System.get_env("NOTIFICATION_HUB_API_KEY"),
    workflow_engine_enabled: System.get_env("WORKFLOW_ENGINE_ENABLED") == "true",
    workflow_engine_url: System.get_env("WORKFLOW_ENGINE_URL"),
    workflow_engine_api_key: System.get_env("WORKFLOW_ENGINE_API_KEY"),
    workflow_payment_routing_id: System.get_env("WORKFLOW_PAYMENT_ROUTING_ID"),
    workflow_metrics_report_id: System.get_env("WORKFLOW_METRICS_REPORT_ID"),
    recon_engine_enabled: System.get_env("RECON_ENGINE_ENABLED") == "true",
    recon_engine_url: System.get_env("RECON_ENGINE_URL"),
    recon_engine_api_key: System.get_env("RECON_ENGINE_API_KEY"),
    client_portal_enabled: System.get_env("CLIENT_PORTAL_ENABLED") == "true",
    client_portal_url: System.get_env("CLIENT_PORTAL_URL"),
    client_portal_api_key: System.get_env("CLIENT_PORTAL_API_KEY")

  # Dunning configuration
  config :sle,
    dunning_max_attempts: String.to_integer(System.get_env("DUNNING_MAX_ATTEMPTS") || "4"),
    dunning_retry_intervals: System.get_env("DUNNING_RETRY_INTERVALS") || "24,72,120,168"

  # Tenant management
  config :sle,
    self_registration_enabled: System.get_env("SELF_REGISTRATION_ENABLED") == "true",
    default_tenant_name: System.get_env("DEFAULT_TENANT_NAME") || "Default"

  # Stripe webhook source slug
  config :sle,
    stripe_webhook_source_slug: System.get_env("STRIPE_WEBHOOK_SOURCE_SLUG") || "stripe-events"

  # Logging level
  log_level =
    case System.get_env("LOG_LEVEL") do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level

  # Sentry error tracking
  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: :prod,
      enable_source_code_context: true,
      root_source_code_paths: [File.cwd!()]
  end

  # BetterStack log shipping
  if betterstack_token = System.get_env("BETTERSTACK_SOURCE_TOKEN") do
    config :sle, :betterstack_source_token, betterstack_token
  end
end
