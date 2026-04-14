# Build Journal — Subscription Lifecycle Engine

> Engineering narratives captured during implementation. Each entry records the decision, context, and rationale for significant technical choices.

## Template

### [Date] — [Title]

**Context:** What was the situation?
**Decision:** What did we decide?
**Rationale:** Why this approach over alternatives?
**Impact:** What does this affect going forward?

---

## Example Entry

### 2026-04-14 — Chose Oban over GenServer for Job Processing

**Context:** Needed reliable background job processing for webhook events and dunning retries.
**Decision:** Oban 2.x with PostgreSQL backend instead of raw GenServer or custom queue.
**Rationale:** Oban provides persistence, retries, cron scheduling, and unique jobs out of the box. No Redis dependency. PostgreSQL is already required for the app.
**Impact:** All background jobs use Oban workers. Job monitoring via Oban telemetry events.
