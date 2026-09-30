# Foundations — Backend Tasks & Database Design

**Module:** `01-foundations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below it is designed until the schema is settled. Every table states its
tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `audit_log` (model `AuditLog`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 (app-generated) | PK |
| `school_id` | `uuid` | yes | `null` | **Tenant column.** `null` = platform-level event. Loose ref to `schools` (04-organization-hierarchy) — no FK by design (append-only decoupling) |
| `actor_user_id` | `uuid` | yes | `null` | Loose ref to `users` (03-identity-access); `null` = system/worker action |
| `actor_role` | `text` | yes | `null` | Role snapshot at action time |
| `action` | `text` | no | — | Dot-namespaced verb, e.g. `vendor.approve`, `order.cancel`, `fee.refund` |
| `entity_type` | `text` | no | — | e.g. `vendor_account`, `fee_invoice` |
| `entity_id` | `text` | no | — | uuid-as-text (accepts pre-uuid owners) |
| `before` | `jsonb` | yes | `null` | Previous state snapshot (secret-free, BR-006) |
| `after` | `jsonb` | yes | `null` | New state snapshot |
| `request_id` | `text` | yes | `null` | `X-Request-Id` correlation |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | `updated_at` present for convention; rows never change (INV-001) |

**Constraints:** `CHECK (action <> '' AND entity_type <> '')`; `CHECK (entity_id <> '')`; no FK on
`school_id`/`actor_user_id` (owners are modules 03/04; they may add FKs on their own tables).
**Append-only:** rule/trigger rejects `UPDATE`/`DELETE` (BR-005).
**Indexes:** `(school_id, created_at DESC)` → school audit trail list · `(entity_type, entity_id)`
→ entity history · `(actor_user_id, created_at DESC)` → moderator/actor review.

#### `jobs` (model `Job`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 (app-generated) | PK |
| `school_id` | `uuid` | yes | `null` | **Tenant column.** `null` = platform job (e.g. reaper metrics). Loose ref to `schools` (04) |
| `type` | `text` | no | — | Registered handler key, e.g. `year_end_migration` (04), `ai_batch_tag` (08), `weekly_pain_points` (09), `payment_receipt_pdf` (12) |
| `payload` | `jsonb` | no | — | Handler-specific args; validated by the handler |
| `status` | `text` | no | `'QUEUED'` | CHECK ∈ QUEUED / RUNNING / SUCCEEDED / FAILED / DEAD (INV-002) |
| `run_at` | `timestamptz` | no | `now()` | Earliest claim time; backoff target on retry |
| `attempts` | `integer` | no | `0` | Incremented on claim |
| `max_attempts` | `integer` | no | `5` | DEAD at attempts ≥ max (INV-004) |
| `last_error` | `text` | yes | `null` | Truncated error message |
| `locked_at` | `timestamptz` | yes | `null` | Set on claim; staleness (> 5 min) triggers reaper |
| `locked_by` | `text` | yes | `null` | Worker instance id |
| `idempotency_key` | `text` | yes | `null` | `UNIQUE` when present (INV-003); producer dedupe |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** `CHECK (status IN ('QUEUED','RUNNING','SUCCEEDED','FAILED','DEAD'))`;
`CHECK (attempts >= 0 AND max_attempts > 0)`; `UNIQUE (idempotency_key)` (nulls distinct).
**Indexes:** partial `(run_at ASC) WHERE status = 'QUEUED'` → claim query (`FOR UPDATE SKIP
LOCKED`) · `(status, locked_at) WHERE status = 'RUNNING'` → reaper stale scan ·
`(school_id, status)` → tenant job list (admin surfaces later).

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20260930000001_baseline_extensions` — extensions (`pg_trgm`), schema conventions | ✅ |
| 2 | `20260930000002_audit_log` — table + append-only rule + indexes | ✅ |
| 3 | `20260930000003_jobs` — table + partial indexes + idempotency unique | ✅ |

Wired via golang-migrate with an embedded `migrations/` dir; expand/contract only; applied files
are never edited.

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| None — infrastructure module. No seed data; fictional demo content (e.g. "Demo High School", DRAFT) is owned by feature modules (04+) | — | — |

---

## 2. Server Contracts

### Endpoint `GET /healthz` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | none — public liveness (Nginx/HestiaCP + `15-deployment-operations` uptime) |
| **Input** | none; contract-generated response struct |
| **Result** | `200` `{"status":"ok"}` (plain JSON, `no-store`) |
| **Errors** | unexpected → `INTERNAL` problem+json |
| **Rate limit** | `default` class |
| **Audit** | none — read-only |
| **Stories** | FND-US-006 |

### Endpoint `GET /readyz` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | none (public; IP-restriction decision open — 01 §9 Q3) |
| **Input** | none |
| **Result** | `200` with per-dependency results when Neon ping + Redis PING pass (1s timeout each); `503` `application/problem+json` naming failed dependencies |
| **Errors** | `INTERNAL` (dependency down) with localized bn/en `message` + details array |
| **Rate limit** | `default` class |
| **Audit** | none — read-only |
| **Stories** | FND-US-006 |

### Cross-cutting headers & error envelope (every route, all modules)

| | |
| --- | --- |
| **`X-Request-Id`** | accepted (≤ 64 chars, sanitized) or generated uuid v7; echoed on every response; attached to all slog fields |
| **Error format** | RFC-7807 `application/problem+json`: `type`, `title`, `status`, `code` ∈ {UNAUTHENTICATED, FORBIDDEN, VALIDATION_FAILED, TENANT_MISMATCH, NOT_FOUND, NOT_VERIFIED, RATE_LIMITED, QUOTA_EXCEEDED, CONFLICT, INTERNAL}, localized `message` (bn default / en), `requestId`; open-set codes — clients fall back to generic bn/en copy |
| **Rate-limit classes** | auth / ai / payments / messaging / default — table fixed here, enforced per-route by consumer modules |
| **Audit** | destructive/financial routes (modules 11–13) must call `audit.Record` in-tx |

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web routes. The generated `openapi-fetch` client and zod schemas are
scaffolded in `packages/shared` (FND-BE-002) and first consumed by 03-identity-access (login) and
07-command-center-web.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `FND-BE-001` | Monorepo + Go module scaffold: pnpm workspaces (`web`/`app`/`shared`), `turbo.json` tasks, `go.mod`, Makefile, handler→service→repository layout, husky + lint-staged | ESLint boundary rule: web/app import api only via generated client | — | — |
| `FND-BE-002` | Codegen pipeline: `contracts/openapi/openapi.yaml` skeleton (Problem schema, health paths, error shape) → oapi-codegen (Go types + `ServerInterface`) → openapi-typescript + openapi-fetch into `packages/shared/src/api-client` | `make contracts` / `pnpm generate:api`; generated code committed; drift = defect (BR-001) | — | — |
| `FND-BE-003` | Config modules: Go typed struct parser (required/optional, enums) + TS zod env; single accessor; fail-fast `Validate()` at boot | No `os.Getenv`/`process.env` outside config (BR-002); names every offending var | — | — |
| `FND-BE-004` | DB base: pgx pool (Neon-compatible TLS), sqlc config + `queries/` dir, golang-migrate embedded wiring, testcontainers-go fixture (per-test Postgres + migrations up) | Pool ping with backoff for Neon cold start; context timeouts | — | — |
| `FND-BE-005` | Error envelope service: domain error type + RFC-7807 writer; code registry; bn/en message selection (`Accept-Language`, bn default); `requestId` injection | Never leaks stacks/internal errors; unknown codes render generic copy | — | — |
| `FND-BE-006` | Middleware chain: RequestID, Recover, security headers, slog request logger (method/path/status/duration/request_id), redaction list, rate-limit class registry, auth/tenant-scope scaffolding (stub claims until 03) | Order fixed per 02 §6; panics → `INTERNAL`, no stack leak; secrets redacted (BR-006) | — | — |
| `FND-BE-007` | Health service: `/healthz` + `/readyz` with Neon ping + Redis PING (1s timeouts), per-dependency detail, degraded messages bn/en | readyz red on any dependency failure; no caching | — | — |
| `FND-BE-008` | `audit.Record(ctx, Entry)` tx-aware helper + sqlc queries (insert; scoped lists); DB append-only rule/trigger | Same-tx atomicity: audit failure aborts the action; no UPDATE/DELETE path exists (BR-005) | — | writes here |
| `FND-BE-009` | `jobs.Enqueue` / `jobs.Register` + worker loop: claim (`SKIP LOCKED`, `run_at <= now()`), execute, ack/retry, graceful drain on SIGTERM | At-least-once; handlers idempotent (BR-004); unregistered type → enqueue error | — | — |
| `FND-BE-010` | CI quality gate: GitHub Actions — api (gofmt/goimports, golangci-lint, `go vet`, unit + testcontainers integration), TS (`pnpm lint/typecheck/test/build` per workspace), codegen drift job | Required checks block merge; no skip flags | — | — |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `FND-BE-011` | `AuditLog.Insert` / `ListBySchool(schoolID, limit)` / `ListByEntity(type, id)` | INSERT append-only; SELECT scoped `WHERE school_id = $1 ORDER BY created_at DESC`; SELECT by entity pair | `(school_id, created_at DESC)` · `(entity_type, entity_id)` |
| `FND-BE-012` | `Jobs.Enqueue` / `Claim` / `MarkSucceeded` / `MarkFailed` / `MarkDead` / `RequeueStale` / `CountByStatus` | INSERT (with idempotency dedupe); `UPDATE … WHERE id IN (SELECT id … FOR UPDATE SKIP LOCKED)` claim; stale `WHERE status='RUNNING' AND locked_at < now()-interval` | partial `(run_at) WHERE QUEUED` · `(status, locked_at) WHERE RUNNING` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `FND-BE-009` | Worker runtime (claim → run → ack/retry), 1s poll, graceful shutdown | process start; queue non-empty | handlers must be (BR-004) | backoff 5s × 2^n + jitter → DEAD at max_attempts |
| `FND-BE-012` | Reaper: stale RUNNING (lock > 5 min) → QUEUED | in-process ticker, 60s | yes — pure status transition | logged + metric; never fatal |
| `FND-BE-013` | Harness noop handler + queue metrics (depth, DEAD count) for `15-deployment-operations` | registered at boot | yes | — |

Consumer modules register handlers, never their own pollers: 04 (year-end migration), 08 (AI
batches), 09 (weekly analytics), 12 (PDF receipts).

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `FND-UT-001` | Domain error → problem+json mapping for every code; bn (default) / en message selection | Unit | FND-US-004 envelope contract |
| `FND-UT-002` | Config parse: missing/invalid var fails fast naming it; valid env loads typed values | Unit | BR-002 |
| `FND-UT-003` | Backoff curve + DEAD transition decision table (attempts/max_attempts) | Unit | INV-004 |
| `FND-UT-004` | slog redaction of `password`/`token`/`secret`/`authorization` fields | Unit | BR-006 |
| `FND-UT-005` | readyz checker with fake Neon/Redis probes (green, each-failure-shape) | Unit | FND-US-006 |
| `FND-IT-001` | Migrations up/down clean on fresh testcontainers Postgres; re-apply idempotent | Integration (testcontainers) | FND-US-003 |
| `FND-IT-002` | `/readyz` 200 with Postgres + Redis up; 503 naming Redis when it stops; `/healthz` unaffected | Integration (testcontainers) | FND-US-006 |
| `FND-IT-003` | Worker: enqueue→run→SUCCEEDED; failing handler retries with backoff then DEAD; duplicate `idempotency_key` returns original job; two workers never double-claim | Integration (testcontainers) | FND-US-007, BR-004, INV-002/003 |
| `FND-IT-004` | `audit.Record` in-tx commit/abort; UPDATE/DELETE rejected; school-scoped list returns only scoped rows (cross-tenant probe → `TENANT_MISMATCH`) | Integration (testcontainers) | FND-US-008, BR-005, BR-003 |
| `FND-IT-005` | Request without `X-Request-Id` gets uuid v7 echoed; malformed incoming id replaced; errors carry `requestId` | Integration | FND-US-005 |
| `FND-IT-006` | Contract validation: bad body → `VALIDATION_FAILED` with bn-default message; unknown route → `NOT_FOUND` problem shape | Integration | FND-US-002, FND-US-004 |

Always include: unauthenticated call denied for every protected entry point — none exist in this
module (health is public by design); the authenticate/tenant-scope chain's rejection semantics are
proven with stub claims in FND-IT-006 and for real by 03-identity-access. No seed → no publish
guard here; guard lands with the first content module (04).

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [ ] `FND-BE-004` — pgx pool + sqlc + golang-migrate base + testcontainers fixture
- [ ] `FND-BE-008` — `audit_log` table + append-only rule + indexes + helper
- [ ] `FND-BE-009` — `jobs` table + indexes + worker base
- [ ] `FND-BE-012` — jobs repository queries (enqueue/claim/ack/retry/reaper)

### Repository · Service · Entry points · Seed · Tests

- [ ] `FND-BE-001` — monorepo + Go module scaffold
- [ ] `FND-BE-002` — OpenAPI codegen pipeline (Go + TS) + skeleton spec
- [ ] `FND-BE-003` — config modules (Go + zod TS)
- [ ] `FND-BE-005` — RFC-7807 error envelope + code registry + bn/en copy
- [ ] `FND-BE-006` — middleware chain (request-id, recover, headers, slog redaction, rate-limit classes, auth scaffolding)
- [ ] `FND-BE-007` — `/healthz` + `/readyz`
- [ ] `FND-BE-010` — CI quality gate + drift check
- [ ] `FND-BE-011` — audit repository queries
- [ ] `FND-BE-013` — noop handler + queue metrics
- [ ] Seed — None — infrastructure module
- [ ] `FND-UT-001` … `FND-UT-005`, `FND-IT-001` … `FND-IT-006` — test plan above
