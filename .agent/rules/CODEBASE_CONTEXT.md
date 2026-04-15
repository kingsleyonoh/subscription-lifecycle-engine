# Subscription Lifecycle Engine — Codebase Context

> Last updated: 2026-04-14
> Template synced: 2026-04-14

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.17+ |
| Framework | Phoenix 1.7+ (API-only, no LiveView) |
| Database | PostgreSQL 16 |
| ORM | Ecto 3.x |
| Background Jobs | Oban 2.x (PostgreSQL-backed) |
| HTTP Client | Req 0.5+ |
| Stripe SDK | stripity_stripe 3.x |
| Testing | ExUnit + Mox + Bypass + ex_machina |
| Containerization | Docker + Docker Compose |
| Hosting | Docker on Hetzner VPS behind Traefik |
| Package Manager | Mix (Hex) |

## Project Structure

```
subscription-lifecycle-engine/
├── lib/
│   ├── sle/                    # Business logic (Ecto contexts)
│   │   ├── application.ex      # OTP app — starts Repo, Oban, Req pools
│   │   ├── repo.ex             # Ecto Repo
│   │   ├── tenants/            # Tenant management + API key auth
│   │   ├── customers/          # Stripe customer sync
│   │   ├── subscriptions/      # State machine + lifecycle (4 files)
│   │   ├── billing/            # Invoice + plan management
│   │   ├── dunning/            # Payment retry + escalation
│   │   ├── metrics/            # MRR, churn, ARPU calculators
│   │   ├── webhooks/           # Event router + processors/
│   │   ├── ecosystem/          # Outbound integration facade (5 clients)
│   │   └── stripe/             # Stripe API wrapper
│   ├── sle_web/                # Phoenix HTTP layer
│   │   ├── router.ex           # All routes
│   │   ├── controllers/        # 10 controllers
│   │   ├── plugs/              # auth.ex, rate_limit.ex, tenant_scope.ex
│   │   └── views/              # error_json.ex, changeset_json.ex
│   └── sle_jobs/               # 8 Oban workers
├── priv/repo/migrations/       # Ecto migrations
├── test/                       # Mirrors lib/ structure
│   ├── support/                # factory.ex, mocks.ex, fixtures/stripe/
│   └── test_helper.exs
├── config/                     # config.exs, dev.exs, test.exs, prod.exs, runtime.exs
├── Dockerfile                  # Multi-stage Elixir release
├── docker-compose.yml          # Dev PostgreSQL
├── docker-compose.prod.yml     # Production: app + Postgres
└── mix.exs                     # Dependencies + project config
```

> Full detailed tree with every file: see PRD Section 9.

## Key Modules, Schema & Integrations

> **Split for size compliance.** See companion files:
> - `CODEBASE_CONTEXT_MODULES.md` — key modules, dependency hierarchy, deep references
> - `CODEBASE_CONTEXT_SCHEMA.md` — database schema, external integrations, ecosystem connections, env vars
>
> 11 modules (Tenants, Customers, Subscriptions, Billing, Dunning, Metrics, Webhooks, Ecosystem, Stripe, Web, Jobs) | 8 tables | 8 external integrations | 30 env vars

## Commands

| Action | Command |
|--------|---------|
| Dev server | `mix phx.server` |
| Run tests | `mix test` |
| Lint/check | `mix credo` |
| Format check | `mix format --check-formatted` |
| Build | `MIX_ENV=prod mix release` |
| Migrate DB | `mix ecto.migrate` |
| Setup DB | `mix setup` |
| E2E tests | `mix test test/e2e/` |
| Dependencies | `mix deps.get` |
| Interactive | `iex -S mix` |

## Tenant Model

- **Isolation:** API key per tenant (`X-API-Key` header)
- **Table:** `tenants` with `api_key_hash` (SHA-256)
- **Middleware:** Auth plug hashes key, resolves tenant, sets `conn.assigns.current_tenant`
- **All queries scoped:** `WHERE tenant_id = ^tenant.id`

## Key Patterns & Conventions

- **File naming:** `snake_case.ex` for all Elixir files
- **Module naming:** `PascalCase` (e.g., `SLE.Subscriptions.StateMachine`)
- **Import conventions:** `use` -> `import` -> `alias` -> `require`, grouped by stdlib -> deps -> project
- **Error handling:** Centralized error JSON format via `FallbackController`
- **State machine:** Explicit transition map in `StateMachine` module, guarded transitions only
- **Event-driven:** All state changes triggered by webhook events, never by polling
- **Idempotent:** Every processor checks `stripe_event_id` before executing
- **Ecosystem:** Feature-flagged integrations, standalone-capable, fire-and-forget for notifications
- **Contexts:** Ecto contexts pattern — `SLE.Subscriptions`, `SLE.Dunning`, etc. import DOWN only

## Gotchas & Lessons Learned

> Discovered during implementation. Added automatically by `/implement-next` Step 9.3.
> These prevent the same mistakes from being repeated across sessions.

| Date | Area | Gotcha | Discovered In |
|------|------|--------|---------------|
| 2026-04-04 | PostgreSQL | Local port 5432 conflict with system PostgreSQL — Docker container fails to start or connects to wrong instance. Fix: map to alternate port via `docker-compose.override.yml` (`5440:5432`) and update `DATABASE_URL`. | Swarm Intelligence Gateway (seeded from template knowledge base) |

## Shared Foundation (MUST READ before any implementation)

> These files define the project's shared patterns, configuration, and utilities.
> The AI MUST read these **in full** before writing ANY new code. Never recreate what exists here.

| Category | File(s) | What it establishes |
|----------|---------|-------------------|
| Application | `lib/sle/application.ex` | OTP supervision tree, starts Repo, Oban, Req pools |
| Repo | `lib/sle/repo.ex` | Ecto Repo module |
| Auth plug | `lib/sle_web/plugs/auth.ex` | API key -> tenant resolution for all requests |
| Tenant scope | `lib/sle_web/plugs/tenant_scope.ex` | Sets tenant_id on conn |
| Rate limiter | `lib/sle_web/plugs/rate_limit.ex` | Per-tenant rate limiting |
| Error handling | `lib/sle_web/controllers/fallback_controller.ex` | Standard error JSON response |
| Error views | `lib/sle_web/views/error_json.ex` | Error rendering |
| State machine | `lib/sle/subscriptions/state_machine.ex` | Transition validator + guard functions |
| Ecosystem facade | `lib/sle/ecosystem/ecosystem.ex` | Feature-flagged outbound integration dispatch |
| Router | `lib/sle_web/router.ex` | All route definitions, pipeline plugs |
| Config | `config/runtime.exs` | Runtime env var -> application config mapping |
| Test factory | `test/support/factory.ex` | Test data factory (ex_machina) |
| Mocks | `test/support/mocks.ex` | Mox behaviour definitions |

## Deep References

> See `CODEBASE_CONTEXT_MODULES.md` for the full directory-to-topic mapping table.
