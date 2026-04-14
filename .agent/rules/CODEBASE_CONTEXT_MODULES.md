# Subscription Lifecycle Engine — Codebase Context: Modules & References

> Split from `CODEBASE_CONTEXT.md` for size compliance. Also see: `CODEBASE_CONTEXT_SCHEMA.md`

## Key Modules

| Module | Purpose | Key Files |
|--------|---------|-----------|
| Tenants | Multi-tenant management, API key auth | `lib/sle/tenants/` |
| Customers | Stripe customer sync and lookup | `lib/sle/customers/` |
| Subscriptions | State machine, lifecycle management | `lib/sle/subscriptions/` |
| Billing | Invoice and plan management | `lib/sle/billing/` |
| Dunning | Payment failure recovery, retry escalation | `lib/sle/dunning/` |
| Metrics | MRR, churn, ARPU computation + snapshots | `lib/sle/metrics/` |
| Webhooks | Event routing, processors, idempotency | `lib/sle/webhooks/` |
| Ecosystem | Outbound integrations facade (Hub, Workflow, Recon, Portal) | `lib/sle/ecosystem/` |
| Stripe | Stripe API wrapper (invoice retry, sub cancel, fetch) | `lib/sle/stripe/` |
| Web | Phoenix controllers, plugs, router | `lib/sle_web/` |
| Jobs | Oban workers (event processor, dunning, metrics, sync) | `lib/sle_jobs/` |

## Dependency Hierarchy

```
sle/tenants          → nothing (leaf)
sle/stripe           → nothing (leaf — wraps external SDK)
sle/customers        → sle/tenants
sle/billing          → sle/tenants, sle/customers
sle/subscriptions    → sle/tenants, sle/customers, sle/billing
sle/dunning          → sle/tenants, sle/subscriptions, sle/billing
sle/webhooks         → sle/subscriptions, sle/billing, sle/dunning (processors call contexts)
sle/metrics          → sle/tenants, sle/subscriptions, sle/billing, sle/dunning
sle/ecosystem        → nothing (leaf — outbound HTTP only, no business logic imports)
sle_web              → sle/* (controllers call contexts)
sle_jobs             → sle/webhooks, sle/dunning, sle/metrics, sle/ecosystem, sle/stripe
```

Rule: Contexts import DOWN only. `sle/ecosystem` is a leaf — it never imports business logic modules. Jobs orchestrate by calling contexts + ecosystem.

## Deep References

> For detailed implementation patterns, read the source directly — don't embed here.

| Topic | Where to look |
|-------|--------------|
| Tenant system | `lib/sle/tenants/` |
| Customer management | `lib/sle/customers/` |
| Subscription lifecycle | `lib/sle/subscriptions/` |
| Billing & invoices | `lib/sle/billing/` |
| Dunning engine | `lib/sle/dunning/` |
| Metrics aggregation | `lib/sle/metrics/` |
| Webhook pipeline | `lib/sle/webhooks/` |
| Event processors | `lib/sle/webhooks/processors/` |
| Ecosystem integrations | `lib/sle/ecosystem/` |
| Stripe API wrapper | `lib/sle/stripe/` |
| API controllers | `lib/sle_web/controllers/` |
| Auth middleware | `lib/sle_web/plugs/` |
| Background jobs | `lib/sle_jobs/` |
| Database migrations | `priv/repo/migrations/` |
| Test patterns | `test/` |
| Stripe fixtures | `test/support/fixtures/stripe/` |
