# Foundations — Technical Document

**Module:** `01-foundations` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Compresses spec files `01`–`06` in this folder; when it drifts, the specs win.

---

## 1. Overview

### 1.1 Purpose

Platform skeleton every later module builds on, inside the `applications/api` repository only
(each application is its own repo; no shared package — owner decision 2026-09-30): the Go `api`
module, the OpenAPI contract it owns with Go codegen (generated contract types are the only API
types anywhere; web/app generate their own clients from it),
and cross-cutting runtime concerns — fail-fast config, sqlc + golang-migrate base, RFC-7807
errors, `X-Request-Id`, redacted slog, health, append-only `audit_log`, the in-DB `jobs` worker,
the CI gate and the testcontainers harness. Pure infrastructure for `brd.md` §8 Phase 1 (detail in
`01-user-stories.md` §1).

### 1.2 Scope

**In:** api repo scaffold (Go `api` with chi + websocket shell, `tools.mod`, Makefile) ·
OpenAPI 3.1 contract + Go codegen + CI drift check · Go config module · Postgres base
(pgx, sqlc, golang-migrate, testcontainers-go) · RFC-7807 envelope + code registry · `X-Request-Id`,
security headers, redacted slog · `/healthz` + `/readyz` · `audit_log` + `audit.Record` · `jobs`
table + worker base · CI gate.

**Out:** product features/screens beyond health (03+) · auth/OTP (03) · hierarchy tables (04) ·
web/app repo scaffolds, their TS clients, tokens and client catalogs (02) · Docker/Nginx/
backups/runbooks (15) · Kafka/RabbitMQ/Redis-Streams queues (rejected, `tech-stack.md`).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | — (root module) | Nothing. External decisions recorded 2026-09-29: Neon Postgres (ap-southeast-1), Cloudflare R2, Hostinger KVM 2 + HestiaCP |
| consumed by | 02–15 (all later modules) | `applications/api/openapi/openapi.yaml` — Go code generated here (CI drift-gated); web/app sync a copy and generate their own client |
| consumed by | 04 (migration), 08 (AI), 09 (analytics), 12 (receipts) · 11–13 first (destructive/financial routes) | `jobs.Enqueue` / `jobs.Register` worker interface · `audit.Record` helper |
| consumed by | 15-deployment-operations | `GET /healthz`, `GET /readyz` (uptime checks, deploy gating) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go 1.26.1 · chi v5.3.2 · gorilla/websocket shell (added with 05) · `log/slog` | single deployable for REST + future WS messaging; boring, explicit (`prd.md` §6) | golangci-lint v2 + gofmt/goimports in CI, tools pinned in `tools.mod` |
| api — data | PostgreSQL (Neon) · pgx v5.11.0 · sqlc v1.31.1 · golang-migrate v4.20.1 | type-safe plain SQL, reviewable migrations, real-Postgres tests | testcontainers-go v0.44.0 for integration tests |
| contracts | OpenAPI 3.1 (`applications/api/openapi/openapi.yaml`, owned by api) → oapi-codegen v2.8.0 (Go types, chi server, embedded spec) · kin-openapi request validation | spec is the single source; drift checkable in CI | generated Go committed; `make contracts` / `make contracts-check`; web/app generate their own TS clients (02) |
| i18n (api) | `internal/i18n` bn/en catalog (embedded JSON) | server-rendered copy: problem messages now; push/email text later (06/12) | client catalogs live in each client repo (02) |
| tooling | Makefile · `tools.mod` (`go tool`) · GitHub Actions (api repo) | one quality gate for the api repo | no Node tooling in this module |
| web / app | None — this module does not touch the web or app repos | — | 02 scaffolds both |

---

## 3. Architecture

### 3.1 Component diagram

```text
web repo · app repo (02+)          api repo GitHub Actions (gate + drift: make contracts-check)
  sync copy of the spec,                      │
  generate own src/api client                 ▼
        ▲                 applications/api/openapi/openapi.yaml ─► oapi-codegen ─► api (Go) chi chain:
        └──────────────── (owned by api)          RealIP → RequestID → Recover → Security headers →
                                                  slog (redacted) → rate-limit class → validator →
                                                  auth/tenant scaffolding (stubs until 03)
                              ┌────────────┼────────────┐
                              ▼            ▼            ▼
                       health service  audit service  jobs worker
                       /healthz/readyz audit.Record(tx) Enqueue/claim/retry/reaper
                              │            ▼            ▼
                Redis(PING)·Neon(ping)  audit_log (append-only)   jobs (SKIP LOCKED)
```

### 3.2 Boundary

**Owns (tables / services):** `openapi.yaml` skeleton + codegen pipeline · middleware chain, error
envelope, headers, health · `audit_log` and `jobs` tables + services/worker · config module · api
CI workflow + testcontainers harness · api bn/en problem copy. Nothing outside `applications/api`.

**Reads (via exported service functions only):** none — root module; 02–15 read from this one.
FK-free by design: `school_id`/`actor_user_id` are loose refs into 04/03 owner tables
(`02-solution-approach.md` §1.2).

### 3.3 Request / data flows

```text
1. Contract change   spec edit → make contracts → Go types regenerated → same commit → CI drift job;
                     then each client repo: pnpm sync:api-spec → pnpm generate:api → its own drift check
2. Health probe      uptime → GET /readyz → Neon ping + Redis PING (1s each) → 200 per-dependency | 503 problem+json
3. Job lifecycle     jobs.Enqueue (idempotency dedupe) → claim (SKIP LOCKED, run_at <= now()) → handler →
                     ack | retry (run_at = now + 5s×2^n + jitter) → DEAD at max_attempts → metrics
4. Stale lock        reaper ticker (60s) → RUNNING with locked_at > 5 min → QUEUED (log + metric)
5. Destructive act   feature handler (11–13) → audit.Record in caller tx → atomic commit (audit failure aborts)
6. Request tracing   X-Request-Id reused (≤64 chars, sanitized) or uuid v7 generated → echoed + attached to slog
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `jobs` | QUEUED · RUNNING · SUCCEEDED · FAILED · DEAD | QUEUED → RUNNING (worker claim, `SKIP LOCKED`, sets `locked_at`/`locked_by`) · RUNNING → SUCCEEDED (handler nil) · RUNNING → QUEUED (error, attempts<max; `run_at`=backoff) · RUNNING → DEAD (error, attempts≥max; `last_error` set) · RUNNING → QUEUED (stale `locked_at` > 5 min, reaper only) |
| `audit_log` | created once, immutable | none — INSERT only; UPDATE/DELETE rejected by DB rule (INV-001/BR-005) |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 — column detail stays there. uuid v7 is app-generated (Neon PG
16+ has no `uuidv7()`).

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `audit_log` | Append-only record of destructive/financial actions (actor, entity, before/after) | `school_id` nullable — `null` = platform-level event; scoped reads when school context present, platform rows only for Super Admin surfaces (07+) | `(school_id, created_at DESC)` · `(entity_type, entity_id)` · `(actor_user_id, created_at DESC)` | no FK on `school_id`/`actor_user_id` (loose refs to 04/03); CHECK on action/entity_type/entity_id non-empty; append-only rule/trigger |
| `jobs` | In-DB queue + Go worker (at-least-once) for background work (04/08/09/12 consumers) | `school_id` nullable — `null` = platform job; tenant jobs scoped, platform jobs trusted to the worker boundary | partial `(run_at ASC) WHERE status='QUEUED'` · `(status, locked_at) WHERE status='RUNNING'` · `(school_id, status)` | `status` CHECK QUEUED/RUNNING/SUCCEEDED/FAILED/DEAD; `UNIQUE(idempotency_key)` nulls distinct; `max_attempts` default 5 |

Migrations: `20260930000001_baseline_extensions` (pg_trgm) · `…000002_audit_log` ·
`…000003_jobs` — all reversible, golang-migrate embedded, expand/contract only. Seed: none —
infrastructure module (`03-backend-tasks.md` §1.3).

---

## 5. Contracts

### 5.1 REST endpoints

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | GET `/healthz` | none — public liveness | process-alive proof for Nginx/HestiaCP + 15 uptime checks; `{"status":"ok"}`, `no-store` | `INTERNAL` (unexpected only) | FND-US-006 |
| 2 | GET `/readyz` | none (public; IP-restriction open — 01 §9 Q3) | Neon ping + Redis PING (1s timeouts); 200 with per-dependency results, or 503 naming failed deps (bn/en) | `INTERNAL` (dependency down) | FND-US-006 |

Outside production only (`APP_ENV` ≠ `production`), `serve` also mounts GET `/docs` (Swagger UI),
GET `/openapi.json` (the embedded spec) and GET `/` → 302 `docs`. They are developer tooling, not
contract routes: not in the spec, not validated, 404 in production (`internal/apidocs`).

Cross-cutting every route, all modules: `X-Request-Id` (≤64 chars sanitized, else generated uuid
v7, echoed); RFC-7807 envelope with open-set `code`; rate-limit classes `auth/ai/payments/
messaging/default` fixed here, enforced by consumers; destructive/financial routes must call
`audit.Record` in-tx. No web Server Actions here.

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| Worker runtime (`FND-BE-009`) | process start; queue non-empty (1s poll) | claim → run → ack/retry; graceful drain on SIGTERM | 04 (year-end migration), 08 (AI), 09 (analytics), 12 (receipts) register handlers | backoff 5s × 2ⁿ + jitter → DEAD at `max_attempts`; handlers idempotent (BR-004) |
| Reaper (`FND-BE-012`) | ticker, 60s | stale RUNNING (`locked_at` > 5 min) → QUEUED | queue metrics | logged + metric; never fatal |
| Noop handler + metrics (`FND-BE-013`) | registered at boot | queue depth + DEAD count | 15-deployment-operations | — |

No realtime (WS) channels here — the gorilla/websocket shell lands here, messaging is 05's.

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `openapi.yaml` + `make contracts` | 02–15, CI | regenerated Go types/`ServerInterface` (clients generate their own TS client from a synced copy) | build error on invalid spec; CI fails on drift | spec is the single source (BR-001) |
| `GET /healthz` · `GET /readyz` | 15, HestiaCP/Nginx uptime · deploy gate | 200 `{"status":"ok"}` / per-dependency results | 503 problem+json naming the failed dependency |
| `jobs.Enqueue(ctx, JobType, payload, opts...)` / `jobs.Register(JobType, Handler)` | 04, 08, 09, 12 | job id (existing id on idempotency-key hit) | error if type unregistered / payload invalid; DTO payloads via typed wrappers |
| `audit.Record(ctx, Entry)` | all modules with destructive/financial actions | nil | error aborts the surrounding transaction |

Exports return DTOs (never sqlc rows); domain errors, never raw HTTP; additive-first signatures
(`06-integration-tasks.md` §2).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| N/A — no product routes; the web repo scaffold + generated client is `FND-FE-001` (placeholder `/`, brand name only). Routes `/`, `/download`, `/login`, `/admin/*`, `/school/*`, `/partner/*` belong to 03/07+ | — | — | — |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| N/A — no product routes; the app repo scaffold + generated client is `FND-AP-001` (placeholder `/`); onboarding screens with 03 | — | — | — |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Neon Postgres | primary datastore (ap-southeast-1) | PostgreSQL wire, TLS | `DATABASE_URL` (config module only) | connect 5s; pool ping backoff (cold start) | 503 problem responses; readyz red; self-heals on warm |
| Redis | rate limits, presence (later 05), caches | RESP (go-redis) | `REDIS_URL` | 2s ops; 3 retries exp backoff | in-process limiter fallback; readyz red; presence/chat (05) degrade, never fatal |
| GitHub Actions / GHCR | CI quality gate + drift check; images built in CI (never on the 2-vCPU VPS) | HTTPS, OIDC/GITHUB_TOKEN | repo secrets | n/a (async); manual re-run | merge gate blocks (by design); gates runnable locally via `make gate` |

FCM, R2, DeepSeek, payment gateways and the SMS gateway are **not** wired here — owning modules
declare them (`06-integration-tasks.md` §5).

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `DATABASE_URL` | yes | local: `postgres://postgres:postgres@localhost:5432/kc?sslmode=disable` · production: Neon `kushol-connect-db` (direct endpoint for migrations) | pgx pool; ping at boot, fail fast |
| `REDIS_URL` | yes | `redis://127.0.0.1:6379/0` | go-redis (limits, caches) |
| `APP_ENV` | yes | `development` \| `test` \| `production` | config module |
| `LOG_LEVEL` | yes | `info` (debug/info/warn/error) | slog setup |
| `HTTP_PORT` | yes | `5433` locally; `8080` in containers (1–65535) — host port is 15's `API_PORT` | chi server; `healthcheck` subcommand |
| `SHUTDOWN_TIMEOUT` | no | `20s` | graceful HTTP drain + worker in-flight jobs |
| `TRUSTED_PROXIES` | no | `127.0.0.1/32,::1/128` — production adds the Compose network CIDR (Docker publishes ports via the bridge gateway) | RealIP: whose `X-Forwarded-For` is believed |
| `WORKER_CONCURRENCY` | no | `2` (1–32) | jobs worker goroutines |

Feature secrets (`JWT_SECRET`, `SMS_GATEWAY_*`, gateway keys, …) are parsed by this module's
config system from module 03 onward — none defined here. The api repo's `.env.example` covers
the Neon/Redis wiring consumed later by 15's Compose (`FND-INT-005`); web/app keep their own,
each parsed only by its zod `src/env.ts`:

| Variable | Repo | Required | Example | Notes |
| --- | --- | --- | --- | --- |
| `NEXT_PUBLIC_API_URL` | web | yes | `http://localhost:5433` | public (inlined at build) — never a secret |
| `NEXT_PUBLIC_SITE_URL` | web | yes | `http://localhost:4433` | `metadataBase`; public |
| `EXPO_PUBLIC_API_URL` | app | yes | `http://<lan-ip>:5433` | inlined in the bundle; per-channel values in EAS profiles (15 `OPS-AP-004`) |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| `DATABASE_URL`, `REDIS_URL`, `HTTP_PORT`, `APP_ENV`, `LOG_LEVEL`, `SHUTDOWN_TIMEOUT`, `TRUSTED_PROXIES`, `WORKER_CONCURRENCY` (env now; admin UI later via 07/15) | backoff curve (5s × 2ⁿ + jitter, max 5 attempts) · lock timeout 5 min · rate-limit class table · RFC-7807 code registry · uuid v7 generation · health-check timeouts (1s each) · migrations directory layout · redaction field list |

Nothing outside the config module reads env (BR-002, lint-enforced).

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | middleware order fixed here: `X-Request-Id` → recover → security headers → request log → rate-limit class → `authenticate → load role claims → tenant-scope`; identity semantics supplied by 03, rejection order proven here with stub claims (FND-IT-006) |
| Role matrix | none of its own — `/healthz` `/readyz` are public, read-only, no data, no tenant context; `auth/ai/payments/messaging` classes registered for consumer modules |
| Tenant scope | `audit_log.school_id` nullable: scoped reads when school context present, platform rows (null) only for Super Admin surfaces (07+); `jobs.school_id` nullable: tenant jobs scoped, platform jobs trusted to the worker boundary; every tenant-row query carries `school_id` or is declared platform-level with a proving test (BR-003) |
| Rate limits | `default` class applied to health routes; class table (auth / ai / payments / messaging / default) defined here |
| Audit events | this module ships the table + `audit.Record` + append-only enforcement; emitting sites arrive with feature modules (11 order cancel, 12 refunds); entries are secret-free (BR-006) |
| Privacy / minors | `before`/`after` snapshots must not include secrets or full webhook payloads; slog redacts `password`/`token`/`secret`/`authorization`; errors never carry stack traces; logs are stdout JSON — shipping is module 15's concern |

---

## 10. Error Handling

All errors surface as RFC-7807 `application/problem+json` (`type`, `title`, `status`, `code`,
localized `message` bn-default, `requestId`). Message keys `errors.<code>` ship in bn + en in
the api's own catalog (`internal/i18n`, namespace `errors` per 02 §1.1); codes are an open set — clients fall back to generic bn/en copy on
unknown codes (`06-integration-tasks.md` §7).

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `VALIDATION_FAILED` | input rejected | contract validator rejects a bad body (FND-IT-006) | field errors from `errors.fields`; bn-default message |
| `NOT_FOUND` | no such route/resource | unknown route → problem shape | generic bn/en copy |
| `TENANT_MISMATCH` | cross-tenant attempt (as 404) | proven on `audit_log` scoped reads (FND-IT-004); pattern carried forward | no data leaked; silent 404 treatment |
| `RATE_LIMITED` | class cap exceeded | rate-limit class registry (enforced per-route by consumers) | countdown/retry; bn/en copy |
| `INTERNAL` | unexpected failure | dependency down on `/readyz` (503); panics → recover middleware; Neon hard outage on DB paths | retry + request id; never a stack trace |
| `UNAUTHENTICATED` / `FORBIDDEN` / `NOT_VERIFIED` / `QUOTA_EXCEEDED` / `CONFLICT` | defined in the shared registry here | returned by consumer modules (03+), not by FND's own routes | registry copy bn/en |

**Module-specific codes (registered here, owned by the listed module — 2026-09-30).** The registry
lives in one Go package (`internal/problem`) with its copy in `internal/i18n`; a module adding a code adds it here in its Stage 3 docs
sync with bn/en copy. Clients treat unknown codes with generic bn/en copy (open set).

| Code | Owner | HTTP | Meaning |
| --- | --- | --- | --- |
| `OUT_OF_STOCK` | 11 | 409 | Variant stock insufficient at reserve/checkout |
| `PAYMENT_FAILED` | 12 | 402 | Gateway reported failure/cancel for this attempt |
| `INVALID_SIGNATURE` | 12, 14 | 403 | Webhook signature missing/invalid (security-logged) |
| `STALE_TIMESTAMP` | 14 | 400 | Webhook timestamp outside the ±5-min replay window |
| `DUPLICATE_WEBHOOK` | 12 | 200 | Already-processed gateway event (idempotent no-op) |
| `UNKNOWN_EVENT` | 12 | 400 | Webhook event type not handled by the adapter |
| `CAMPAIGN_REJECTED` | 13 | 409 | Action on a campaign rejected in moderation |

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog JSON to stdout only; fields `request_id` + method/path/status/duration; redaction list applied (`password`/`token`/`secret`/`authorization` → `[REDACTED]`, BR-006); no log shipping until 15 |
| Metrics / counters | queue depth + DEAD count (`FND-BE-013`) for 15 dashboards; no reporting surfaces of its own (01 §8) |
| Health contribution | `/healthz` liveness (no dependency checks) · `/readyz` = Neon ping + Redis PING, 1s timeouts, red→green automatically after Neon cold start; both `no-store` |
| Jobs & retries | at-least-once; 1s poll; backoff 5s × 2ⁿ + jitter to max 5 attempts → DEAD + `last_error`; reaper requeues stale locks ≤ 5 min delay; worker crash delays background effects only, QUEUED rows survive |
| Runbook pointers | deploy/rollback/backup owned by 15-deployment-operations (Compose, backups, restore drill); failure matrix in `06-integration-tasks.md` §8; CI gate runs locally via `make gate` when GitHub Actions is down; migrations expand/contract, applied files immutable |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | problem+json mapping per code + bn/en selection · config fail-fast · backoff/DEAD decision table · slog redaction · readyz probe fakes · Enqueue idempotency + typed payload | `FND-UT-001…006` | `go test` green in CI |
| Integration | migrations up/down · readyz green/red shapes · worker retry/DEAD/dedupe/no-double-claim · audit in-tx + append-only + scoped reads · `X-Request-Id` echo · contract validation · generated-contract Go round-trip + spec validity · CI drift check | `FND-IT-001…008` (testcontainers Postgres) | required check |
| E2E | None — no user-facing surfaces; Playwright golden paths start with 07, Maestro with 03 | — | — |
| CI | per-app quality gate | — | api: gofmt/goimports, golangci-lint, `go vet`, unit + testcontainers integration · codegen drift job (`make contracts-check`) · (web/app gates live in their own repos) · required checks, no skip flags |

Mandatory set: unauthenticated calls denied for every protected entry point — none exist here
(health is public by design; the auth/tenant chain is proven with stub claims, for real by 03);
no seed → the publish guard lands with the first content module (04).

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | hundreds of jobs/day; audit rows only on destructive/financial actions (low hundreds/day); health polled every 30–60s |
| Hot paths + indexes | jobs claim: partial `(run_at) WHERE QUEUED` + `SKIP LOCKED`; reaper: `(status, locked_at) WHERE RUNNING`; audit list: `(school_id, created_at DESC)` and `(entity_type, entity_id)` |
| Latency targets | polling latency ~1s acceptable for the job queue; health checks 1s timeouts per dependency; Neon cold start → fast 503s, never hangs |
| Bundle / payload impact | none for clients; codegen/lint tools live in `tools.mod`, so the Go binary footprint is unchanged by tooling deps |
| Caching | none — no cached reads; `/healthz` `/readyz` are `no-store` (`06-integration-tasks.md` §4) |

---

## 14. Risks & Open Questions

Consolidated from `01-user-stories.md` §9 and `02-solution-approach.md` §11; unconfirmed items
keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Repositories + toolchain | — | Rahul | Resolved 2026-09-29; layout revised 2026-09-30 | One git repo per app, no shared package; Go module for api (chi + gorilla/websocket + sqlc + pgx + golang-migrate); OpenAPI 3.1 owned by api; web/app generate their own clients (02); Neon Postgres (region per plan F1); R2 media; Hostinger KVM 2 + HestiaCP |
| 2 | Where do generated TS clients live? | consumer import paths | Rahul | Resolved 2026-09-30 | Each client repo generates its own: `applications/web/src/api/`, `applications/app/src/api/` |
| 3 | `/readyz` public or loopback-only in production? | exposure of dependency detail | Rahul | Open | Public; Nginx/IP restriction applied later by 15 if needed |
| 4 | oapi-codegen covers the OpenAPI 3.1 subset used · testcontainers (Docker) available in CI | generated code lags spec; integration tests can't run | Rahul | Resolved / Assumption | oapi-codegen v2.8.0 supports 3.1 (verified 2026-09-30, pinned in `tools.mod`); ubuntu runners ship Docker, fallback Postgres service container |
| 5 | Neon free tier pauses/cold-starts · shared KVM 2 tolerates api+web+Redis later | first request after idle 503s; memory pressure | Rahul | Accepted / Deferred | fine for dev/pilot, readyz communicates; exercised at module 15 with memory caps |
| 6 | Committed generated code stays fresh | drift merges | Rahul | Mitigated | CI regenerates + diffs, blocks merge (INV-005) |
| 7 | CI budget: full gate ≤ 10 min (`TODO: Confirm` after first runs) | CI minutes / merge latency | Rahul | Open | revisit after first runs |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| `FND-BR-001` spec-only API types | tech-stack §Shared & tooling; prompt §1 | FND-US-002 | FND-BE-002, FND-INT-001 | FND-IT-007/008 |
| `FND-BR-002` config-only env reads | prd §6 | FND-US-001 | FND-BE-003 | FND-UT-002 |
| `FND-BR-003` tenant-scoped queries · `FND-BR-005` append-only audit | prd §6; brd §6 | FND-US-003, US-008 | FND-BE-004, BE-008, BE-011 | FND-IT-004 |
| `FND-BR-004` at-least-once idempotent jobs | tech-stack §Queueing | FND-US-007 | FND-BE-009, BE-012 | FND-IT-003, FND-UT-003/006 |
| `FND-BR-006` secret-free logs/errors | prompt §5, §9 | FND-US-004, US-005 | FND-BE-005, BE-006 | FND-UT-001/004, FND-IT-005 |
| — (all infrastructure stories) | brd §8 Phase 1 | FND-US-001…009 | FND-BE-001…013, FND-INT-001…006 | FND-UT-001…006, FND-IT-001…008 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Deployment alignment (`docs/infra/architecture-and-deployment.md`): one binary with `serve`/`worker`/`migrate`/`migrate-status`/`healthcheck` (`FND-BE-014`); `serve` never migrates; worker idle back-off to 30 s; RealIP trusts only the local proxy; golang-migrate pinned | Claude |
| 2026-09-30 | Consistency pass: module-specific error codes registered (§10); migration version rule (monotonic in build order, see `docs/modules/README.md`) | Claude |
| 2026-09-30 | Isolated applications (owner): module 01 works only in the api repo — spec moved to `applications/api/openapi/openapi.yaml`, no `packages/shared`/Turborepo, TS client generation and web/app tooling moved to 02 (`DSN-FE-000`/`DSN-AP-000`); problem copy owned by api `internal/i18n` (`errors.*`); env adds `SHUTDOWN_TIMEOUT`, `TRUSTED_PROXIES`, `WORKER_CONCURRENCY`; verified pins recorded (§2) | Claude |
| 2026-09-30 | Owner: "complete 01-foundations for api, web and app" — web and app repo scaffolds return to 01 (`FND-FE-001`, `FND-AP-001`; were 02 `DSN-FE-000`/`DSN-AP-000`), `FND-INT-006` back in 01; web/app env vars added to §8.1; jobs `run_at` now uses the database clock (bug found by `FND-IT-003`) | Claude |
| 2026-09-30 | §8.1: local development on Postgres `kc` (localhost) with ports api 5433 · web 4433 · ai 8433 (reserved) via `applications/dev-start.sh`; production database is the Neon project `kushol-connect-db` (Singapore, Postgres 18) | Claude |
| 2026-09-30 | §5.1: Swagger UI at `/docs` and the spec at `/openapi.json` outside production (owner request) | Claude |
| 2026-09-30 | App: development builds + EAS, never Expo Go (owner); `com.kusholconnect.app`; `eas.json` (15 `OPS-AP-001`) pulled forward; local iOS scene-life-cycle plugin for iOS 27 (07-progress ADR-16/17) | Claude |
