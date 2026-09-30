# Foundations — Build Progress

**Module:** `01-foundations` · **App:** `api` · **Repo:** `applications/api` (own git repo, branch
`module/01-foundations`, nothing committed yet) · **Last updated:** 2026-09-30

## Stages & gates

| Stage / gate | Status | Date | Notes |
| --- | --- | --- | --- |
| 1 · Read & plan | ✅ approved ("go ahead") | 2026-09-30 | C1/C2 taken as the recommended defaults, then superseded by the owner's isolated-apps instruction (below) |
| 2 · UI build | N/A | 2026-09-30 | No web/app surfaces in 01 |
| Gate 1 · UI approval | Skipped (N/A) | 2026-09-30 | Per `prompt-build.md` §3 exception |
| 4 · Backend build | 🚧 code complete; integration suite written, **not yet run** (Docker daemon not running on the dev Mac) | 2026-09-30 | See evidence |
| Gate 2 · owner runs migrations | ⏳ waiting on owner | — | Versions `20260930000001–000003` |
| 5 · Integration | not started | — | `FND-INT-*` |
| Gate 3 · integrated flows | not started | — | Developer golden paths |
| 6 · Gaps & verification | not started | — | |

## Owner decisions during the build (ADRs)

| # | Decision | Effect |
| --- | --- | --- |
| ADR-1 | **Isolated applications** (owner, 2026-09-30): each of `applications/api`, `web`, `app`, `ai` is its own git repo; no shared package, no root pnpm/Turborepo workspace | Removed the root workspace and `packages/shared` built earlier this session; spec moved to `applications/api/openapi/openapi.yaml`; TS client generation + web/app tooling moved to 02 (`DSN-FE-000`/`DSN-AP-000`); api owns its bn/en copy in `internal/i18n`; docs + `prompt.txt` updated (91 files) |
| ADR-2 | Keep the hand-built `jobs` queue (not River) | River's own schema/migration tooling and maintenance loops clash with owner-run migrations and Neon idle; infra plan F16 closed |
| ADR-3 | Go config parser: `caarlos0/env` v11 | Struct tags + defaults; errors mapped back to env names |
| ADR-4 | `db.Querier` interface (not `DBTX`) + transaction-in-context (`db.InTx`/`db.WithTx`) | `audit.Record` refuses to run outside a tx; `jobs.Enqueue` joins the caller's tx |
| ADR-5 | Problem `type` = `about:blank`, `title` = HTTP status text; `VALIDATION_FAILED` = 400; `TENANT_MISMATCH` = 404 with not-found copy (no existence oracle) | Recorded in `internal/problem` |
| ADR-6 | Reaper sends a stale lock to DEAD (not QUEUED) when attempts are already exhausted | Keeps FND-INV-004 true; spec lifecycle said "→ QUEUED" only |
| ADR-7 | Tools pinned in a separate `tools.mod` (`go tool -modfile=tools.mod …`) | Keeps sqlc/golangci-lint deps out of the binary's `go.mod` |

## Defaults relied on

- Q3 (01 §9): `/readyz` public; module 15 may restrict it.
- C5: default rate-limit class 120 req/min/IP — `TODO: Confirm` (owner Rahul), in `ratelimit.DefaultRule`.
- Go module path `github.com/aktarulrahul/kushol-connect/applications/api` — `TODO: Confirm` the api repo's final remote.
- `jobs.status` keeps `FAILED` in its CHECK (spec); no code path sets it.
- Postgres major for tests `postgres:17-alpine` — `TODO: Confirm` against the Neon project's major at Gate 2.

## Pinned versions (verified 2026-09-30)

Go 1.26.1 (1.27.1 available) · chi v5.3.2 · pgx v5.11.0 · golang-migrate v4.20.1 · sqlc v1.31.1 ·
oapi-codegen v2.8.0 (OpenAPI 3.1 supported) · kin-openapi v0.149.0 · nethttp-middleware v1.2.0 ·
caarlos0/env v11.4.1 · google/uuid v1.6.0 · go-redis v9.22.0 · x/time v0.16.0 ·
testcontainers-go v0.44.0 · golangci-lint v2.14.0 · goimports (x/tools v0.50.0) ·
actions/checkout v7 · actions/setup-go v7. ESLint 9 is out of support → tech-stack now says ESLint 10
(for 02).

## Evidence (2026-09-30, `applications/api`)

| Check | Result |
| --- | --- |
| `make fmt-check` | clean |
| `make contracts-check` | `contracts: no drift` |
| `go vet ./...` (+ `-tags=integration`) | clean |
| `make lint` (golangci-lint v2, incl. integration files) | `0 issues` |
| forbidigo probe (`os.Getenv` outside config) | rejected as expected |
| `go test -race ./...` | 10/10 packages pass, 73 test cases incl. subtests: FND-UT-001…006, FND-IT-005, FND-IT-006, auth-chain rejection order, RealIP trust, redaction, catalog parity |
| `go test -tags=integration ./...` | **not run** — needs Docker (FND-IT-001…004, reaper, drain) |
| `make build` | `bin/api` 21 MB |
| Binary guards | `migrate up` without `--confirm` → exit 2; empty env → exit 1 naming `APP_ENV, DATABASE_URL, HTTP_PORT, LOG_LEVEL, REDIS_URL` |

## Checklist status (ticked only after Gate 2 + integration run)

Code done, pending verification: `FND-BE-001…014`, `FND-UT-001…006`, `FND-IT-001…006`.
Moved to 02: `FND-INT-006`. Not started: `FND-INT-001…005` wiring checks (Stage 5).

## Findings raised to other modules

- 15 / infra plan F19: `TRUSTED_PROXIES` must include the Compose network CIDR (Docker publishes
  ports through the bridge gateway).
- 15 / infra plan F18: home repo for Compose/Hestia templates/ops scripts now that apps are
  separate repos.
- 02: now owns web/app scaffolding and client generation (`DSN-FE-000`, `DSN-AP-000`,
  token pin `DSN-UT-005`).
- Panic values are logged with their stack (server-side only); a panic message that embeds a
  secret would reach the log — handlers must not panic with secrets (BR-006 note).
