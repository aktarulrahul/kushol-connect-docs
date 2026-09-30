# Deployment & Operations — Technical Document

**Module:** `15-deployment-operations`
**Version:** 0.1
**Status:** 📝 Draft 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

Single engineer-facing reference compressing this module's spec set (`01`–`06`). When this file
drifts, the spec files win.

> Infrastructure plan: `docs/infra/architecture-and-deployment.md` (architecture, host checks, DNS, email).
> This spec set was aligned with it on 2026-09-30.

---

## 1. Overview

### 1.1 Purpose

Ships the platform's infrastructure and operations in two parts. **Part A** (after 01/02) — the
walking skeleton: multi-stage images built in CI → GHCR, a Compose stack (**api + worker + web + redis
only**) on the Hostinger KVM 2 VPS behind HestiaCP Nginx + Let's Encrypt TLS, one-command deploy
gated on `/readyz`, rollback < 5 min. **Part B** (after 14) — production hardening: prod wiring
(Neon, R2, FCM, gateways), nightly backups with an executed restore drill, runbooks, EAS
pipelines, log discipline, and the pilot checklist — captured in `DEPLOYMENT.md`. Serves
`brd.md` §8 (pilot readiness, rollout) and persona "Operate what you build".

**Binding correction vs the README row:** `docs/tech-stack.md` §Infrastructure (decision
2026-09-29) supersedes "Compose (Postgres/Redis/MinIO)" — Postgres runs **off-box on Neon** (free
tier, `ap-southeast-1`), media on **Cloudflare R2**; Compose runs **api + worker + web + redis only**;
MinIO is deliberately not used. **Language split (binding):** runbooks and `DEPLOYMENT.md` are
English (operator-facing); user-facing ops copy (maintenance banner/page, degraded-mode strings)
is bn + en via `ops.*` in `packages/shared` (bn default).

### 1.2 Scope

**In:** `Dockerfile` per deployable (api: Go multi-stage → distroless/alpine; web: Next
standalone), built in CI → GHCR — never on the VPS; `docker-compose.yml` (api + worker + web + redis;
profiles; `mem_limit`, restart policies, healthchecks) + `.env.example` + `.dockerignore`;
HestiaCP Nginx proxy templates (apex + `api.` → `127.0.0.1`, TLS, security headers, WS upgrade,
maintenance flag); deploy/rollback scripts gated on `/readyz` + Makefile + release log; Part B
wiring (Neon prod DB, R2 buckets, FCM prod credentials via the 06 seam, gateway production
cutover via the 12 seam); nightly `pg_dump` → R2 (versioned) + off-site copy + restore script +
executed drill; runbooks + `DEPLOYMENT.md`; EAS Build/Submit profiles + OTA policy + Maestro smoke
in CI; log discipline (retention + redaction verified in prod); maintenance mode + `ops.*` bn/en
strings; pilot checklist (2–3 schools).

**Out:** any product feature, screen or route (01–14); OpenAPI contract changes; Postgres or
MinIO containers on the VPS; Kubernetes, on-VPS image builds, log-aggregation SaaS, multi-VPS
orchestration (rejected until measured need); data-model ownership — none, infrastructure module.

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 (Part A) | `/healthz` + `/readyz` gate (consumed verbatim), config-module env names, golang-migrate entrypoint, jobs metrics |
| consumes | 02 (Part A) | Web `standalone` output; app icon/splash for EAS; brand tokens for ops surfaces |
| consumes | 03 (Part B) | EAS Build/Submit wiring patterns + credentials handling |
| consumes | 06 (Part B) | FCM prod credential shape + post-cutover test push |
| consumes | 12 (Part B) | Sandbox→prod cutover list (gateway env names + webhook URLs) |
| consumed by | all (Part B) | Deployable, env-complete, health-gated services before hardening begins; 01's Redis `REDIS_URL` points at the Compose redis (loopback) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| Containers | Docker multi-stage builds + Compose v2 | api (Go → distroless/static or alpine, < 40 MB) + web (Next `output: "standalone"`, < 250 MB) + redis; `mem_limit`, healthchecks, `127.0.0.1` bindings | `docs/tech-stack.md` §Infrastructure |
| Host / proxy | Hostinger KVM 2 (2 vCPU / 8 GB, shared with 2 co-tenant apps) · Ubuntu 24.04 · HestiaCP + Nginx + Let's Encrypt + fail2ban | TLS, reverse proxy to loopback containers, firewall, cert renewal for all 3 apps on the box | Custom proxy templates versioned in repo |
| CI / registry | GitHub Actions → GHCR | Images built in CI and pulled by the VPS — never build on the KVM 2 | `tech-stack.md` CI row; gitleaks in the same workflow |
| App build/CI | **EAS Build / Submit / Update** (Expo) | APK/AAB + TestFlight per `prd.md` §4B; OTA channels; Maestro smoke on the built APK | `tech-stack.md` app table |
| Data services | Neon Postgres (off-box, TLS wire) · Cloudflare R2 (S3 API: media + versioned backups bucket + off-site `rclone` copy) | Zero RAM/CPU for DB/media on the shared host | Decision 2026-09-29, binding over the README row |
| Ops tooling | bash scripts (`ops/deploy|rollback|backup|restore.sh`) · cron · Makefile · gitleaks | One-command, cron-safe, non-interactive operation | Consumes 01 contracts; builds nothing itself |

---

## 3. Architecture

### 3.1 Component diagram

```text
GitHub Actions (CI) ──build + gitleaks──► GHCR : ghcr.io/<org>/kushol-{api,web}:main-<sha7>
                                                │ pull exact tags (never build on VPS, BR-001)
users ─HTTPS─► HestiaCP Nginx (TLS, LE, fail2ban, maintenance flag)                 │
   │        ├─ api.kusholconnect.com ──► 127.0.0.1:8180 ─┐                                   ▼
   │        ├─ kusholconnect.com (www → 301) ──► 127.0.0.1:3100; /api/* → 8180 ─┤ Compose project kushol
   │        └─ flag → static bn/en page         ├─ api   (mem 512m, restart, healthcheck) + worker (256m)
   │                                            ├─ web   (mem 512m)   └─ redis (256m, loopback)
   ├─ api ──TLS──► Neon Postgres (off-box, ap-southeast-1)   ◄─ cron 02:30 ops/backup.sh
   ├─ api ──TLS──► Cloudflare R2 (media + versioned backups bucket → off-site rclone copy)
   ├─ api ──► FCM · bKash/Nagad/SSLCommerz · DeepSeek · SMS (module-owned code, 15-wired env)
   └─ external uptime checker ──► GET /healthz (60 s) + GET /readyz (5 min)
```

### 3.2 Boundary

**Owns (tables / services):** no tables — infra-as-code only: `deploy/` (Dockerfile.api,
Dockerfile.web, docker-compose.yml, HestiaCP template notes, `.dockerignore`), `ops/` (deploy/
rollback/backup/restore scripts, `ops/releases.log`, cron definitions, Makefile targets),
`.env.example` per deployable, CI image-publish workflow, `eas.json`, static maintenance page,
runbooks + `DEPLOYMENT.md`, `ops.*` keys in `packages/shared`.

**Reads (via exported contracts only):** 01 `/healthz` + `/readyz` (never reimplemented or
proxied), config env names, migrate entrypoint, `jobs` metrics; 02 standalone output + assets;
06 FCM credential shape; 12 gateway cutover list. Cache contract: none — no cached reads, no
revalidation surface (`06` §4).

### 3.3 Request / data flows

```text
1. Deploy (release lifecycle): merge to main → CI builds + pushes main-<sha7> (+ gitleaks)
   → ops/deploy.sh <env> [tag]: lock file → pull exact tags (old stack untouched, pull-before-
   swap) → schema check (`migrate-status` read-only; DB behind → stop, owner runs SQL — Gate 2) → compose up -d → poll
   /readyz ≤ 120 s (2 s interval; Neon cold start tolerated) → smoke (OPS-E2E-001) → release-log
   line. Pull/schema failure: exit ≠ 0 before any swap (old containers keep serving). Gate/smoke failure: automatic
   rollback to the previous logged tag, exit ≠ 0, incident-log entry (brief restart blip either way).
2. Rollback: ops/rollback.sh <env> → previous tag from ops/releases.log → redeploy + gate, < 5
   min; refuses tags never deployed (immutable tags; rollback is a redeploy, never a rebuild).
3. Backup / restore: cron 02:30 Asia/Dhaka → ops/backup.sh: pg_dump -Fc → .sha256 → R2 versioned
   bucket → off-site rclone → prune (30-day default); skips + alarms on deploy-lock/low disk.
   ops/restore.sh <artifact> <target>: checksum verify → restore to scratch/target → row-count
   sanity → api smoke; any failure aborts non-zero + alarms (BR-007: not a backup until restored).
4. Traffic topology: users → HestiaCP Nginx TLS (apex + `api.` subdomain) → loopback containers →
   Neon/R2 off-box; external uptime checker polls /healthz + /readyz from off-box and alerts
   ≤ 5 min; app: EAS profile builds → Maestro smoke on the preview APK → distribution.
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| Release (Part A) | BUILT, PULLED, VERIFIED, GATED, SERVING, ROLLED_BACK | merge → BUILT (CI quality gates + gitleaks green) · BUILT → PULLED (deploy lock held; tag scheme matches) · PULLED → VERIFIED (`migrate-status`: DB at the image's expected version — owner already ran the SQL; else stop, nothing changed) · VERIFIED → GATED (`compose up -d`; healthchecks pass) · GATED → SERVING (`/readyz` 200 ≤ 120 s + smoke green; release log) · GATED → ROLLED_BACK (gate/smoke red; previous tag redeployed automatically; incident entry) · SERVING → SERVING (rollback: previous logged tag, < 5 min) |
| App channels (Part B) | development / preview / production | build + submit per profile; OTA publish = channel-scoped, `runtimeVersion`-matched; canary development → preview (24 h) → production; bad bundle → republish previous |
| Backup cycle | dump → checksum → R2 → off-site → prune → DRILL | nightly, each step gated (skip + alarm on lock/low disk); drill quarterly + pre-pilot; drill failure blocks pilot sign-off |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1. Operational entities (Release, Environment, Backup artifact,
Runbook/incident entry, App release channel) live as infra state — log files, compose labels,
object storage, repo docs — not rows.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| None — infrastructure module | 15 owns no tables; product tables (incl. 01's `audit_log`/`jobs`) are owned by 01–14, probed via `/readyz` and protected via backups. The module's data design **is** the backup/restore strategy: Neon automated backups (first line) + nightly sha256-checksummed `pg_dump` (custom format) into the versioned R2 backups bucket + off-site `rclone` copy, proven by an executed, documented restore drill (OPS-IT-002, BR-007); R2 media/receipts protected by bucket versioning + off-site policy | N/A | N/A | Migrations: none owned — `ops/deploy.sh` applies module-owned golang-migrate migrations at deploy time. Seed: none; pilot step verifies fictional demo data ("Demo High School", DRAFT) is cleared/invisible |

---

## 5. Contracts

### 5.1 REST endpoints

No product endpoints are created. The REST surface here is **consumed**, not exported; the
exported contracts are scripts + docs (§5.3) plus the Nginx vhost contract (`api.`→
`127.0.0.1:8180` with WS upgrade + 2 m body limit (media via R2 presign); apex→`127.0.0.1:3100` (+ `/api/`→8180) with static caching +
CSP/security headers; maintenance flag serving the static bn/en page `no-store`) — `03` §2.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /readyz` (owned by 01) | public (deploy gate + checker) | Per-dependency results (Neon + Redis) → gate passes | any non-200 within 120 s = gate fail → abort before swap (BR-003) | OPS-US-003/004 |
| 2 | `GET /healthz` (owned by 01) | public, `no-store` | Liveness — polled by the external checker (60 s) and Compose healthchecks | — | OPS-US-006 |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| Nightly backup (OPS-BE-009) | cron 02:30 Asia/Dhaka | dump → checksum → R2 → off-site → prune; timestamped artifacts (rerun safe) | backup log + operator | skip + alarm on deploy-lock/low disk; upload-failure alarm; next window retries |
| Restore drill (OPS-BE-010) | quarterly + pre-pilot reminder | checksum → scratch restore → row-count sanity → api smoke | pilot sign-off, DR | failure blocks sign-off + incident entry |
| Weekly redaction probe (OPS-BE-014) | cron (weekly) | read-only sampling of prod logs for `password`/`token`/`secret`/`authorization` values | incident log | probe failure → incident entry + rotation runbook check |
| Let's Encrypt renewal | HestiaCP scheduler | ACME auto-renew | all vhosts | panel alert + manual renew runbook; old cert serves until expiry |
| Uptime checks | external checker service | `/healthz` 60 s + `/readyz` 5 min, off-box | operator alerts | alerts ≤ 5 min; provider `TODO: Confirm` (§14 #1) |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `ops/deploy.sh <env> [tag]` | operator (documented for CI rescue) | exit 0 + release-log line on SERVING; the only sanctioned deploy path (BR-003); cron-safe, non-interactive | lock held / pull fail / gate red / smoke red — old stack keeps serving |
| `ops/rollback.sh <env>` | operator | previous tag SERVING < 5 min (drill-timed); tags immutable (BR-005) | unknown/absent previous tag |
| `ops/backup.sh` | cron + operator | artifact + `.sha256` in R2 + off-site copy + backup-log line | lock/low-disk skip; upload-failure alarm |
| `ops/restore.sh <artifact> <target>` | operator (drill/DR) | restored target + verification report; target always explicit — never implicitly prod | checksum mismatch aborts (BR-007) |
| `make deploy│rollback│backup│restore-drill│smoke│images` | developers | thin wrappers over `ops/` — no second implementation | — |
| `DEPLOYMENT.md` + runbooks (deploy · rollback · backup · restore · secret rotation · incident-log template) + health-endpoint usage doc | whole team, new operators, uptime checker | English procedures; health contracts owned by 01, documented/used here only | — |

Script CLIs are additive-first; documented exit codes; machine output on stdout, progress on
stderr; no prompts; safe to re-run (`06` §2/§7).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/maintenance` (Nginx-served static, bypasses Next) | Maintenance page: brand mark, `ops.maintenance.title/body` bn default + `?lang=en`, no nav/forms, works without JS; incident variant copy | Static file pair | Public |
| `/` (landing, owned by 07) | Ops hardening target only: CSP + security headers via the Nginx template (OPS-FE-002) and Lighthouse CI CWV budget gate in prod (OPS-FE-003); standalone output verified in CI (OPS-FE-001) | Server Component | Public |
| global (root layout) | OpsBanner: rendered only when `NEXT_PUBLIC_MAINTENANCE_MODE=true` at build; `role="status"`, dismissible, `ops.maintenance.banner` bn/en; tree-pruned (zero bundle cost) when off | Client Component | Public + all admin roles |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| None — no routes added; the ops surface is `eas.json` + CI wiring + the distribution checklist: EAS profiles development/preview/production with per-channel `EXPO_PUBLIC_API_URL` (OPS-AP-001/004), icon+splash from 02 (OPS-AP-002), OTA channels + `runtimeVersion` policy + canary/republish-rollback documented in `DEPLOYMENT.md` (OPS-AP-003), Maestro smoke on the built preview APK at 360px/throttled before any distribution (OPS-AP-005), distribution checklist — TestFlight group + signed APK link + version/notes (OPS-AP-006) | — | none from this module | none — app runtime/offline behaviour stays owned by 03/05/06 |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| GHCR | Image registry | OCI push/pull | `GITHUB_TOKEN` (CI push) · read-only pull token in host `.env` | pull 120 s; 3× backoff → abort | deploys blocked; running stack unaffected (INV-001) |
| Hostinger KVM 2 + HestiaCP | Host, Nginx/TLS, firewall, fail2ban, certs | SSH (key-only, non-root deploy user) + panel templates | SSH keys; panel creds (operator) | — | full stack down → DR runbook (fresh box + restore scripts + DNS); panel upgrades can clobber templates → diff + re-apply runbook |
| Neon | Production Postgres | PostgreSQL wire (TLS) + console provisioning | `DATABASE_URL` (host env only) · console creds (operator) | dump cap 30 min; 1 retry → skip + alarm | api serves the 503 problem envelope (01); backup failure alarm; RPO ≤ 24 h (PITR on paid) |
| Cloudflare R2 | Media buckets + versioned backups bucket + off-site copy target | S3 API (TLS) | `R2_*` (apps, env-only) · `R2_BACKUP_*` (ops, 15-held) | 60 s/op; 3× backoff; off-site copy independent | media/receipts degraded (05/08/12); backups fail + alarm |
| Expo EAS | App builds, submission, OTA updates | HTTPS CLI in CI | `EXPO_TOKEN` (CI secret) | async queue; re-run | releases delayed; documented local `eas build` fallback (never the VPS) |
| External uptime checker | Off-box availability alerting | HTTPS GET `/healthz` + `/readyz` | none (public endpoints) | continuous; alert ≤ 5 min | alerting lost only; provider + secondary check `TODO: Confirm` (§14 #1) |
| Let's Encrypt | TLS certificates | ACME via HestiaCP | panel-managed | auto-retry + manual runbook | old cert serves until expiry |
| bKash/Nagad/SSLCommerz prod | Payments cutover (code owned by 12) | 15 wires env + webhook URLs only | gateway dashboards (operator-held) | n/a | payments disabled until cutover signed (OPS-BE-013) |

---

## 8. Configuration

### 8.1 Environment variables

Full env inventory — `.env.example` per deployable mirrors 01 config-module keys exactly
(parity CI-enforced, OPS-UT-002); real `.env` only on the host, chmod 600 root-owned.

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `DATABASE_URL` | yes (api) | Neon connection string (`ap-southeast-1`) | api → Neon |
| `REDIS_URL` | yes (api) | `redis://127.0.0.1:6379/0` (Compose loopback) | api → redis |
| `JWT_SECRET` | yes (api) | random 32+ bytes | 03 auth |
| `DEEPSEEK_API_KEY` | Part B (api) | DeepSeek dashboard key | 08 AI |
| `FCM_SERVER_KEY` | Part B (api) | prod service account (06 seam; FCM for topics + directed — no Expo push token) | 06 push |
| `R2_*` (account/bucket/keys) | Part B (api) | R2 dashboard values | 05/08/12 media + receipts |
| `R2_BACKUP_*` | ops-only | ops-scoped R2 creds | `ops/backup.sh` |
| `BKASH_*` / `NAGAD_*` / `SSLCOMMERZ_*` | Part B (api) | prod keys + webhook URLs (12 cutover) | 12 payments |
| `GOOGLE_*` / `GITHUB_*` | yes (api) | OAuth client creds | 03 SSO |
| `SMS_GATEWAY_*` | yes (api) | local SMS gateway creds | 03 OTP |
| `NEXT_PUBLIC_API_URL` / `NEXT_PUBLIC_SITE_URL` | yes (web) | `/api` (same-origin — browser calls go through the web host) / `https://kusholconnect.com` | web build |
| `API_INTERNAL_URL` | yes (web, server-only) | `http://api:8080` (Compose network) | Next.js server-side calls to the api (forwards the session cookie) |
| `NEXT_PUBLIC_MAINTENANCE_MODE` | build-time (web) | `true` ships the banner | OpsBanner (§6.1) |
| `EXPO_PUBLIC_API_URL` | per EAS profile | LAN host / pilot / prod API URL | app builds (§6.2) |
| `EXPO_TOKEN` · GHCR pull token | CI/host | CI secret / host `.env` | EAS + image pulls |
| `APP_ENV` / `LOG_LEVEL` / `HTTP_PORT` | yes | `production` for both pilot and prod hosts (01 allows `development`·`test`·`production`; pilot vs prod differ by domain/keys, not mode) / `info` / `8080` | 01 config modules |
| `OTP_PEPPER` | yes (api) | random 32+ bytes | 03 OTP HMAC |
| `AI_PROVIDER` / `AI_INTERNAL_TOKEN` | Part B (api) | `deepseek` / random token for the later FastAPI service | 08 `AIService` |
| `ERP_SECRET_KEY` | when 14 ships (api) | 32-byte base64 key | 14 webhook-secret encryption |
| `NEXT_PUBLIC_DOWNLOAD_URLS_READY` | build-time (web) | `false` until APK/TestFlight links exist | 07 landing/download |

### 8.2 Runtime config — the two lists

| Owner can change (host `.env` + runbook step — no admin UI in pilot) | Fixed in code |
| --- | --- |
| Deployed image tags per env (release log) | **Memory caps (api 512m · worker 256m · web 512m · redis 256m)** + restart policies |
| `APP_ENV`, `LOG_LEVEL`, feature env values from module `.env.example`s | Healthcheck paths/intervals; `/readyz` gate timeout (120 s) |
| Maintenance flag (Nginx file + build input) | `127.0.0.1`-only port bindings; GHCR tag scheme `main-<sha7>` |
| Backup schedule (cron) + retention counts; uptime checker contacts | Backup artifact naming + checksum format; prune policy |
| Ops alert routing (email/Telegram) | `ops.*` string keys (bn/en copy editable in `packages/shared` only) |

Environment matrix: dev (local — `go run`/`next dev` or a local Compose, Neon dev branch,
`development` channel) · server (Compose project `kushol` on the KVM 2, `kusholconnect.com` +
`api.kusholconnect.com`): runs as **pilot** first (Neon plan per plan F6, `preview` APK, uptime
checker on) and is **promoted to prod** after pilot sign-off (Neon paid, R2 versioning,
`production` AAB/APK + TestFlight, weekly ops review). Only one server stack runs on the shared
8 GB host; pre-release checks use Neon branches + local Compose (BR-004).

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | No product auth surface; entry points are SSH + Nginx + GHCR + cloud consoles. **No image builds on the VPS** — CI-only, host scripts lint-checked (BR-001/INV-001); supply chain: base images pinned by digest, gitleaks every merge |
| Role matrix | Operator (Rahul): deploys, rollbacks, backups, drills, secrets, runbooks, pager · Developer: merges to `main`, consumes GHCR images + scripts + `.env.example` · CI: builds/pushes images, runs the secret scan · System actors: HestiaCP/Nginx, Docker, uptime checker, EAS, cron |
| Tenant scope | N/A — no DB tables owned. Backups carry tenant data: private-bucket objects over TLS, **never presigned**; access operator-only |
| Rate limits | `default` class on the consumed health endpoints (01); fail2ban + HestiaCP firewall on SSH/80/443 |
| Audit events | Release log (`<timestamp> <env> <tag> <result>` per deploy/rollback), backup log, cutover log, incident log (timeline, detection source, impact, actions, follow-ups) |
| Secrets hygiene | **No secrets in git, CI logs or images** (BR-002): gitleaks + CI masking verified (OPS-IT-003); real env only in host `.env` **chmod 600 root-owned**, wired via Compose `env_file`, parsed solely by 01 config modules; secret-rotation runbook with per-credential order (`JWT_SECRET`, `DATABASE_URL`, `R2_*`, `FCM_SERVER_KEY`, gateway keys, `EXPO_TOKEN`), < 5 min impact or scheduled window; containers non-root, read-only capability set, loopback-only bindings (INV-005) |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| 503 `application/problem+json` | Dependency down (Neon/Redis), via the 01 contract | api through the Nginx front door; bn/en problem copy; maintenance page/banner optionally flagged | Users see the static bn/en page; operator follows the incident runbook (RPO ≤ 24 h) |
| Gate failure (non-zero exit) | `/readyz` red or timeout within 120 s, or smoke red | `ops/deploy.sh` after `compose up -d` (BR-003); `ops.deploy.readyzTimeout` operator key | Automatic rollback to the previous logged tag; incident-log entry |
| Schema behind (non-zero exit) | DB version < image's expected migration version | `ops/deploy.sh` before any container change | Nothing changed; owner runs the named SQL files (Gate 2), then re-runs deploy |
| `ops.backup.checksumMismatch` | Artifact `.sha256` mismatch | `ops/restore.sh` pre-verify | Abort non-zero + alarm — a silent partial restore is impossible |
| `ops.config.envIncomplete` | `.env` missing/empty keys vs `.env.example` | Deploy pre-flight (OPS-UT-002) | Operator fills env; deploy refuses |
| Tag-scheme refusal | Tag outside `^(main\|release)-[0-9a-f]{7,40}$`, or rollback target never deployed | Deploy/rollback scripts (BR-005/INV-006) | Operator picks a logged release tag |

All api errors stay RFC-7807 via 01 (15 never wraps them). Operator-facing message keys
(`ops.*`) ship bn + en; runbooks themselves are English-only by the binding language split.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | Prod containers log **single-line JSON keyed by `X-Request-Id`** (slog, redaction ships in 01 — 15 owns retention + verification); Docker `json-file` rotation **10 MB × 5 (~30 days)**, no external shipping during pilot; weekly redaction probe over sampled logs — failure files an incident entry |
| Metrics / counters | Uptime availability %, backup log (last success/age/size), release log, weekly `docker stats` memory review, `jobs` queue depth + DEAD counts via 01's readyz detail/metrics (FND-BE-013) — operator-side only, feeds no product dashboard |
| Health contribution | `/healthz` = uptime + in-container healthcheck target; `/readyz` = deploy gate — different jobs, one 01 contract; 15 owns the polling/usage, never the endpoints |
| Jobs & retries | Nightly backup (rerun-safe timestamped artifacts), quarterly drill, weekly probe, LE renewal, uptime checks (§5.2); deploy lock prevents interleaved compose/migrate operations |
| Runbook pointers | **deploy · rollback · backup · restore · secret-rotation runbooks + incident-log template + `DEPLOYMENT.md`** (topology, environments, app distribution, pilot checklist per school, scaling trigger) — English, in-repo, updated in the same commit as behaviour; walkthrough recorded by someone who didn't write it; drill evidence filed in `07-progress.md` |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Backup script (artifact naming, checksum, exit codes, dry-run, prune selection); `.env.example` parity with 01 config modules; tag-scheme validator | `OPS-UT-001`–`003` | CI required check |
| Integration | **Deploy dry-run** on a fresh Compose stack (pull → migrate → healthy → `/readyz` 200 → smoke green); **restore drill** (checksum match → scratch restore → row-count sanity → api green); secret hygiene (gitleaks clean, CI logs unmasked-free, `.env` perms 600) | `OPS-IT-001`–`003` | CI + host check; drill evidence filed |
| E2E | **Post-deploy smoke** through the real front door: `/healthz` 200 + landing 200 + login round-trip (Playwright); APK smoke = Maestro on the built preview APK (OPS-AP-005) | `OPS-E2E-001` | **The deploy is "done" only when this passes**; Lighthouse CI CWV budget on prod landing |
| CI | Always include: the gate never trusts a green `/readyz` without the smoke; restore never runs against prod implicitly (explicit target); scripts non-interactive (cron-safe) | — | GitHub Actions required checks + gitleaks |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Deploys on merge to `main`; backups nightly; uptime polls 60 s / 5 min; pilot scale 2–3 schools |
| Hot paths + indexes | Image sizes: api < 40 MB (distroless/alpine), web < 250 MB (Next standalone) — small pulls keep deploys fast on the shared line |
| Latency targets | Deploy ≤ 5 min wall-clock (pull + migrate + gate + smoke); rollback ≤ 5 min operator time (drill-timed); gate polls `/readyz` every 2 s up to 120 s; smoke ≤ 30 s; **Neon cold start (~hundreds of ms) tolerated by design — no false red** |
| Bundle / payload impact | **Shared-host memory caps:** Kushol ≈ 1.5 GB of the 8 GB host (+ HestiaCP mail stack on the host — ClamAV ≈ 1 GB if enabled) (api 512m · worker 256m · web 512m · redis 256m; HestiaCP + 2 co-tenants ≈ 5 GB); Nginx gzip/brotli + immutable static caching; CWV budgets via Lighthouse CI |
| Caching | Static assets cache-immutable at Nginx; maintenance page `no-store` (instant recovery); app-level caching owned by 07; backups at 02:30 off-peak, alarm if dump > 30 min |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the table to review in module readiness checks.
Unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | External uptime checker provider (and secondary check) | Alerting gap if chosen poorly | Rahul | Open — `TODO: Confirm` | UptimeRobot-class free checker: `/healthz` 60 s, `/readyz` 5 min, email + Telegram alerts |
| 2 | Off-site copy target for DB dumps beyond R2 | DR depth (R2 versioning alone is not off-site) | Rahul | Open — `TODO: Confirm` before Part B | `rclone` sync to a second provider |
| 3 | Log retention on the VPS | Disk growth vs forensics window | Rahul | Open | Docker `json-file` rotation 10 MB × 5 (~30 days); no external shipping during pilot |
| 4 | Scaling trigger off Neon free tier / **single-VPS SPOF** | Refusals/pauses at pilot growth; full outage until reprovision | Rahul | Open / accepted-for-pilot | Upgrade Neon (Launch ~$19/mo) or move Postgres into Compose at real pilot traffic; VPS revisit at sustained CPU > 70%, > 10 schools, or a pilot SLA breach — recorded in `DEPLOYMENT.md`; DR = fresh box + restore scripts, RPO ≤ 24 h |
| 5 | Memory-cap sizing on the shared KVM 2 (8 GB) | OOM kills / co-tenant starvation | Rahul | Open | api 512m · worker 256m · web 512m · redis 256m; adjust after the first monitoring week |
| 6 | Shared-host contention; ap-southeast-1 latency to Bangladesh users; EAS quota limits; HestiaCP upgrades clobbering Nginx templates; drills/docs drifting from reality | Latency spikes, late app releases, broken proxy/TLS, DR failure when needed | Rahul | Risk | Hard `mem_limit`s + weekly `docker stats` review; measure p95 from prod (Neon region change is config-level); documented local `eas build` fallback; templates versioned + post-upgrade diff/re-apply; quarterly drill + same-commit docs discipline |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| `brd.md` §8 build phases (Part A = Phase 1 walking skeleton; Part B = production hardening after 14) + module rules OPS-BR-001–008 | §4 (platform ops / distribution `prd.md` §4B) | `OPS-US-001`–`012` | `OPS-BE-001`–`015` · `OPS-FE-001`–`005` · `OPS-AP-001`–`006` · `OPS-INT-001`–`006` | `OPS-UT-001`–`003` · `OPS-IT-001`–`003` · `OPS-E2E-001` (+ `OPS-AP-005` APK smoke) |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Aligned with `docs/infra/architecture-and-deployment.md`: deploy never migrates (read-only `migrate-status` check; owner runs SQL — Gate 2); gate/smoke failure auto-rolls back (old containers are replaced by `compose up -d`); `worker` container; caps api 512m / worker 256m / web 512m / redis 256m; ports 8180/3100 (configurable); one server stack promoted pilot → prod; host-prep runbook `OPS-BE-016`; HestiaCP mail backups | Claude |
| 2026-09-30 | Domain set: `kusholconnect.com` (web, apex; `www` 301 → apex) + `api.kusholconnect.com` (mobile API + WebSocket); web host also proxies `/api/*` → api so the web session cookie stays same-origin. Hostinger Docker Manager does not support the HestiaCP OS image — deploy with Docker Engine + Compose over SSH | Claude |
| 2026-09-30 | Env inventory aligned: `APP_ENV` values match 01 (`production` on pilot + prod); added `OTP_PEPPER`, `AI_PROVIDER`, `AI_INTERNAL_TOKEN`, `ERP_SECRET_KEY`, `NEXT_PUBLIC_DOWNLOAD_URLS_READY`, `HTTP_PORT` | Claude |
