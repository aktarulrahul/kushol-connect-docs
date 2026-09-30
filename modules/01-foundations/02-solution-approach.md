# Foundations — Solution Approach

**Module:** `01-foundations` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Written before any task list and any code. Toolchain resolved 2026-09-29 (README "Blocked before
build" row 01): Go module for `api`, pnpm+Turborepo for TS workspaces, OpenAPI 3.1 in
`contracts/openapi/`, Neon Postgres, Cloudflare R2, Hostinger KVM 2 + HestiaCP.

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `Job` | A unit of background work queued in the `jobs` table and executed by the Go worker | Yes |
| `AuditLog` | Append-only record of a destructive/financial action (actor, entity, before/after) | Yes |
| OpenAPI contract | `contracts/openapi/openapi.yaml` + generated Go server types and TS clients | Yes (tooling; no table) |
| Config module | Typed env parsing per app (Go config struct / zod env) | Yes (no table) |
| Middleware chain | Request-id, recover, logging, security headers, rate-limit classes, auth/tenant scaffolding | Yes (no table) |

### 1.2 Relationships

```text
jobs                                   audit_log (append-only)
 ├─ idempotency_key UNIQUE (nullable)   ├─ school_id     (null = platform; loose ref → schools, 04)
 ├─ school_id (null = platform job;     ├─ actor_user_id (null = system; loose ref → users, 03)
 │    loose ref → schools, 04)          └─ entity_type + entity_id (string refs, no FK)
 └─ status state machine (see §3)

References are intentionally FK-free: append-only audit and platform jobs must not break when
owner modules (03/04) migrate. Those modules may add FKs on their own tables — not here.
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `FND-INV-001` | `audit_log` rows are never updated or deleted | DB rule/trigger + tests |
| `FND-INV-002` | `jobs.status` ∈ {QUEUED, RUNNING, SUCCEEDED, FAILED, DEAD}; transitions only via the worker/claim query | CHECK + `FOR UPDATE SKIP LOCKED` claim |
| `FND-INV-003` | `jobs.idempotency_key`, when present, is globally unique; duplicates return the original job | UNIQUE index + `Enqueue` |
| `FND-INV-004` | A job is DEAD only when `attempts ≥ max_attempts`; retries re-queue with `run_at` in the future | Worker decision function (unit-tested) |
| `FND-INV-005` | Every generated Go/TS artifact matches the current spec (zero drift) | CI regenerate + `git diff --exit-code` |
| `FND-INV-006` | No repository query touches tenant rows without a `school_id` scope unless declared platform-level | Repo review + integration tests (BR-003) |

## 2. Module Boundary

**Owns (writes):** `contracts/openapi/openapi.yaml` skeleton + codegen pipeline · middleware chain,
error envelope, headers, health · `audit_log` and `jobs` tables and their Go services/worker ·
config modules (Go + TS) · CI workflows and the testcontainers harness · empty workspace shells for
`web`/`app`/`shared` (content arrives with 02/03).

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| None — root module | Nothing; modules 02–15 read from this one | n/a |

**Cache keys / tags revalidated / consumed:** none yet — see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
jobs:  QUEUED ──claim──▶ RUNNING ──ok──▶ SUCCEEDED
                          ├─error (attempts<max)──▶ QUEUED (run_at = now + backoff)
                          ├─error (attempts≥max)──▶ DEAD (last_error set)
                          └─stale lock > 5 min (reaper)──▶ QUEUED
audit_log: created once, immutable — no state machine.
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| QUEUED | worker claims (`SKIP LOCKED`, `run_at <= now()`) | RUNNING | row lock; sets `locked_at`/`locked_by` | none |
| RUNNING | handler returns nil | SUCCEEDED | — | — |
| RUNNING | handler errors, attempts<max | QUEUED | attempts<max_attempts | `run_at` = backoff; `last_error` |
| RUNNING | handler errors, attempts≥max | DEAD | attempts≥max_attempts | `last_error`; metric exposed |
| RUNNING | stale `locked_at` > lock timeout (5 min) | QUEUED | reaper only | log + metric |
| (any) | `audit.Record` | immutable row | insert within caller tx | failure aborts the tx |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| None — infrastructure module; no rendered surfaces. The generated TS client and Turborepo task graph are build-time artifacts for 02+ | — | — | — |

## 5. Configuration — the two lists

| Owner can change (env now; admin UI later, module 07/15) | Fixed in code |
| --- | --- |
| `DATABASE_URL`, `REDIS_URL`, `HTTP_PORT`, `APP_ENV`, `LOG_LEVEL`, graceful-shutdown timeout | Backoff curve (5s × 2^n + jitter, max 5 attempts), lock timeout 5 min, rate-limit class table (auth / ai / payments / messaging / default), RFC-7807 code registry, uuid v7 generation, health-check timeouts (1s each), migrations directory layout, redaction field list |

Rule: nothing else reads env — both lists are surfaced only through the config module (BR-002).

## 6. Security

- Middleware order fixed here: `X-Request-Id` → recover → security headers → request log →
  rate-limit class → `authenticate → load role claims → tenant-scope` (identity supplied by
  03-identity-access; rejection semantics and order proven here with stub claims).
- Endpoints: `/healthz`, `/readyz` only — public, read-only, no data, no tenant context.
  Rate-limit class `default` applied; auth/ai/payments/messaging classes registered, enforced by
  their consumer modules.
- Tenant-scope rules: `audit_log.school_id` nullable — scoped reads when school context present,
  platform rows (null) visible only to Super Admin surfaces (07+); `jobs.school_id` nullable —
  tenant jobs scoped, platform jobs trusted to the worker service boundary.
- Validation: every handler input validated against generated OpenAPI validators; zod mirrors in
  `packages/shared`.
- Privacy: `before`/`after` snapshots must not include secrets or full webhook payloads (BR-006);
  redaction list applied at log time. Errors are RFC-7807 with bn/en copy — never stack traces.

## 7. Accessibility & Motion

N/A — module ships no UI surfaces. The convention is fixed for all later modules: every animated
element carries a reduced-motion variant row (04 §5 / 05 §5 of those modules), bn-first at 360px.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Neon cold start (free tier scales to zero) | Pool ping fails; `/readyz` red | Requests 503 fast; no data loss | Auto-warms on first connection; readyz green; pool retry with backoff |
| 2 | Redis down | `/readyz` red; limiter errors | Degraded: rate limits fall back to per-process token bucket; later chat presence (05) degrades, never fatal | Auto-reconnect; alarm via 15 uptime checks |
| 3 | Codegen drift (spec edited, code not regenerated) | CI regenerate → diff | Merge blocked | `make contracts` + commit |
| 4 | Migration fails midway | `migrate up` non-zero exit | Deployment aborts before traffic | Expand/contract discipline; fix-forward migration; never edit applied files |
| 5 | Worker crash with locked jobs | Reaper finds stale `locked_at` | Jobs delayed ≤ 5 min | Reaper requeues; at-least-once continues |
| 6 | GitHub Actions outage | Gate never reports | Merges blocked (by design) | Run gates locally (`make gate`); rerun when CI returns |

## 9. Performance

- Volumes (Phase 1): hundreds of jobs/day; audit rows only on destructive/financial actions
  (low hundreds/day); health polled every 30–60s by Nginx/uptime.
- Hot queries: `jobs` claim — partial index `(run_at) WHERE status='QUEUED'` + `SKIP LOCKED`
  (cheap at any realistic queue depth); reaper — `(status, locked_at) WHERE status='RUNNING'`;
  audit list — `(school_id, created_at DESC)` and `(entity_type, entity_id)`.
- Bundle impact: generated TS client is type-only until used (tree-shakeable, zero runtime
  without a call site); Turborepo cache keeps CI minutes flat as workspaces grow. Go binary
  footprint unchanged by tooling deps.
- CI budget target: full gate ≤ 10 min on GitHub runners (TODO: Confirm after first runs — owner
  Rahul).

## 10. Alternatives Considered

### Option A — Go (chi + sqlc + pgx) · Option B — NestJS/TypeScript + ORM

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Single deployable for REST + high-concurrency WebSocket messaging; type-safe plain SQL; reviewable migrations; small memory on the shared KVM 2 | Same language as web/app; fast CRUD scaffolding via ORM |
| Disadvantages | Two languages in the repo; more explicit wiring | ORM layer rejected (`tech-stack.md` "Deliberately not used": GORM/Ent — reflection, hidden queries); Node WS hot path weaker for the messaging gateway (`prd.md` §6 pins Go) |
| Complexity / weight | Low-medium: boring, layered, explicit | Higher runtime weight; ORM magic to audit for tenant scoping |

**Recommendation:** A — recorded decision 2026-09-29 (`prd.md` §6, `tech-stack.md` api table); ADR in the module's `07-progress.md` at build time.

### Option C — OpenAPI-first codegen · Option D — hand-written types per app

| | C (chosen) | D |
| --- | --- | --- |
| Advantages | One spec → Go server types + TS clients; drift checkable in CI; contract reviewable | No codegen step; quick hacks |
| Disadvantages | Codegen toolchain to pin; 3.1 feature subset discipline | Types diverge silently; `tech-stack.md` §Shared & tooling: web/app never hand-write API types |
| Complexity / weight | One `make contracts` target | Hidden cost: every mismatch is a runtime bug |

**Recommendation:** C — spec is the single source; regenerate on every change (BR-001).

### Option E — in-DB `jobs` table + Go worker · Option F — Kafka/RabbitMQ or Redis Streams

| | E (chosen) | F |
| --- | --- | --- |
| Advantages | Transactional enqueue with business data; `SKIP LOCKED` is enough at MVP scale; one less system on the 2-vCPU VPS | Massive throughput, rich semantics |
| Disadvantages | Polling latency (~1s), limited throughput | Explicitly rejected until measured need (`tech-stack.md` "Deliberately not used": Kafka/RabbitMQ; Redis Streams as primary store) |
| Complexity / weight | Trivial: one table + worker loop | A broker to operate on a shared 2 vCPU host |

**Recommendation:** E — revisit only with a measured need and an ADR.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | oapi-codegen covers the OpenAPI 3.1 subset we use | Generated code lags spec features | Restrict the spec to the supported subset (JSON-Schema 2020-12 constructs avoided); pin versions; `TODO: Confirm` exact pins at build — owner Rahul |
| 2 | testcontainers (Docker) is available in CI | Integration tests can't run in CI | GitHub ubuntu runners ship Docker; fallback: Postgres service container |
| 3 | Neon free tier pauses/cold-starts | First request after idle 503s | Acceptable for dev/pilot; readyz communicates; upgrade path recorded (tech-stack.md) |
| 4 | Committed generated code stays fresh | Drift merges | CI regenerates and diffs — blocks merge (INV-005) |
| 5 | The shared KVM 2 tolerates api+web+Redis later | Memory pressure | Exercised at module 15; container memory caps planned there; this module keeps the api image minimal |
