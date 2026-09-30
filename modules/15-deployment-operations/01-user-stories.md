# Deployment & Operations — User Stories

**Module:** `15-deployment-operations`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Ships the platform's infrastructure and operations in two parts. **Part A** (after 01/02) — the walking skeleton: multi-stage images built in CI → GHCR, a Compose stack (**api + worker + web + redis only**) on the Hostinger KVM 2 VPS behind HestiaCP Nginx + Let's Encrypt TLS, one-command deploy gated on `/readyz`, rollback < 5 min. **Part B** (after 14) — production hardening: prod wiring (Neon, R2, FCM, gateways), nightly backups with an executed restore drill, runbooks, EAS pipelines, log discipline, and the pilot checklist — captured in `DEPLOYMENT.md`. Serves `brd.md` §8 (pilot readiness, rollout) and `persona.md` "Operate what you build": a small team must run this alone.

**Correction vs the README row (binding):** the index row says "Compose (Postgres/Redis/MinIO)"; `docs/tech-stack.md` §Infrastructure supersedes it (decision 2026-09-29): Postgres runs **off-box on Neon** (free tier, `ap-southeast-1`), media on **Cloudflare R2** — Compose runs **api + worker + web + redis only**; MinIO is deliberately not used. **Language split (binding):** runbooks and `DEPLOYMENT.md` are English (operator-facing); anything user-facing — maintenance banner/page copy, degraded-mode strings — is bn + en via the `ops.*` namespace in `applications/web/src/i18n` (bn default).

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Operator (Rahul / platform ops) | Owns deploys, rollbacks, backups, restore drills, secrets, runbooks; carries the pager |
| Developer (any module) | Merges to `main`; consumes GHCR images, deploy scripts, `.env.example` files |
| CI (GitHub Actions) | Builds/pushes images to GHCR; runs the secret scan; never builds on, or deploys from, the VPS |
| HestiaCP / Nginx (system) | TLS, reverse proxy to `127.0.0.1` containers, firewall, fail2ban, cert renewal |
| Docker / Compose (system) | Runs api + worker + web + redis with memory caps, restart policies, healthchecks |
| External uptime checker (system) | Polls `/healthz` + `/readyz` from off-box and raises alerts |
| EAS Build / Submit (system) | Builds APK/AAB, submits to Play / TestFlight from 02/03 assets |
| System (cron) | Nightly backup, quarterly drill reminder, log rotation |

No product end-user roles act here — every story is operator/developer/CI-facing (infrastructure).

## 3. Scope

**In scope**

- `Dockerfile` per deployable (api: Go multi-stage → distroless/alpine; web: Next standalone), built in CI → GHCR — never on the VPS
- `docker-compose.yml` (api + worker + web + redis; profiles; `mem_limit`, restart policies, healthchecks) + `.env.example` + `.dockerignore` per deployable
- HestiaCP Nginx proxy templates: `kusholconnect.com` (+ `/api/*`) / `api.kusholconnect.com` → `127.0.0.1`, TLS, security headers, WS upgrade, maintenance flag
- Deploy / rollback scripts gated on `/readyz` (01 contract); Makefile targets; release log
- Part B wiring: Neon prod DB, R2 buckets, FCM prod credentials (06 seam), gateway production cutover (12 seam)
- Nightly `pg_dump` → R2 (versioned) + off-site copy; restore script + executed, documented drill
- Runbooks (deploy, rollback, backup, restore, secret rotation, incident log) + `DEPLOYMENT.md`
- EAS Build/Submit profiles + OTA policy; Maestro smoke on the built APK in CI
- Log discipline (retention + redaction verified in prod); maintenance mode + `ops.*` bn/en strings; pilot checklist (2–3 schools)

**Out of scope** (explicit — prevents scope drift)

- Any product feature, screen or route (owned by 01–14); OpenAPI contract changes
- Postgres or MinIO containers on the VPS — superseded by `tech-stack.md` §Infrastructure (Neon + R2)
- Kubernetes, on-VPS image builds, log-aggregation SaaS, multi-VPS orchestration — rejected until measured need
- Data-model ownership: none — infrastructure module; 15 owns no tables (see 02 §1)

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 (Part A) | `/healthz` + `/readyz` gate, config-module env names, golang-migrate entrypoint, jobs metrics |
| 02 (Part A) | Web `standalone` output; app icon/splash for EAS; brand tokens for ops surfaces |
| 03 (Part B) | EAS Build/Submit wiring patterns + credentials handling |
| 06 (Part B) | FCM prod credential shape + post-cutover test push |
| 12 (Part B) | Sandbox→prod cutover list (gateway env names + webhook URLs) |
| all (Part B) | Deployable, env-complete, health-gated services before hardening begins |

---

## 4. User Stories

### `OPS-US-001` — Walking skeleton on the VPS (Part A)

**Priority:** P0 · **Traces:** brd.md §8 Phase 1 · tech-stack.md §Infrastructure · **Depends on:** 01, 02

**Story** — As an **operator**, I want `docker compose up` on the VPS to serve the web landing page and api health endpoints via HestiaCP Nginx with Let's Encrypt TLS on `kusholconnect.com` and `api.kusholconnect.com`, so that the platform has a real, secure deployment path from week one.

**Acceptance criteria**

- **Given** the VPS with Docker + HestiaCP, **when** `docker compose -p kushol up -d` runs with a filled `.env`, **then** `https://kusholconnect.com/` renders the landing page and `https://api.kusholconnect.com/healthz` returns 200 over valid TLS.
- **Given** the Compose file, **when** inspected, **then** only api + worker + web + redis exist (Postgres/MinIO deliberately absent — Neon + R2 off-box) and every container binds `127.0.0.1` only.
- **Given** a VPS reboot, **when** the host returns, **then** all containers self-heal via restart policies and report healthy within 2 minutes.

**Notes** — Memory caps: api 512m · worker 256m · web 512m · redis 256m, sized for the shared host (15 §9 Q5).

---

### `OPS-US-002` — Images built in CI, published to GHCR (Part A)

**Priority:** P0 · **Traces:** prompt.txt §11 · tech-stack.md §Infrastructure · **Depends on:** OPS-US-001

**Story** — As a **developer**, I want every merge to `main` to build multi-stage images (api: Go → distroless/alpine; web: Next standalone) in GitHub Actions and push to GHCR, so that the 2-vCPU shared VPS never builds an image.

**Acceptance criteria**

- **Given** a merge to `main`, **when** CI finishes, **then** `ghcr.io/<org>/kushol-api:main-<sha7>` and `…/kushol-web:main-<sha7>` (+ `latest`) exist in GHCR.
- **Given** the VPS, **when** any deploy runs, **then** it only pulls — no `docker build` exists in host scripts (lint-checked; BR-001).
- **Given** a failed CI build, **when** a merge lands red, **then** no new tag publishes and previous tags remain the deployable set; gitleaks runs in the same workflow (OPS-IT-003).

---

### `OPS-US-003` — One-command deploy gated on `/readyz` (Part A)

**Priority:** P0 · **Traces:** prompt.txt §11 · FND-US-006 · **Depends on:** OPS-US-001, OPS-US-002

**Story** — As an **operator**, I want `ops/deploy.sh <env> <tag>` to pull exact tags, confirm the database already has this release's migrations, restart services and pass a `/readyz` gate + smoke check, so that a bad build never reaches users silently.

**Acceptance criteria**

- **Given** a green CI tag, **when** `ops/deploy.sh pilot main-abc1234` runs, **then** it pulls pinned tags, checks `migrate-status` (read-only; migrations are run manually by the owner — Gate 2), `compose up -d`, polls `/readyz` ≤ 120 s and runs the smoke check (OPS-E2E-001) before success.
- **Given** `/readyz` red or timeout, **when** the gate fails, **then** the script automatically redeploys the previous logged tag (brief restart; old containers were already replaced), exits non-zero and writes an incident-log entry; a concurrent deploy is refused via lock file.
- **Given** the database is behind the image's expected migration version, **when** deploy runs, **then** it stops before changing any container and names the SQL files the owner must run.
- **Given** a Neon cold start during the gate, **when** retries run, **then** the warm-up (~hundreds of ms) is tolerated — no false red; readyz green after warm-up. The gate consumes the 01 contract verbatim.

---

### `OPS-US-004` — Rollback to the previous tag in under 5 minutes (Part A)

**Priority:** P0 · **Traces:** prompt.txt §11 · **Depends on:** OPS-US-003

**Story** — As an **operator**, I want `ops/rollback.sh <env>` to redeploy the previous immutable tag from the release log, so that a bad release is undone faster than users notice.

**Acceptance criteria**

- **Given** serving release `main-def5678` and previous `main-abc1234`, **when** `ops/rollback.sh pilot` runs, **then** the previous tag is redeployed, gated and serving in < 5 minutes (drill-timed).
- **Given** any deploy or rollback, **when** it completes, **then** `<timestamp> <env> <tag> <result>` is appended to the release log — rollback source is mechanical, never memory.
- **Given** a tag never deployed, **when** rollback targets it, **then** the script refuses — only logged releases are targets (tags immutable, BR-005; rollback is a redeploy, never a rebuild).

---

### `OPS-US-005` — Environment and secret discipline per deployable (Part A)

**Priority:** P0 · **Traces:** prompt.txt §11 · FND-BR-002 · **Depends on:** 01

**Story** — As an **operator**, I want every deployable's `.env.example` to mirror exactly its config-module keys, with real `.env` files only on the host (HestiaCP-hosted, chmod 600), so that no secret enters git, CI logs or an image.

**Acceptance criteria**

- **Given** the api + web config modules (01), **when** CI compares `.env.example` files against parsed keys, **then** they match exactly — missing/extra keys fail the build (OPS-UT-002).
- **Given** the VPS, **when** `.env` files are inspected, **then** they are root-owned, chmod 600, wired via Compose `env_file`, never committed (gitleaks clean).
- **Given** any `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `DEEPSEEK_API_KEY`, `FCM_SERVER_KEY`, `R2_*`, `BKASH_*`/`NAGAD_*`/`SSLCOMMERZ_*`, `GOOGLE_*/GITHUB_*`, `SMS_GATEWAY_*`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SITE_URL` value, **when** CI logs are sampled, **then** secrets are masked — never echoed (OPS-IT-003); env is parsed only by 01 config modules.

---

### `OPS-US-006` — Uptime monitoring, resource guards and maintenance comms (Part A + B)

**Priority:** P1 · **Traces:** persona "Operate what you build" · prd.md §4 · **Depends on:** OPS-US-001

**Story** — As an **operator**, I want an off-box checker on `/healthz` + `/readyz`, enforced memory caps/healthchecks on every container, and a Nginx-level maintenance mode with bn/en copy, so that outages and planned downtime are detected and communicated without a deploy.

**Acceptance criteria**

- **Given** the checker, **when** `/healthz` fails twice from outside, **then** an alert reaches the operator within 5 minutes (provider `TODO: Confirm`, 15 §9 Q1).
- **Given** any Compose service, **when** inspected, **then** it declares `mem_limit`, `restart: unless-stopped` and a healthcheck (BR-006); an OOM-killed api restarts and lands in the incident log.
- **Given** the maintenance flag set, **when** users open `kusholconnect.com` or the web build ships `NEXT_PUBLIC_MAINTENANCE_MODE=true`, **then** the static bn/en page (bn default) or banner shows `ops.maintenance.*` from `applications/web/src/i18n` — both entries build-checked; flag removal recovers instantly (`no-store`).

**Notes** — In-container healthchecks use `/healthz`; the deploy gate uses `/readyz` — different jobs, one contract (01).

---

### `OPS-US-007` — Production environment wiring (Part B)

**Priority:** P0 · **Traces:** prompt.txt §11 · brd.md §8 Phase 1 exit · **Depends on:** all modules (deployable), 06, 12

**Story** — As an **operator**, I want the production stack wired to real backing services — Neon prod DB, R2 buckets, FCM prod credentials (06 seam), payment-gateway production keys (12's sandbox→prod cutover) — so that the pilot runs on the environment it will keep.

**Acceptance criteria**

- **Given** the prod `.env`, **when** the api boots, **then** it connects to the Neon production DB (branch/DB created via console; connection string only in host `.env`) and R2 buckets exist with versioning enabled.
- **Given** `FCM_SERVER_KEY` (prod service account), **when** 06's post-cutover test push runs, **then** a real device receives it and the cutover is logged.
- **Given** module 12 shipped on sandbox keys, **when** the cutover runbook step executes, **then** `BKASH_*`/`NAGAD_*`/`SSLCOMMERZ_*` prod values + webhook URLs are registered and the checklist signed.

**Notes** — 06 owns the SDK, 12 owns gateway code, 15 owns env/secrets and the cutover ceremony — no code changes here.

---

### `OPS-US-008` — Nightly backups to R2 with versioning and an off-site copy (Part B)

**Priority:** P0 · **Traces:** prompt.txt §11 · tech-stack.md §Infrastructure (Backups) · **Depends on:** OPS-US-007

**Story** — As an **operator**, I want a nightly cron to run `ops/backup.sh` — `pg_dump` (custom format) → sha256 → R2 backups bucket (versioned) → off-site copy — so that no incident costs more than a day of data, and media stays protected by R2 versioning.

**Acceptance criteria**

- **Given** 02:30 Asia/Dhaka, **when** the cron fires, **then** `<env>-pg-<timestamp>.dump` + `.sha256` land in the versioned R2 bucket and the off-site copy completes (target `TODO: Confirm`, 15 §9 Q2) with a logged result.
- **Given** a deploy lock or low-disk guard, **when** backup starts, **then** it skips with a logged reason + alarm — never competes with a migration window.
- **Given** 30 days of artifacts, **when** retention runs, **then** older dumps prune per policy while recent ones remain untouched.

**Notes** — Neon automated backups stay the first line (`tech-stack.md`); this dump is the portable, operator-owned copy. BR-007: not a backup until restored.

---

### `OPS-US-009` — Restore drill executed and documented (Part B)

**Priority:** P0 · **Traces:** prompt.txt §11 · persona "backups you have restored" · **Depends on:** OPS-US-008

**Story** — As an **operator**, I want `ops/restore.sh` to restore any backup into a scratch Neon database with checksum verification and an api smoke test, and the drill executed and documented step-by-step, so that recovery is a rehearsed procedure, not a theory.

**Acceptance criteria**

- **Given** the latest nightly artifact, **when** `ops/restore.sh <artifact> <scratch-db>` runs, **then** the sha256 matches, restore completes, row-count sanity passes and the api boots green against scratch (OPS-IT-002).
- **Given** a checksum mismatch or failed step, **when** any part fails, **then** the script aborts non-zero, alarms, and the incident log records it — a silent partial restore is impossible.
- **Given** the pre-pilot gate, **when** the checklist is signed, **then** drill evidence (commands, timings, output) is attached to `07-progress.md` and summarized in `DEPLOYMENT.md`; repeated quarterly.

---

### `OPS-US-010` — Runbooks, incident log and prod log discipline (Part B)

**Priority:** P0 · **Traces:** prompt.txt §5, §9, §11 · persona "Operate what you build" · **Depends on:** OPS-US-003…009

**Story** — As an **operator**, I want English runbooks (deploy, rollback, backup, restore, secret rotation), an incident log template, and prod logs that are rotated JSON with verified redaction, so that one person can operate the platform alone at 2 a.m.

**Acceptance criteria**

- **Given** `DEPLOYMENT.md` + runbooks, **when** each is followed start-to-finish by someone who didn't write it, **then** each operation succeeds with no undocumented step (walkthrough recorded); secret rotation lands with < 5 min impact or a scheduled window.
- **Given** prod containers, **when** logs are inspected, **then** they are single-line JSON keyed by `X-Request-Id` with Docker rotation caps (default 10 MB × 5, 15 §9 Q3), and a weekly probe finds no `password`/`token`/`secret`/`authorization` values — probe failure files an incident entry.
- **Given** any incident, **when** the template is used, **then** it captures timeline, detection source, impact, rollback/restore actions and follow-ups.

**Notes** — slog + redaction ship in 01; 15 owns retention, rotation and the prod probe. Runbooks are English; user-facing incident copy ships bn + en via `ops.*`.

---

### `OPS-US-011` — EAS build pipelines and OTA update policy (Part B)

**Priority:** P1 · **Traces:** prd.md §4B · brd.md §8 Phase 1 · tech-stack.md §app · **Depends on:** 02, 03

**Story** — As a **developer**, I want EAS Build/Submit pipelines — `develop` → internal APK, production track → Play-ready AAB/APK + TestFlight submit — with an OTA (EAS Update) channel policy, so that app distribution matches `prd.md` §4B without ad-hoc local builds.

**Acceptance criteria**

- **Given** a commit to `develop`, **when** CI triggers EAS, **then** a `preview` APK (internal distribution) builds from 02 icon/splash assets with the pilot `EXPO_PUBLIC_API_URL`.
- **Given** a release tag, **when** the production profile runs, **then** a Play-ready AAB/APK builds and EAS Submit delivers the TestFlight track, versioned per profile.
- **Given** a JS-only fix, **when** an OTA update publishes, **then** it matches `runtimeVersion` policy, canaries `development` → `preview` → `production`, and a bad update rolls back via republish; Maestro smoke runs on the built APK first (OPS-AP-005).

**Notes** — EAS quota path: documented local `eas build` fallback (06 §8) — never the VPS.

---

### `OPS-US-012` — `DEPLOYMENT.md` and the pilot readiness checklist (Part B)

**Priority:** P0 · **Traces:** prompt.txt §11 · brd.md §8 Phase 1 exit (pilot 2–3 schools) · **Depends on:** OPS-US-001…011

**Story** — As an **operator**, I want `DEPLOYMENT.md` — topology, environments, deploy/rollback, backup/restore, runbook index, app distribution — and a pilot checklist per school, so that "pilot-ready for 2–3 schools" is a signed list, not a feeling.

**Acceptance criteria**

- **Given** a new operator with only the repo and VPS credentials, **when** they follow `DEPLOYMENT.md`, **then** they can deploy, roll back, back up, restore (drill) and rotate a secret without asking anyone.
- **Given** each pilot school, **when** the checklist executes, **then** prod envs set · fictional seed cleared/invisible ("Demo High School" DRAFT unreachable) · monitoring on · backup verified by restore · TestFlight invite + APK link live · school admin verified — each item ticked with a date.
- **Given** the scaling trigger (15 §9 Q4), **when** thresholds are crossed, **then** `DEPLOYMENT.md` states the next step (upgrade Neon / move Postgres / VPS sizing). The doc is English, in-repo, updated in the same commit as behaviour changes.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `OPS-BR-001` | Images are built in CI and pulled from GHCR — building on the VPS (2 vCPU, shared with 2 other applications) is a defect | CI workflow + host-script lint |
| `OPS-BR-002` | No secret enters git, CI logs or images; real env lives only in host `.env` (chmod 600), parsed solely by 01 config modules | gitleaks + masking + perms check |
| `OPS-BR-003` | No deploy serves traffic until `/readyz` (01 contract) is green and smoke passes; gate failure aborts before the swap | `ops/deploy.sh` gate |
| `OPS-BR-004` | One server stack (`kushol`) on the shared KVM 2 — pilot is promoted to prod, never run side by side; dev/pre-release stacks run locally against Neon branches and never share the server's containers, networks or `.env` | Compose project name + runbook |
| `OPS-BR-005` | Image tags are immutable (git SHA); rollback = redeploy the previous logged tag, never rebuild | GHCR tag scheme + release log |
| `OPS-BR-006` | Every container declares `mem_limit`, `restart: unless-stopped` and a healthcheck — uncapped is a defect on the shared host | Compose file + review checklist |
| `OPS-BR-007` | A backup is not a backup until a restore from it has succeeded (checksum-verified drill pre-pilot; quarterly after) | `ops/restore.sh` + pilot checklist |
| `OPS-BR-008` | Operator docs (runbooks, `DEPLOYMENT.md`) are English; any ops copy reaching end users ships bn + en from `applications/web/src/i18n` `ops.*` | Docs convention + build-time catalog check |

Content truth (`prompt.txt` §12): none shipped here — no publishable content. The only shipped copy is `ops.*` strings, which make no factual claims; provider names under `TODO: Confirm` stay unpublished until confirmed.

## 6. Validation Rules

| Field | Rule | Message key (`applications/web/src/i18n` catalog) |
| --- | --- | --- |
| Image tag | `^(main\|release)-[0-9a-f]{7,40}$`; deploy script refuses anything else | Operator-facing only — never rendered to end users |
| `.env` completeness | Every key in the deployable's `.env.example` present + non-empty for prod; parseable by 01 config | `ops.config.envIncomplete` — bn: `পরিবেশ ভেরিয়েবল অসম্পূর্ণ` / en: `Environment variables incomplete` (operator surfaces only) |
| Backup artifact | `<env>-pg-<YYYYMMDDTHHMMSSZ>.dump` + matching `.sha256` (pg_dump custom format) | `ops.backup.checksumMismatch` — bn/en (operator log + incident) |
| `/readyz` gate | HTTP 200 within 120 s post-swap, else deploy aborts | `ops.deploy.readyzTimeout` — bn/en (operator log) |
| Maintenance banner | `ops.maintenance.banner` exists in bn + en before the flag ships | Build-time check — `ops.maintenance.banner` (bn default, en) |
| Uptime check | `/healthz` polled ≥ 1×/min from off-box; alert ≤ 5 min | Operator-facing only |

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Second deploy started while one runs | Lock file refuses — no interleaved compose/migrate operations |
| 2 | `/readyz` green but login smoke fails | Deploy marked suspect; rollback path; incident entry |
| 3 | GHCR pull fails mid-deploy | Old containers keep serving (pull-before-swap); abort; retry safe |
| 4 | Neon cold start during the gate | Backoff retries ≤ 120 s; warm-up tolerated, never a false red |
| 5 | Backup cron fires in a migration window | Skip + logged reason + alarm; deploy unaffected; next window retries |
| 6 | VPS disk near-full | Backup aborts early + alarm; log rotation and pruning cap growth |
| 7 | Let's Encrypt renewal fails | HestiaCP alert + runbook; old cert serves until expiry; manual retry |
| 8 | Bad OTA update published to a channel | Republish previous bundle per policy; store builds unaffected |

## 8. Reporting Needs

Operator-side only — none of it feeds 07/09 product dashboards: backup log (last success, age, size), release log (deploys/rollbacks per env), uptime availability %, container memory/health state (weekly `docker stats` review), and `jobs` queue depth + DEAD counts via 01's readyz detail/metrics (FND-BE-013). Summarized into the incident log when thresholds trip.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | External uptime checker provider (`TODO: Confirm`) | Rahul | Open | UptimeRobot-class free checker: `/healthz` 60 s, `/readyz` 5 min, email + Telegram alerts |
| 2 | Off-site copy target for DB dumps beyond R2 | Rahul | Open | `rclone` sync to a second provider (`TODO: Confirm` before Part B); R2 versioning alone is not off-site |
| 3 | Log retention on the VPS | Rahul | Open | Docker `json-file` rotation 10 MB × 5 (~30 days); no external shipping during pilot |
| 4 | Scaling trigger off Neon free tier / single shared VPS | Rahul | Open | Upgrade Neon (Launch ~$19/mo) or move Postgres into Compose at real pilot traffic; VPS revisit at sustained CPU > 70%, > 10 schools, or a pilot SLA breach — recorded in `DEPLOYMENT.md` |
| 5 | Memory-cap sizing on the shared KVM 2 (8 GB total) | Rahul | Open | Compose `mem_limit` defaults api 512m · worker 256m · web 512m · redis 256m (≈ 1.5 GB Kushol; rest for HestiaCP + 2 co-tenants); adjust after the first monitoring week |
