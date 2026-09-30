# Foundations — Integration Tasks

**Module:** `01-foundations` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

`02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
**contract**. No cross-module call, cache key or external dependency may exist in code unless it is
declared here (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `02`–`15` (all later modules) | they call us | `applications/api/openapi/openapi.yaml` — oapi-codegen Go server types generated here; web/app sync a copy and generate their own openapi-typescript/openapi-fetch client in their repos (02) | fatal — api build breaks on drift (CI drift gate); client drift caught by each client repo's check |
| I-2 | `04` (migration), `08` (AI), `09` (analytics), `12` (receipts) | they call us | `jobs.Enqueue` / `jobs.Register` worker interface | degraded — job stays QUEUED, retried with backoff |
| I-3 | all modules with destructive/financial actions (11–13 first) | they call us | `audit.Record` helper | fatal for the wrapped action — no un-audited destructive commit |
| I-4 | `15-deployment-operations` | they call us | `GET /healthz`, `GET /readyz` (uptime checks, deploy gating) | degraded — deploy gate red, alarms fire |
| I-5 | Neon Postgres (external) | we call | pgx wire protocol (TLS) | fatal for DB-dependent request paths (fail fast 503) |
| I-6 | Redis (external) | we call | go-redis (RESP) | degraded — limiter falls back in-process; readyz red |
| I-7 | GitHub Actions + GHCR (external CI) | we call | workflow runs; images built in CI (never on VPS) | fatal for merge (gate by design); degraded for deploy cadence |

## 2. Exported Contract

```text
codegen  : make contracts · make contracts-check   # openapi.yaml → Go server types (clients generate their own)
health   : GET /healthz · GET /readyz
jobs     : jobs.Enqueue(ctx, JobType, payload any, opts ...EnqueueOption) (uuid.UUID, error)
           jobs.Register(JobType, Handler)        # Handler: Handle(ctx context.Context, payload []byte) error
audit    : audit.Record(ctx context.Context, e audit.Entry) error
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `openapi.yaml` + `make contracts` | 02–15, CI | regenerated Go types/`ServerInterface` + embedded spec (request validation) | build error on invalid spec | spec is the single source; regenerate on every change; CI fails on drift (BR-001); client repos sync a copy |
| `GET /healthz` | 15, HestiaCP/Nginx uptime | 200 `{"status":"ok"}` | — | liveness only, no dependency checks, `no-store` |
| `GET /readyz` | 15 deploy gate | 200 per-dependency results, or 503 problem+json | — | checks Neon + Redis (1s timeouts); bn/en degraded messages |
| `jobs.Enqueue` / `jobs.Register` | 04, 08, 09, 12 | job id (existing id on idempotency-key hit) | error if type unregistered / payload invalid | at-least-once; handlers must be idempotent (BR-004); DTO payloads via typed wrappers, never raw maps |
| `audit.Record` | all modules performing destructive/financial actions | nil | error aborts the surrounding transaction | append-only target; entries secret-free (BR-006) |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| Neon Postgres (wire, `DATABASE_URL`) | Neon (external, ap-southeast-1) | boot fails fast if unreachable at start; runtime requests 503 fast; `/readyz` red; cold start self-heals |
| Redis (`REDIS_URL`) | self-hosted on VPS (Compose, module 15) | reconnect loop; limiter falls back to per-process token bucket; readyz red |
| GitHub Actions / GHCR | GitHub (external) | merges blocked (by design); gates runnable locally via `make gate` |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| None — this module performs no cached reads and exposes no mutable cached entities; later modules declare their own tags here (e.g. 05 §4 chat/notice tags) | — |

| Read | Tagged with |
| --- | --- |
| None — no cached reads; `/healthz` `/readyz` are `no-store` | — |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Neon Postgres | PostgreSQL wire, TLS | `DATABASE_URL` (config module only) | connect 5s; query ctx per handler | pool ping backoff (cold start) | 503 problem responses; readyz red; self-heals on warm |
| Redis | RESP (go-redis) | `REDIS_URL` | 2s ops | 3 retries, exp backoff | in-process limiter fallback; presence/chat (05) degrade, never fatal |
| GitHub Actions / GHCR | HTTPS, OIDC/GITHUB_TOKEN | repo secrets | n/a (async) | manual re-run | merge gate blocks; no deploy impact until 15 |

FCM, Cloudflare R2, DeepSeek, payment gateways and the SMS gateway are **not** wired here — their
owning modules declare them (05/06: FCM · 05/08: R2 · 08: DeepSeek · 12: gateways · 03: SMS).

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| N/A — no screens in this module. The seam artifact is the api's spec; web/app generate their `openapi-fetch` client and mirror shapes in their own `src/schemas` (02 `DSN-FE-000`/`DSN-AP-000`); first consumers are 03 (app/web login) and 07 (web portals) | — | — |

## 7. Contract Stability

- `applications/api/openapi/openapi.yaml` is the single source: regenerate the Go contract code on every
  spec change; hand-editing generated files is a defect (INV-005, BR-001).
- Schema changes expand/contract; migrations applied files are immutable; spec changes additive
  first (new optional fields/new routes), removals only after consumers migrate.
- Error `code` values are an open set: consumers must fall back to generic bn/en copy on unknown
  codes; `Problem` schema is shared and versioned with the spec.
- Localized problem `message` strings ship in the api's bn/en catalog (`internal/i18n`, bn default);
  the spec carries only the message keys — copy changes never require a spec change.
- Generated code is committed; CI regenerates and fails on any diff — "spec changed" and
  "code regenerated" must be the same commit.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| Neon cold start (free tier) | `/healthz`, static middleware path | 503 problem+json, bn/en message ("service warming up"); readyz red | first connection warms the DB; readyz green automatically; no data loss |
| Neon hard outage | `/healthz`; enqueue buffered in memory is NOT offered (by design — no silent loss) | 503 everywhere DB is needed | incident path per 15 runbooks; jobs already QUEUED resume after restore |
| Redis down | all non-limiter routes; jobs worker | slightly looser rate limits (in-process fallback); readyz red | auto-reconnect; chat presence (05) degrades to no-presence |
| GitHub Actions outage | local dev + local `make gate` | PR merges blocked | re-run when CI returns; gates are required checks |
| Codegen drift | nothing merged — CI red on the PR | developer-facing drift diff | `make contracts`, commit with the spec change |
| Worker crash | API request paths; jobs stay QUEUED (locked rows requeued by reaper ≤ 5 min) | delayed background effects only | reaper; at-least-once delivery honoured |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `FND-IT-007` | Generated-contract round-trip: `openapi.yaml` validates as OpenAPI 3.1 (kin-openapi loader) and oapi-codegen output compiles into the api build; the TS side is proven in the client repos (02 `DSN-FE-000`/`DSN-AP-000`) | Integration (CI) | one spec serves Go and the client generators (I-1) |
| `FND-IT-008` | Drift check: CI regenerates contract code → `git diff --exit-code` passes | Integration (CI) | no hand-edited generated code (BR-001) |
| `FND-UT-006` | `jobs.Enqueue` idempotency-key dedupe + typed payload wrapper validation | Unit | exported jobs API contract |
| `FND-E2E-*` | None — no user-facing surfaces; Playwright golden paths start with 07-command-center-web, Maestro with 03-identity-access onboarding | — | — |

## 10. Task Checklist

- [ ] `FND-INT-001` — codegen pipeline wired into Make targets + CI drift job (FND-IT-007/008 green)
- [ ] `FND-INT-002` — health endpoints exposed and documented as the 15-deployment-operations seam (uptime + deploy gate)
- [ ] `FND-INT-003` — `jobs.Enqueue`/`Register` interface published; consumer stubs (04/08/09/12 shapes) compile against it
- [ ] `FND-INT-004` — `audit.Record` helper exported; example call from a generated server stub verified
- [ ] `FND-INT-005` — api `.env.example` covers Neon/Redis wiring consumed later by 15 Compose
- [x] `FND-INT-006` — ~~generated TS client consumable~~ — moved to 02 (`DSN-FE-000` / `DSN-AP-000`) by the owner's isolated-apps decision — 2026-09-30
