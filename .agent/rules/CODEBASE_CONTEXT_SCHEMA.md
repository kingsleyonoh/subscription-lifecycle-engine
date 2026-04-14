# Subscription Lifecycle Engine — Codebase Context: Schema & Integrations

> Split from `CODEBASE_CONTEXT.md` for size compliance. Also see: `CODEBASE_CONTEXT_MODULES.md`

## Database Schema

| Table | Purpose | Key Fields |
|-------|---------|-----------|
| tenants | Multi-tenant isolation | id, name, api_key_hash, api_key_prefix, stripe_config JSONB, is_active |
| customers | Stripe customer records | id, tenant_id FK, stripe_customer_id, email, name |
| plans | Subscription plan mappings | id, tenant_id FK, stripe_price_id, name, amount_cents, currency, interval |
| subscriptions | Subscription state machine | id, tenant_id FK, customer_id FK, plan_id FK, stripe_subscription_id, status (8 values), period dates, trial dates |
| subscription_events | Immutable event log + idempotency | id, tenant_id FK, stripe_event_id, event_type, payload JSONB, processed_at, idempotency_key UNIQUE |
| invoices | Stripe invoice tracking + recon sync | id, tenant_id FK, stripe_invoice_id, status (5 values), amounts, synced_to_recon |
| dunning_attempts | Payment retry tracking + escalation | id, tenant_id FK, subscription_id FK, invoice_id FK, status (5 values), attempt_number, notification_payload JSONB |
| metrics_snapshots | Daily MRR/churn/ARPU snapshots | id, tenant_id FK, period dates, mrr_cents, churn_rate, synced_to_portal |

## External Integrations

| Service | Purpose | Auth Method |
|---------|---------|------------|
| Stripe | Payment provider — webhooks + API calls | Bearer token (STRIPE_SECRET_KEY) |
| Notification Hub | Dunning alerts, subscription notifications | X-API-Key header |
| Workflow Automation Engine | Payment routing, weekly metrics report DAGs | X-API-Key header |
| Transaction Recon Engine | Batch invoice sync for settlement matching | X-API-Key header |
| Client Management Portal | MRR/churn metrics push | X-API-Key header |
| Webhook Ingestion Engine | Receives Stripe webhooks, delivers to SLE | Delivers with X-API-Key |
| BetterStack | Uptime monitoring + log shipping | Source token |
| Sentry | Error tracking | DSN |

## Ecosystem Connections

| Direction | System | Method | Env Vars |
|-----------|--------|--------|----------|
| Webhook Engine -> SLE | Webhook Ingestion Engine | REST POST /api/webhook-handler | N/A (Engine delivers) |
| SLE -> | Notification Hub | REST POST /api/events | NOTIFICATION_HUB_URL, NOTIFICATION_HUB_API_KEY |
| SLE -> | Workflow Engine | REST POST /api/workflows/:id/execute | WORKFLOW_ENGINE_URL, WORKFLOW_ENGINE_API_KEY |
| SLE -> | Recon Engine | REST POST /api/v1/transactions/ingest/batch | RECON_ENGINE_URL, RECON_ENGINE_API_KEY |
| SLE -> | Client Portal | REST POST /api/integration/metrics | CLIENT_PORTAL_URL, CLIENT_PORTAL_API_KEY |

## Environment Variables

| Variable | Purpose | Source |
|----------|---------|--------|
| HOST | Bind address for Phoenix server | `.env` |
| PORT | HTTP port (default 4000) | `.env` |
| SECRET_KEY_BASE | Phoenix secret (64+ hex chars) | `mix phx.gen.secret` |
| PHX_SERVER | Enable Phoenix server in release | `.env` |
| MIX_ENV | Elixir environment (dev/test/prod) | `.env` |
| DATABASE_URL | PostgreSQL connection string | `.env` |
| POOL_SIZE | Ecto connection pool size | `.env` |
| STRIPE_SECRET_KEY | Stripe API key (sk_test_ or sk_live_) | Stripe Dashboard |
| STRIPE_WEBHOOK_SOURCE_SLUG | Webhook Engine source slug for Stripe | Webhook Engine config |
| SELF_REGISTRATION_ENABLED | Allow open tenant registration | `.env` |
| DEFAULT_TENANT_NAME | Name for first-run seed tenant | `.env` |
| DUNNING_MAX_ATTEMPTS | Max retry attempts before exhaustion | `.env` |
| DUNNING_RETRY_INTERVALS | Hours between retries (comma-separated) | `.env` |
| NOTIFICATION_HUB_ENABLED | Feature flag for Notification Hub | `.env` |
| NOTIFICATION_HUB_URL | Notification Hub base URL | `.env` |
| NOTIFICATION_HUB_API_KEY | Notification Hub tenant API key | Hub onboarding |
| WORKFLOW_ENGINE_ENABLED | Feature flag for Workflow Engine | `.env` |
| WORKFLOW_ENGINE_URL | Workflow Engine base URL | `.env` |
| WORKFLOW_ENGINE_API_KEY | Workflow Engine tenant API key | Workflow Engine onboarding |
| WORKFLOW_PAYMENT_ROUTING_ID | UUID of payment routing workflow | Workflow Engine |
| WORKFLOW_METRICS_REPORT_ID | UUID of weekly report workflow | Workflow Engine |
| RECON_ENGINE_ENABLED | Feature flag for Recon Engine | `.env` |
| RECON_ENGINE_URL | Recon Engine base URL | `.env` |
| RECON_ENGINE_API_KEY | Recon Engine tenant API key | Recon Engine onboarding |
| CLIENT_PORTAL_ENABLED | Feature flag for Client Portal | `.env` |
| CLIENT_PORTAL_URL | Client Portal base URL | `.env` |
| CLIENT_PORTAL_API_KEY | Client Portal tenant API key | Portal onboarding |
| LOG_LEVEL | Logging level (debug/info/warning/error) | `.env` |
| SENTRY_DSN | Sentry error tracking DSN | Sentry Dashboard |
| BETTERSTACK_SOURCE_TOKEN | BetterStack log shipping token | BetterStack Dashboard |
