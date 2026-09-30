# Deployment & Operations — Backend Tasks & Database Design

**Module:** `15-deployment-operations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (Neon, off-box) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging — *consumed as a GHCR image; this module builds the image, not the code*
**Stack (web):** Next.js standalone output · zod forms · generated `openapi-fetch` client → api — *consumed as a GHCR image*
**Stack (infra):** Docker + Compose v2 (api + web + redis) · GitHub Actions → GHCR · HestiaCP (Nginx/TLS/firewall) · bash deploy/rollback/backup/restore scripts · cron · Makefile
**Last updated:** 2026-09-30

No product schema exists here. This module's "schema" is the **infra-as-code inventory** (§3/§7); the real data design of module 15 **is the backup/restore strategy** (§1). Postgres is off-box on Neon and media off-box on R2 per `docs/tech-stack.md` §Infrastructure — Compose runs api + web + redis only.

---

## 1. Database Design

### 1.1 Tables

**None — infrastructure module.** 15 owns no tables; the data model is owned by modules 01–14 (health + `jobs`/`audit_log`: 01-foundations §1, which this module probes via `/readyz` and protects via backups).

The module's data design **is** the backup strategy: Neon automated backups (first line, `tech-stack.md` §Infrastructure) + nightly `pg_dump` (custom format, sha256-checksummed) into the versioned R2 backups bucket + off-site `rclone` copy, proven by an executed restore drill (OPS-IT-002, BR-007). Media/receipts on R2 are protected by bucket versioning + the off-site copy policy.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | None owned by this module — `ops/deploy.sh` applies the module-owned golang-migrate migrations (01 pattern, expand/contract) at deploy time via `compose run --rm api migrate up`, after a DB pre-flight ping and before the container swap | N/A — no migrations owned |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| None — infrastructure module. Pilot step "seeds cleared" = per-school runbook verification that fictional demo data ("Demo High School", DRAFT) is removed or invisible before real users onboard | — | prompt.txt §12 · 01 §9/15 §7 (edge case) |

---

## 2. Server Contracts

No product endpoints are created. The contracts below are the ones this module **consumes** and the script/nginx surfaces it **exports** (full exported contract: 06 §2).

### Consumed endpoint `GET /readyz` — the deploy gate (owned by 01)

| | |
| --- | --- |
| **Auth** | none (public; IP restriction decision open — 01 §9 Q3) |
| **Input** | none |
| **Result** | `200` per-dependency results (Neon + Redis) → gate passes; `503` `application/problem+json` naming failed dependencies → gate fails |
| **Errors** | gate treats any non-200 within 120 s as failure — abort before swap (BR-003) |
| **Rate limit** | `default` class (01) |
| **Audit** | deploy log entry on every gate result |
| **Stories** | OPS-US-003, OPS-US-004 |

### Consumed endpoint `GET /healthz` — uptime + in-container healthcheck target (owned by 01)

| | |
| --- | --- |
| **Auth** | none — liveness only, `no-store` |
| **Result** | `200` `{"status":"ok"}` — polled by the external checker (60 s) and by Compose healthchecks |
| **Stories** | OPS-US-006 |

### Script contract `ops/deploy.sh <env> [tag]`

| | |
| --- | --- |
| **Input** | env ∈ {pilot, prod}; tag default `latest` resolved to `main-<sha7>` from the release log |
| **Guards** | lock file (no concurrent deploys); tag scheme check (15 §6); `.env` completeness (OPS-UT-002) |
| **Result** | pull exact tags → migrate up → `compose up -d` → `/readyz` ≤ 120 s → smoke (OPS-E2E-001) → release-log line; exit 0 |
| **Errors** | non-zero + incident-log entry on lock held / pull failure / gate red / smoke red — old stack keeps serving |
| **Stories** | OPS-US-003 |

### Script contracts `ops/rollback.sh <env>` · `ops/backup.sh` · `ops/restore.sh <artifact> <target>`

| | |
| --- | --- |
| **rollback** | previous tag from release log → redeploy + gate; < 5 min; refuses unknown targets (BR-005) |
| **backup** | `pg_dump -Fc` → `.sha256` → R2 (versioned) → off-site `rclone` → prune; skips on deploy-lock/low-disk with alarm |
| **restore** | checksum verify → restore to scratch (drill) or target DB → row-count sanity → api smoke; any failure aborts non-zero (BR-007) |
| **Stories** | OPS-US-004, OPS-US-008, OPS-US-009 |

### Nginx vhost contract (HestiaCP custom proxy template)

| | |
| --- | --- |
| `api.<domain>` | → `127.0.0.1:8080`; WS upgrade headers for the gateway path; `client_max_body_size 25m`; TLS (Let's Encrypt, auto-renew); HSTS + security headers (OPS-FE-002) |
| `web.<domain>` | → `127.0.0.1:3000`; static-asset caching; TLS; security headers; CSP (OPS-FE-002) |
| Maintenance flag | flag file present → serve static bn/en page (`no-store`) instead of proxying `web.` (OPS-US-006) |

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web routes. The only web-side artifacts are build-time inputs (`NEXT_PUBLIC_*` env, `NEXT_PUBLIC_MAINTENANCE_MODE`) and `ops.*` strings rendered by 04 §2.

---

## 3. Service Layer Tasks

Infra-as-code inventory — each row is a *file/artifact delivered*, not a Go service:

| ID | Method (artifact) | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `OPS-BE-001` | `deploy/Dockerfile.api` — multi-stage: Go build (CGO off, static) → `distroless/static` (or alpine) non-root runtime; `migrate` entrypoint baked from the same build | No build tools in the runtime layer; < 40 MB target | — | — |
| `OPS-BE-002` | `deploy/Dockerfile.web` — Next `output: "standalone"` build (pnpm fetch → build → runner), non-root, `NEXT_PUBLIC_*` as build args | < 250 MB target; boots and serves `/` in CI boot-check | — | — |
| `OPS-BE-003` | `deploy/docker-compose.yml` — services api/web/redis; profiles per env; `mem_limit` 1.5g/1g/512m; `restart: unless-stopped`; healthchecks (`/healthz`); `127.0.0.1` bindings; log rotation options; project names `kushol-<env>` | No Postgres/MinIO services (BR-001/tech-stack); INV-004/005/007 | — | — |
| `OPS-BE-004` | `.env.example` (api, web) + `.dockerignore` per deployable — keys exactly matching 01 config modules incl. `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `DEEPSEEK_API_KEY`, `FCM_SERVER_KEY`, `R2_*`, `BKASH_*`/`NAGAD_*`/`SSLCOMMERZ_*`, `GOOGLE_/GITHUB_*`, `SMS_GATEWAY_*`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SITE_URL` | CI completeness check (OPS-UT-002); comments mark prod-only keys | — | — |
| `OPS-BE-005` | CI image workflow — on merge to `main`: gitleaks → build api + web → push GHCR `main-<sha7>` + `latest`; boot-check job for web standalone | Required check; tags immutable (BR-005); no `docker build` outside CI (BR-001) | — | — |
| `OPS-BE-006` | HestiaCP custom proxy templates + notes — `api.`/`web.` vhosts, TLS, WS upgrade, body-size limits, security headers, maintenance flag | Templates versioned in repo; post-panel-upgrade diff + re-apply runbook (02 §11 risk 6) | — | — |
| `OPS-BE-007` | `ops/deploy.sh` — full gate pipeline per §2 script contract; writes `ops/releases.log` | BR-003; cron-safe (no prompts); stdout machine-readable | — | release log |
| `OPS-BE-008` | `ops/rollback.sh` — previous-tag redeploy from release log + gate; timed drill evidence | BR-005; < 5 min target | — | release log |
| `OPS-BE-009` | `ops/backup.sh` + cron (02:30 Asia/Dhaka) — `pg_dump -Fc` → `.sha256` → R2 versioned bucket → off-site `rclone` → prune (30-day default, 15 §9 Q2/Q3) | Skips + alarms on deploy-lock/low disk; never blocks a migration window | — | backup log |
| `OPS-BE-010` | `ops/restore.sh` + step-by-step drill procedure (into scratch Neon DB) — checksum → restore → row-count sanity → api smoke | Any failure aborts + alarms (BR-007); drill evidence filed in `07-progress.md` | — | incident log on failure |
| `OPS-BE-011` | Secret-rotation runbook + host hygiene — `.env` chmod 600 root-owned; rotation order per credential (`JWT_SECRET`, `DATABASE_URL`, `R2_*`, `FCM_SERVER_KEY`, gateway keys, `EXPO_TOKEN`) | BR-002; < 5 min impact or scheduled window; no repo/CI change | — | runbook checklist |
| `OPS-BE-012` | `Makefile` targets — `deploy`, `rollback`, `backup`, `restore-drill`, `smoke`, `images` (thin wrappers over `ops/`) | Wrappers only; no second implementation of any script | — | — |
| `OPS-BE-013` | Part B production wiring — Neon prod DB (console), R2 buckets + versioning, FCM prod `FCM_SERVER_KEY` (06 seam), gateway prod keys + webhook URLs (12 cutover), prod `.env` on host | Env-only changes; each cutover logged + signed in the runbook (OPS-US-007) | — | cutover log |
| `OPS-BE-014` | Log discipline in prod — Docker `json-file` rotation (10 MB × 5 default), weekly redaction probe script over sampled logs (FND-BR-006 verified live) | Probe failure → incident entry (OPS-US-012) | — | incident log on failure |
| `OPS-BE-015` | Maintenance mode — Nginx flag → static bn/en page; `NEXT_PUBLIC_MAINTENANCE_MODE` build input for the banner; enable/disable runbook steps | Strings from `packages/shared` `ops.*` (BR-008); `no-store` | — | change log entry |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| — | **None — infrastructure module.** No application tables or sqlc queries. The only DB-touching operations are `pg_dump`/`psql`/migrate driven by `DATABASE_URL` from host env (parsed by 01 config) | `pg_dump -Fc` full snapshot; golang-migrate `up` (owned by 01) | — |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `OPS-BE-009` | Nightly backup (dump → checksum → R2 → off-site → prune) | cron 02:30 Asia/Dhaka | yes — timestamped artifacts; rerun safe | skip + alarm on deploy-lock/low disk; alarm on upload failure; next window retries |
| `OPS-BE-010` | Restore drill (quarterly + pre-pilot) | calendar/cron reminder | yes — scratch target each time | failure blocks pilot sign-off (BR-007) + incident entry |
| `OPS-BE-014` | Weekly redaction probe over prod logs | cron (weekly) | yes — read-only sampling | failure → incident entry + rotation runbook check |
| HestiaCP | Let's Encrypt renewal | panel scheduler | yes | panel alert + manual renew runbook (02 §8 #9) |
| external | Uptime checks: `/healthz` 60 s, `/readyz` 5 min | checker service | n/a | alerts ≤ 5 min; provider `TODO: Confirm` (15 §9 Q1) |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `OPS-UT-001` | Backup script unit checks: artifact naming `<env>-pg-<ts>.dump` + `.sha256` generation, exit codes, dry-run mode, prune selection | Unit (script tests, e.g. bats) | US-008 artifact contract; 15 §6 validation rows |
| `OPS-UT-002` | `.env.example` completeness: every key parsed by the 01 api/web config modules exists per deployable; no unknown extras | Unit (CI) | US-005; FND-BR-002 seam |
| `OPS-UT-003` | Tag-scheme validator: accepts `main-<sha7>`/`release-*`, refuses `latest`-only or arbitrary tags in deploy context | Unit | BR-005, INV-006 |
| `OPS-IT-001` | Deploy dry-run on a fresh Compose stack (local docker / testcontainers where a DB is needed): images pull → migrate up → services healthy → `/readyz` 200 → smoke green | Integration | US-001, US-003; INV-003/004/007 |
| `OPS-IT-002` | Restore drill on scratch DB: latest dump checksum matches → restore completes → row-count sanity → api boots green against scratch | Integration | US-009; BR-007 |
| `OPS-IT-003` | Secret hygiene: gitleaks clean on repo; CI logs sampled post-run contain no unmasked secret values; host `.env` perms `600` checked by script | Integration (CI + host check) | US-005; BR-002 |
| `OPS-E2E-001` | Post-deploy smoke, automated: `GET /healthz` 200 + `GET /` landing 200 + login round-trip through the real Nginx/TLS front door | E2E (Playwright; APK smoke = OPS-AP-005) | US-003 gate; the deploy is only "done" when this passes |

Always include: the gate never trusts a green `/readyz` without the smoke (edge case 2, 15 §7); restore never runs against prod implicitly (target is explicit); scripts are non-interactive (cron-safe).

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

None — infrastructure module (§1). The infra-as-code inventory is this module's schema:

- [ ] `OPS-BE-001` — Dockerfile.api (multi-stage, distroless/alpine, non-root)
- [ ] `OPS-BE-002` — Dockerfile.web (Next standalone, non-root, CI boot-check)
- [ ] `OPS-BE-003` — docker-compose.yml (api/web/redis, caps, healthchecks, profiles)
- [ ] `OPS-BE-004` — `.env.example` + `.dockerignore` per deployable (01-key parity)
- [ ] `OPS-BE-005` — CI image workflow → GHCR (+ gitleaks)
- [ ] `OPS-BE-006` — HestiaCP proxy templates (TLS, WS, headers, maintenance flag)

### Repository · Service · Entry points · Seed · Tests

- [ ] `OPS-BE-007` — deploy script + release log + gate
- [ ] `OPS-BE-008` — rollback script (< 5 min drill)
- [ ] `OPS-BE-009` — backup script + cron + R2 + off-site + prune
- [ ] `OPS-BE-010` — restore script + drill procedure
- [ ] `OPS-BE-011` — secret-rotation runbook + host `.env` hygiene
- [ ] `OPS-BE-012` — Makefile targets
- [ ] `OPS-BE-013` — Part B production wiring (Neon, R2, FCM, gateways)
- [ ] `OPS-BE-014` — prod log rotation + redaction probe
- [ ] `OPS-BE-015` — maintenance mode (Nginx + build flag)
- [ ] Seed — None — infrastructure module
- [ ] `OPS-UT-001`…`OPS-UT-003`, `OPS-IT-001`…`OPS-IT-003`, `OPS-E2E-001` — test plan above
