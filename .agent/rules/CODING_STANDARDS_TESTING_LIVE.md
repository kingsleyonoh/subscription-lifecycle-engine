# Subscription Lifecycle Engine — Coding Standards: Live & E2E Testing

> Part 3 of 4. Also loaded: `CODING_STANDARDS.md`, `CODING_STANDARDS_TESTING.md` (core TDD), `CODING_STANDARDS_DOMAIN.md`
> This file covers mock policy, integration testing, component testing, and E2E testing.

## Live Integration Testing (Mock Policy)

### The Rule: Don't Mock What You Own
If you control the service and can run it locally → test against the real thing.

### Service Fallback Hierarchy
When deciding how to test a service, follow this order:
1. **Local instance** (best) — Docker, CLI, emulator on your machine
2. **Cloud dev instance** (good) — dedicated test project / staging environment
3. **Mock** (last resort) — only when options 1 and 2 are impossible

### Test LIVE (Never Mock)
- Your database (local PostgreSQL) — validates schema, column names, constraints, query behavior
- Your own API endpoints — call the actual route, not a stub
- Your own server actions / business logic — test the real function
- File storage you control (local filesystem, local object storage)

### Mock ONLY These
- Third-party payment APIs (Stripe charges money)
- Email/SMS delivery (SendGrid/Twilio sends messages)
- Rate-limited external APIs you don't control
- Services with irreversible side effects
- Cloud-only services with no local emulator AND no dev tier

### No Services? No Problem
If the project has no external services (CLI tool, library, static site), this policy doesn't apply — just write standard unit tests.

### Why This Matters
A mock that returns `{ user_id: 1 }` will pass even when the real column is `userId`. A mock that returns success will pass even when the real constraint rejects your data. Mocks test your ASSUMPTIONS about the service. Live tests test REALITY.

### Common Mock Violations (DO NOT DO THESE)
- ❌ Mocking your database client to return fake rows — hit the real database
- ❌ Mocking your own API routes with `Mox` stubs — call the real endpoint via `ConnTest`
- ❌ Using an in-memory SQLite when production uses PostgreSQL — use the real PostgreSQL
- ❌ Mocking Redis/cache when it's running in Docker — connect to the real instance
- ✅ Mocking Stripe's charge API — you don't want to charge real money in tests
- ✅ Mocking SendGrid — you don't want to send real emails in tests
- ✅ Mocking an external API with rate limits — you don't control their uptime

### Test Cleanup
- Each test MUST clean up after itself (delete rows, reset state)
- Use transactions with rollback when possible for speed

## Backend API & Integration Testing

> This section applies to backend-only projects (APIs, workers, CLI tools). If the project has a React frontend, use the Component Testing section above instead.

### When to Write API Integration Tests
- Every **API endpoint**: test request → response cycle with real HTTP semantics
- Every **message consumer/handler**: test event processing with real or local message broker
- Every **background job/worker**: test job execution with actual service dependencies
- Every **middleware**: test request interception, auth guards, validation layers

### What to Test
| Priority | Test This | Example |
|----------|-----------|---------|
| 1 | Request/response cycle | POST /api/users → 201, returns created user |
| 2 | Input validation | Missing required field → 400 with specific error |
| 3 | Auth & authorization | No token → 401; wrong role → 403 |
| 4 | Error handling | Invalid ID → 404; DB constraint → 409 |
| 5 | Edge cases | Empty body, oversized payload, duplicate submission |

### API Testing Patterns
- Use Phoenix `ConnTest` (`use SubscriptionLifecycleEngineWeb.ConnCase`) for endpoint testing
- Test full request lifecycle — plugs, controller, JSON response
- Assert on status codes, response body structure, AND headers where relevant
- Test pagination, filtering, and sorting with real DB rows via Ecto sandbox

### Message/Event Consumer Testing
- Publish test events to a local broker (Kafka/Redpanda, RabbitMQ, Redis Streams)
- Assert the consumer processes them correctly (DB writes, side effects)
- Test error handling: malformed events, duplicate events, consumer restart

### File Naming & Location
- Name: `module_name_test.exs` — in `test/` directory mirroring `lib/` structure
- Group shared test helpers in `test/support/` (e.g., `test/support/factory.ex`, `test/support/conn_case.ex`)

## E2E Testing (Real Endpoints)

> E2E tests hit a RUNNING server over HTTP — not in-process `ConnTest` calls.
> The point is testing the deployed stack: server startup, middleware chain, database, cache, and response serialization.
> These catch issues that unit/integration tests miss: port binding, CORS headers, middleware ordering, connection pool behavior under load.

### When E2E is Required
- **Any batch that creates or modifies an API endpoint** → E2E MUST hit the running server
- **Any batch that creates or modifies a page/component with user interaction** → E2E MUST include a browser test
- **Pure utility/library/config batches with no endpoints** → E2E not required (skip with note)
- **`[SETUP]` items** → E2E not required unless the setup itself starts a server

### E2E Test Architecture

**Backend E2E (API projects):**
1. Start the actual server: `mix phx.server` (NOT in-process ConnTest)
2. Wait for ready signal (health check endpoint passes)
3. Hit real endpoints via HTTP (`HTTPoison`, `Req`, or `curl`)
4. Assert on status codes, response bodies, headers
5. Stop the server after tests complete

**Requires local PostgreSQL running** — this aligns with the existing mock policy ("Don't Mock What You Own").

### E2E Test File Structure
```
test/e2e/
  api/                                ← Backend E2E tests
    auth_e2e_test.exs                 ← Auth endpoint tests
    subscriptions_e2e_test.exs        ← Subscription endpoint tests
  support/
    server_helper.ex                  ← Start/stop server utilities
    seed_helper.ex                    ← Test data seeding
```

### E2E vs Integration Tests
| Aspect | Integration (ConnTest) | E2E (running server) |
|--------|-------------------------------|---------------------|
| Server | In-process, no real HTTP | Real HTTP, real port |
| Speed | Fast (~1ms per test) | Slower (~100ms+ per test) |
| What it catches | Handler logic, validation, DB | Middleware ordering, CORS, startup, ports |
| When to use | Every endpoint (RED/GREEN phase) | After REGRESSION passes (Step 7d) |
| Run command | `mix test` | `mix test test/e2e/` |

**Both are required.** Integration tests are your fast feedback loop (TDD). E2E tests are your deployment confidence check.

### E2E Test Cleanup
- Each E2E test must clean up its own data (delete created records, reset state)
- Use a dedicated test database or schema to avoid polluting dev data
- Kill the server process reliably in the `on_exit` callback — leaked processes block ports

### Bootstrap Setup for E2E
During `/bootstrap` Phase 0, a `[SETUP]` item should configure the E2E framework:
- Create `test/e2e/` directory structure
- Add E2E HTTP client dependency to `mix.exs` (e.g., `req` or `httpoison`)
- Add `test/e2e/` to test paths in `mix.exs` or configure a separate Mix alias
- Create E2E test helper module in `test/support/`
- Verify `mix test test/e2e/` runs and exits cleanly (even with 0 tests)
