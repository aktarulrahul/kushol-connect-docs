# Foundations — Build Progress

**Module:** `01-foundations` · **Apps:** `api` · `web` · `app` · **Repos:** `applications/api`,
`applications/web`, `applications/app` (each its own git repo, branch `module/01-foundations`,
nothing committed yet) · **Last updated:** 2026-09-30

## Stages & gates

| Stage / gate | Status | Date | Notes |
| --- | --- | --- | --- |
| 1 · Read & plan | ✅ approved ("go ahead") | 2026-09-30 | C1/C2 taken as the recommended defaults, then superseded by the owner's isolated-apps instruction (ADR-1) |
| 2 · UI build | N/A | 2026-09-30 | No product screens in 01; web/app get placeholder `/` routes only (brand name) |
| Gate 1 · UI approval | Skipped (N/A) | 2026-09-30 | Per `prompt-build.md` §3 exception |
| 3 · Docs sync | ✅ | 2026-09-30 | Checklists ticked, registries + tech-stack pins updated |
| 4 · Backend build | ✅ code + unit + integration green | 2026-09-30 | See evidence |
| Gate 2 · owner runs migrations | ⏳ **waiting on owner** | — | Versions `20260930000001–000003` against Neon (direct endpoint) |
| 5 · Integration | ✅ `FND-INT-001…006` | 2026-09-30 | Web/app repo scaffolds added on owner instruction (ADR-8) |
| Gate 3 · integrated flows | ⏳ waiting on owner | — | Developer golden paths (below) |
| 6 · Gaps & verification | ✅ `08-gaps.md` written · final verification ⏳ owner | 2026-09-30 | Module stays 🚧 until Gates 2, 3 and final verification pass |

## Owner decisions during the build (ADRs)

| # | Decision | Effect |
| --- | --- | --- |
| ADR-1 | **Isolated applications** (owner, 2026-09-30): each of `applications/api`, `web`, `app`, `ai` is its own git repo; no shared package, no root pnpm/Turborepo workspace | Removed the root workspace and `packages/shared` built earlier; spec lives in `applications/api/openapi/openapi.yaml`; api owns its bn/en copy in `internal/i18n`; docs + `prompt.txt` updated (91 files) |
| ADR-2 | Keep the hand-built `jobs` queue (not River) | River's own migrations and maintenance loops clash with owner-run migrations and Neon idle; infra plan F16 closed |
| ADR-3 | Go config parser: `caarlos0/env` v11 | Struct tags + defaults; errors mapped back to env names |
| ADR-4 | `db.Querier` interface + transaction-in-context (`db.InTx`/`db.WithTx`) | `audit.Record` refuses to run outside a tx; `jobs.Enqueue` joins the caller's tx |
| ADR-5 | Problem `type` = `about:blank`, `title` = HTTP status text; `VALIDATION_FAILED` = 400; `TENANT_MISMATCH` = 404 with not-found copy | Recorded in `internal/problem` |
| ADR-6 | Reaper sends a stale lock to DEAD (not QUEUED) when attempts are exhausted | Keeps FND-INV-004 true |
| ADR-7 | Go tools pinned in a separate `tools.mod` | Keeps sqlc/golangci-lint deps out of the binary's `go.mod` |
| ADR-8 | **Web and app scaffolds belong to 01** (owner, 2026-09-30: "complete the 1-foundations for api, web and app") | `FND-FE-001` / `FND-AP-001` (were 02 `DSN-FE-000` / `DSN-AP-000`, now marked delivered by 01); `FND-INT-006` back in 01. 02 keeps tokens, fonts, catalogs, primitives, icon/splash |
| ADR-9 | **Job times come from the database clock** | `FND-IT-003` failed on first run: enqueue/retry wrote `run_at` from the api host clock while claiming compares with Postgres `now()`, so any skew (Docker VM here; VPS vs Neon in production) delayed new jobs. `InsertJob` now uses `COALESCE(run_at, now())`, `MarkJobRetry` uses `now() + delay`; the test measures backoff on the DB clock |
| ADR-10 | ESLint 10 without `eslint-config-next` / `eslint-config-expo` | Their bundled react/import/jsx-a11y plugins don't declare ESLint 10 support (checked 2026-09-30). Both repos use `@eslint/js` + `typescript-eslint` strict-type-checked + react-hooks (+ `@next/eslint-plugin-next` on web) |
| ADR-11 | TypeScript 6.0.3 (not 7.0) in web and app | typescript-eslint 8.71 supports `<6.1`. TS 6 no longer loads `@types/*` automatically, so the app lists `types` explicitly |
| ADR-12 | Client repos check drift against their **committed** spec copy | CI can't see the api repo; `pnpm sync:api-spec` copies it locally, and `pnpm contracts:check` regenerates into a temp file and compares |

## Defaults relied on

- Q3 (01 §9): `/readyz` public; module 15 may restrict it.
- C5: default rate-limit class 120 req/min/IP — `TODO: Confirm` (owner Rahul), in `ratelimit.DefaultRule`.
- Go module path `github.com/aktarulrahul/kushol-connect/applications/api` — `TODO: Confirm` the api repo's final remote.
- `jobs.status` keeps `FAILED` in its CHECK (spec); no code path sets it.
- Postgres major for tests `postgres:17-alpine` — `TODO: Confirm` against the Neon project's major at Gate 2.
- App identifiers (`android.package`, `ios.bundleIdentifier`) not set — `TODO: Confirm` before the first EAS build (15).

## Pinned versions (verified 2026-09-30)

**api:** Go 1.26.1 · chi v5.3.2 · pgx v5.11.0 · golang-migrate v4.20.1 · sqlc v1.31.1 · oapi-codegen
v2.8.0 · kin-openapi v0.149.0 · nethttp-middleware v1.2.0 · caarlos0/env v11.4.1 · google/uuid v1.6.0
· go-redis v9.22.0 · x/time v0.16.0 · testcontainers-go v0.44.0 · golangci-lint v2.14.0.
**web:** Next.js 16.3.7 · React 19.3.0 · TypeScript 6.0.3 · Tailwind 4.3.3 · ESLint 10.11.0 · Vitest
5.0.2 · Playwright 1.63.0 · @axe-core/playwright 4.13.0.
**app:** Expo SDK 57 (57.0.26) · expo-router 57.0.24 · React Native 0.86.3 · React 19.2.3 · jest-expo
57.0.5 · jest 29.7.0.
**Both clients:** openapi-typescript 7.13.0 · openapi-fetch 0.17.0 · zod 4.6.5 · Prettier 3.9.9 ·
pnpm 11.8.0 · Node ≥ 22.12. **CI:** actions/checkout v7 · setup-go v7 · setup-node v7 ·
pnpm/action-setup v6 · upload-artifact v7. Full list in `docs/tech-stack.md`.

## Evidence (2026-09-30)

| Repo | Check | Result |
| --- | --- | --- |
| api | `make gate` (fmt-check · contracts-check · vet · lint · test -race · test-integration) | exit 0 · `contracts: no drift` · `0 issues` |
| api | `go test -tags=integration -count=1 ./...` | **90 tests pass, 0 fail** (unit + FND-IT-001…007, reaper, drain, testcontainers Postgres 17 + Redis 7) |
| api | First integration run | `FND-IT-003` failed (`first attempt not claimed`) → ADR-9 fix → green |
| api | forbidigo probe (`os.Getenv` outside config) | rejected |
| api | `make build` | `bin/api` 21 MB; `migrate up` without `--confirm` → exit 2; empty env → exit 1 naming every variable |
| web | `pnpm gate` (format · lint · typecheck · test · contracts:check · build) | green · 6 unit tests · `contracts: no drift` · standalone build |
| web | `pnpm test:e2e` (standalone server, 1280px + 768px) | 2/2 pass · axe: 0 serious/critical |
| web | build without env | fails: `EnvError: … NEXT_PUBLIC_API_URL, NEXT_PUBLIC_SITE_URL` |
| app | `pnpm gate` (format · lint · typecheck · test · contracts:check) | green · 7 unit tests · `contracts: no drift` |
| app | `expo-doctor` | 21/21 checks pass |
| app | `expo export --platform android` | Hermes bundle 2.7 MB |
| web + app | boundary probe (`process.env`, `fetch`, `openapi-fetch` outside allowed files) | 3/3 rejected in each repo |

## Developer golden paths (Gate 3)

1. **api:** `cd applications/api && make gate` → exit 0 (Docker running).
2. **api on Neon (after Gate 2):** `bin/api migrate-status` → `dirty=false`, versions equal; `bin/api serve` → `curl localhost:8080/healthz` = `{"status":"ok"}`; `curl -H 'Accept-Language: en' localhost:8080/readyz` = 200 with `postgres`/`redis` ok (stop Redis → 503 problem+json, `dependencies[].ok=false`).
3. **api worker:** `bin/api worker` runs next to `serve` and logs the idle poll; Ctrl-C drains within `SHUTDOWN_TIMEOUT`.
4. **web:** `cd applications/web && pnpm install && cp .env.example .env.local && pnpm dev` → `/` shows "কুশল CONNECT"; `pnpm gate && pnpm test:e2e` green.
5. **app:** `cd applications/app && pnpm install && cp .env.example .env` (LAN IP) → `pnpm start` → open on a device/emulator → "কুশল CONNECT" centred; `pnpm gate` green.
6. **Contract loop:** add a field to `applications/api/openapi/openapi.yaml` → api `make contracts-check` fails until `make contracts` → in web and app, `pnpm contracts:check` stays green until `pnpm sync:api-spec` then fails until `pnpm generate:api`. Revert afterwards.

## Checklist status

All 01 items ticked 2026-09-30: `FND-BE-001…014`, seed (none), `FND-UT-*`, `FND-IT-*`,
`FND-INT-001…006`, `FND-FE-001`, `FND-AP-001`. Ticked = built and verified locally. Delivery
still needs Gates 2 and 3 and the owner's final verification.

## Findings raised to other modules

- 15 / infra plan F19: `TRUSTED_PROXIES` must include the Compose network CIDR.
- 15 / infra plan F18: home repo for Compose, Hestia templates and ops scripts now that the apps are separate repos.
- 15: the web Docker image should run `.next/standalone/server.js` and copy `.next/static` (as the E2E config already does); `outputFileTracingRoot` is pinned to the repo.
- 02: starts from the scaffolded web/app repos (`DSN-FE-000`/`DSN-AP-000` marked delivered by 01).
- Panic values are logged with their stack (server-side only). A panic message that contains a secret would reach the log, so handlers must not panic with secrets (BR-006 note).
