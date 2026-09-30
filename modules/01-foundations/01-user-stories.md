# Foundations — User Stories

**Module:** `01-foundations`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Provides the platform skeleton every later module builds on, **inside the `applications/api` repository only** (each application is its own repo; there is no shared package — owner decision 2026-09-30): the Go `api` module, the OpenAPI contract it owns (`applications/api/openapi/openapi.yaml`) with Go codegen and a drift check, and the cross-cutting runtime concerns — fail-fast config parsing, sqlc + golang-migrate base, RFC-7807 errors with api-owned bn/en copy, `X-Request-Id` headers, redacted slog logging, health endpoints, the append-only `audit_log`, the in-DB `jobs` worker, the CI quality gate and the testcontainers harness. Pure infrastructure for `brd.md` §8 Phase 1 — no product feature of its own. Web and app scaffolding (including their generated TS clients) belongs to 02-design-system.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Developer (api) | Scaffolds the api repo, edits the spec, regenerates contract code, runs the quality gate |
| Module developer (02–15) | Consumes the api contract (web/app generate their own TS client from it), `jobs.Enqueue`, `audit.Record`, health endpoints |
| Operator (Rahul / platform ops) | Reads `/healthz` `/readyz`, owns config; audits destructive actions via `audit_log` later |
| CI (GitHub Actions) | Enforces lint / typecheck / test / build and the codegen drift check before merge |
| System (jobs worker) | Claims, runs, retries and dead-letters rows in the `jobs` table |

The five user roles and vendors (defined by 03-identity-access) have no surface here — every story is platform/developer/operator-facing (infrastructure).

## 3. Scope

**In scope**

- Go `api` repo scaffold (chi + gorilla/websocket shell) — `applications/api` only; no root workspace, no shared package
- OpenAPI 3.1 contract owned by api (`applications/api/openapi/openapi.yaml`) + Go codegen (oapi-codegen) with a CI drift check; web/app generate their own TS client from a synced copy (02 `DSN-FE-000`/`DSN-AP-000`)
- Env/config parsing module (Go), fail-fast, never read env elsewhere
- Postgres base: pgx pool, sqlc, golang-migrate, testcontainers-go harness
- RFC-7807 `application/problem+json` envelope with the shared code registry (bn/en copy)
- `X-Request-Id` middleware, security headers, redacted slog JSON logging
- Health: `/healthz` (liveness) + `/readyz` (Neon + Redis checks)
- `audit_log` (append-only) + `audit.Record`; `jobs` table + worker base (retry/backoff, dead-letter)
- CI quality gate per app + test harness

**Out of scope** (explicit — prevents scope drift)

- Any product feature, screen or route beyond health (03+); auth/OTP (03); hierarchy tables (04); web/app scaffolding, TS clients, tokens and client bn/en catalogs (02); Docker/Nginx/backups/runbooks (15); Kafka/RabbitMQ/Redis-Streams queues (rejected — `tech-stack.md` "Deliberately not used")

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| — (root module) | Nothing. External decisions recorded 2026-09-29: Neon Postgres (ap-southeast-1), Cloudflare R2, Hostinger KVM 2 + HestiaCP (README "Blocked before build", row 01) |

---

## 4. User Stories

### `FND-US-001` — api repo scaffold and fail-fast config

**Priority:** P0 · **Traces:** prd.md §6 · tech-stack.md §Shared & tooling · **Depends on:** —

**Story** — As a **developer**, I want the api repo, Go module and typed config module scaffolded with a fixed layout, so that every module lands in the same shape and bad config kills the process at boot.

**Acceptance criteria**

- **Given** a fresh clone of the api repo, **when** `make build` runs, **then** `go build ./...` compiles the api with pinned tools from `tools.mod` (no global installs).
- **Given** a missing/malformed required var (`DATABASE_URL`), **when** the api starts, **then** it exits non-zero naming the offending variable — never a partial start; no code reads env outside the config module (lint-enforced).
- **Given** a direct `os.Getenv`/`os.LookupEnv` outside `internal/config`, **when** golangci-lint runs, **then** lint fails (forbidigo rule).

**Notes** — api only; web/app scaffolds arrive with 02. Secrets (`JWT_SECRET`, gateway keys, …) are parsed by the config module from module 03 onward.

---

### `FND-US-002` — OpenAPI codegen pipeline (spec is the single source)

**Priority:** P0 · **Traces:** tech-stack.md §Shared & tooling · prompt.txt §1 · **Depends on:** FND-US-001

**Story** — As a **developer**, I want `applications/api/openapi/openapi.yaml` to generate the Go server types (oapi-codegen) and to be the file web/app generate their own clients from, so that API types are never hand-written on any side.

**Acceptance criteria**

- **Given** a spec change, **when** `make contracts` runs, **then** the Go types + server interface are regenerated.
- **Given** hand-edited generated code (or spec/code drift), **when** CI regenerates and diffs, **then** the merge is blocked.
- **Given** the skeleton spec, **when** the spec is validated and the api builds, **then** the generated Go compiles and the spec is valid OpenAPI 3.1 for client generators (the TS round-trip is proven by 02's `DSN-FE-000`/`DSN-AP-000`).

**Notes** — Initial spec: Problem schema, health paths, shared error shape only.

---

### `FND-US-003` — Postgres base: sqlc + golang-migrate + testcontainers

**Priority:** P0 · **Traces:** tech-stack.md §applications/api · **Depends on:** FND-US-001

**Story** — As a **developer**, I want pgx pooling, sqlc from plain SQL and golang-migrate wired to embedded migrations, so that every query runs through sqlc with tenant scope and tests hit a real Postgres.

**Acceptance criteria**

- **Given** a repository query touching tenant-owned rows, **when** written, **then** it carries the `school_id` scope or is declared platform-level with a proving test.
- **Given** `go test -tags=integration`, **when** tests run, **then** testcontainers-go starts a disposable Postgres, applies all migrations up, and tears down cleanly.
- **Given** any migration, **when** `down` then `up` run, **then** it reverses and reapplies.

**Notes** — uuid v7 is app-generated (Neon PG 16+ has no `uuidv7()`); see 03 §1.1.

---

### `FND-US-004` — Consistent RFC-7807 error envelope

**Priority:** P0 · **Traces:** prd.md §6 · prompt.txt §9–§10 (infrastructure) · **Depends on:** FND-US-002

**Story** — As a **developer consuming the api**, I want every error mapped to one `application/problem+json` envelope with a stable `code`, so that web/app handle failures uniformly with bn/en copy.

**Acceptance criteria**

- **Given** any service error, **when** a handler responds, **then** the body is RFC-7807 with `type`, `title`, `status`, `code` ∈ {UNAUTHENTICATED, FORBIDDEN, VALIDATION_FAILED, TENANT_MISMATCH, NOT_FOUND, NOT_VERIFIED, RATE_LIMITED, QUOTA_EXCEEDED, CONFLICT, INTERNAL}, localized `message` (bn default) and `requestId`.
- **Given** `Accept-Language: bn` (default) vs `en`, **when** validation fails, **then** the `message` is Bengali vs English — both shipped in the api's own catalog (`applications/api/internal/i18n`).
- **Given** an unknown future `code`, **when** a client renders it, **then** it falls back to the generic bn/en error string (open-set rule, 06 §7).

**Notes** — The `Problem` schema is defined once here; all modules reuse it.

---

### `FND-US-005` — Request-id header and redacted structured logging

**Priority:** P0 · **Traces:** prompt.txt §5, §9 · persona "Operate what you build" · **Depends on:** FND-US-001

**Story** — As an **operator**, I want every response to carry `X-Request-Id` and every log line to be redacted JSON keyed by it, so that I can correlate a request without leaking secrets.

**Acceptance criteria**

- **Given** a request without `X-Request-Id`, **when** handled, **then** a uuid v7 is generated, echoed in the response header and attached to all slog entries for that request.
- **Given** an incoming `X-Request-Id` (sanitized, ≤ 64 chars), **when** handled, **then** it is reused, not replaced.
- **Given** log fields like `password`/`token`/`secret`/`authorization`, **when** slog emits, **then** values are `[REDACTED]`.

**Notes** — slog JSON to stdout only; log shipping is module 15's concern.

---

### `FND-US-006` — Health endpoints prove readiness

**Priority:** P0 · **Traces:** prompt.txt §5 · consumer 15-deployment-operations · **Depends on:** FND-US-001

**Story** — As an **operator**, I want `/healthz` (liveness) and `/readyz` (Neon + Redis), so that monitoring and deploy gating can tell "alive" from "ready" — including Neon cold starts.

**Acceptance criteria**

- **Given** a running process, **when** `GET /healthz` is called, **then** it returns 200 without touching dependencies.
- **Given** Neon + Redis reachable, **when** `GET /readyz` is called, **then** 200; given Redis stopped, **then** 503 `application/problem+json` naming the failed dependency (bn/en).
- **Given** a Neon cold start, **when** requests arrive, **then** they get fast 503 problems (never hangs) and `/readyz` turns green automatically after warm-up.

**Notes** — Public by design; IP restriction is `TODO: Confirm` (01 §9, Q3).

---

### `FND-US-007` — In-DB job queue and Go worker base

**Priority:** P0 · **Traces:** tech-stack.md §Queueing · **Depends on:** FND-US-003

**Story** — As a **developer (modules 04/08/09/12)**, I want `jobs.Enqueue` plus a registered-handler worker over the `jobs` table, so that background work runs reliably without Kafka/RabbitMQ.

**Acceptance criteria**

- **Given** an enqueued job and N workers, **when** claiming via `FOR UPDATE SKIP LOCKED`, **then** exactly one worker runs each attempt (no double-claim).
- **Given** a failing handler, **when** attempts < max_attempts, **then** the job re-queues with `run_at` = backoff (5s × 2^n + jitter); at max_attempts it becomes DEAD with `last_error`.
- **Given** `Enqueue` with a used `idempotency_key`, **when** it runs, **then** the existing job id returns and no duplicate row is created.

**Notes** — At-least-once semantics; handlers must be idempotent (BR-004). SIGTERM drains in-flight jobs.

---

### `FND-US-008` — Append-only audit log and `audit.Record` helper

**Priority:** P1 · **Traces:** brd.md §6 · prompt.txt §9 (infrastructure) · **Depends on:** FND-US-003, FND-US-005

**Story** — As an **auditor (Super Admin surfaces, later)**, I want every destructive or financial action appended to `audit_log` with actor, entity and before/after state, so that accountability survives incidents.

**Acceptance criteria**

- **Given** `audit.Record` inside a transaction, **when** the action commits, **then** the audit row commits atomically; if the insert fails, the action aborts — no un-audited commit.
- **Given** any UPDATE/DELETE on an audit row, **when** executed, **then** the DB rejects it.
- **Given** a school-scoped list query, **when** rows span tenants, **then** only that `school_id`'s rows return (null `school_id` = platform-level).

**Notes** — Emitting sites arrive with feature modules (11 order cancel, 12 refunds); this module ships table, helper and enforcement.

---

### `FND-US-009` — CI quality gate blocks merges

**Priority:** P0 · **Traces:** prompt.txt §10 · tech-stack.md §CI · **Depends on:** FND-US-001 … FND-US-008

**Story** — As a **developer**, I want the api repo's GitHub Actions workflow to run the gate (`go test/vet/lint` + integration) and the codegen drift check, so that nothing merges red. (web/app gates live in their own repos — 02.)

**Acceptance criteria**

- **Given** a PR touching `applications/api`, **when** CI runs, **then** gofmt/goimports, golangci-lint, `go vet`, unit and testcontainers integration tests must pass.
- **Given** a failing required check, **when** merge is attempted, **then** it is blocked — no skip flags.

**Notes** — EAS build hooks for `app` are added by 02/03 when screens ship; only the task graph exists here.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `FND-BR-001` | API types are generated from `applications/api/openapi/openapi.yaml`, never hand-written; drift fails CI | CI drift check + `make contracts` |
| `FND-BR-002` | Env/config read only inside the config module; missing/invalid config fails startup fast | Config module + forbidigo lint rule (Go); web/app enforce the same in their repos (02) |
| `FND-BR-003` | Every repository query touching tenant-owned rows includes a `school_id` scope, or is declared platform-level with a proving test | Repository layer + integration tests |
| `FND-BR-004` | The `jobs` queue is at-least-once; handlers must be idempotent (use `idempotency_key` where producers may duplicate) | Worker + handler contract (03 §5) |
| `FND-BR-005` | `audit_log` is append-only — UPDATE/DELETE rejected by the DB; every destructive/financial action writes an entry in the same transaction | DB rule/trigger + `audit.Record` |
| `FND-BR-006` | Logs and error bodies never contain secrets, tokens or full webhook payloads; configured fields are redacted | slog redaction + envelope writer |

Content truth (`prompt.txt` §12): "None — infrastructure module"; no publishable content is seeded here. Fictional demo data ("Demo High School", DRAFT) starts with its owning modules (04+).

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| `DATABASE_URL` | Non-empty `postgres://`/`postgresql://` URL (Neon direct endpoint); ping at boot | Not user-facing — startup error names the variable |
| `REDIS_URL` | Non-empty `redis://`/`rediss://` URL | Not user-facing — startup error names the variable |
| `APP_ENV` | Enum `development` \| `test` \| `production` | Not user-facing — startup error names the variable |
| `LOG_LEVEL` | Enum `debug` \| `info` \| `warn` \| `error` | Not user-facing — startup error names the variable |
| `HTTP_PORT` | Integer 1–65535 (in-container listen port; the host port is 15's `API_PORT`) | Not user-facing — startup error names the variable |
| `SHUTDOWN_TIMEOUT` · `TRUSTED_PROXIES` · `WORKER_CONCURRENCY` | Positive duration (default `20s`) · IPs/CIDRs (default `127.0.0.1/32,::1/128`) · integer 1–32 (default 2) | Not user-facing — startup error names the variable |
| Envelope `message` | Always present, bn + en, bn default | `errors.<code>` per code (e.g. `errors.validation_failed`) in the api catalog |
| `X-Request-Id` in | Optional; ≤ 64 chars, printable; else generate | Not user-facing — log only |

Mirrored by the OpenAPI `Problem` schema. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED` — no protected endpoints exist here; chain proven via stub claims (FND-IT-006) and by 03 |
| 2 | Cross-tenant read/write attempt | `TENANT_MISMATCH`/404 — proven on `audit_log` scoped reads (FND-IT-004); pattern carries forward |
| 3 | Neon cold start mid-traffic | Fast 503 problems (never hang); `/readyz` red → green after warm-up |
| 4 | Generated code hand-edited / spec drift | CI drift check blocks merge; fix is `make contracts` |
| 5 | Worker crash mid-job | Stale `locked_at` → reaper requeues; at-least-once honoured |
| 6 | Audit insert fails inside a destructive action | Transaction aborts — action not applied, `INTERNAL` |
| 7 | Malformed incoming `X-Request-Id` | Ignored; fresh uuid v7 generated and echoed |

## 8. Reporting Needs

None directly — no dashboards consume this module's product data. `jobs` queue depth and dead-letter counts are exposed for `15-deployment-operations` operational dashboards later.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Repositories + toolchain | Rahul | Resolved 2026-09-29; layout revised 2026-09-30 | One git repo per app, no shared package; Go module for `api` (chi + gorilla/websocket + sqlc + pgx + golang-migrate); OpenAPI 3.1 in `applications/api/openapi/` generating Go server types; web/app own their toolchains and clients (02); Postgres on Neon (region per plan F1); media on Cloudflare R2; VPS = Hostinger KVM 2 + HestiaCP |
| 2 | Where do generated TS clients live? | Rahul | Resolved 2026-09-30 (owner: no shared package) | Each client generates its own: `applications/web/src/api/`, `applications/app/src/api/` |
| 3 | `/readyz` public or loopback-only in production? | Rahul | Open | Public; Nginx/IP restriction applied later by 15 if needed |
