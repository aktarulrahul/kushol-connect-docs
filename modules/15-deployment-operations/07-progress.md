# Deployment & Operations — Build Progress

**Module:** `15-deployment-operations` (Part A ✅ + Part B ✅ code-complete) · **Repos:** `applications/api`
(`Dockerfile`, `deploy/`, CI image job), `applications/web` (`Dockerfile`, CI image job), both in the
working tree of branch `module/03-identity-access`, nothing committed by the build ·
**Last updated:** 2026-10-08

Owner instruction (2026-10-02): "make deployment plan and script to deploy the web and api in
hostinger in KVM 2 • srv1100749.hstgr.cloud within docker container for kusholconnect.com domain and
also created the 4 emails within the HestiaCP". Taken as the go-ahead for Part A ahead of 02's
Gate 1. Standing rules apply: the agent has no SSH, never runs the stack or Docker, and never
creates accounts or sets passwords — every server step is a script the owner runs
(`docs/infra/deploy/DEPLOYMENT.md` §2 is the ordered plan — moved from the api repo on 2026-10-08, ADR-14).

## Stages & gates

| Stage / gate | Status | Date | Notes |
| --- | --- | --- | --- |
| 1 · Read & plan | ✅ | 2026-10-02 | Plan = `DEPLOYMENT.md` §2; facts re-verified (below) |
| 2 · Build (infra-as-code) | ✅ agent side | 2026-10-02 | Images, Compose, ops scripts, HestiaCP web + mail scripts, CI jobs, runbook |
| Gate 1 · UI | N/A | — | No screens (maintenance page deferred — G-6) |
| Gate 2 · SQL | N/A for 15 | — | 15 owns no migrations; the first deploy needs **01's** migrations on Neon (owner, `DEPLOYMENT.md` §3.7) |
| 5 · Integration | ⏳ **pending owner run** | — | Server steps §3–§5 of `DEPLOYMENT.md`; host report → this file |
| Gate 3 · integrated flows | ⏳ after the first deploy | — | `SMOKE_OK public` + mail headers `spf/dkim/dmarc=pass` |
| 6 · Gaps & verification | ✅ `08-gaps.md` | 2026-10-02 | |

## Facts verified 2026-10-02 (Hostinger API + `dig`)

| Item | Fact |
| --- | --- |
| VPS location | Data centre 21 = **Kuala Lumpur, Malaysia** → ~5–10 ms to Neon `aws-ap-southeast-1` (Singapore). Closes architecture finding F1 |
| VPS | `srv1100749.hstgr.cloud`, KVM 2, 2 vCPU / 8 GB / 100 GB, running, image "Ubuntu 24.04 with HestiaCP"; no hPanel firewall group attached |
| Reverse DNS | `72.61.114.20` and `2a02:4780:5e:99d7::1` → `srv1100749.hstgr.cloud`, which resolves back to both (FCrDNS passes on IPv4 and IPv6) |
| DNS | Nameservers `horizon/orbit.dns-parking.com` **are Hostinger DNS**; the zone is editable through hPanel/API. Today: `@ A 2.57.91.91` (parking), `www CNAME kusholconnect.com`; no `api`, `mail`, MX, SPF |
| Domain | Active, locked, privacy on, expires 2029-09-29 |

## Build decisions (ADRs)

| # | Decision | Why / effect |
| --- | --- | --- |
| ADR-1 | ~~Deploy files live in the api repo `deploy/`~~ — **superseded by ADR-14** | — |
| ADR-2 | **A release = two tags** (`api=main-<sha7>`, `web=main-<sha7>`) | The repos build separately; `deploy.sh pilot api=… web=…` keeps the omitted one; `releases.log` records both. Spec's single `<tag>` arg is superseded |
| ADR-3 | Env files `kushol:kushol 0600` in a `0700` dir (spec said root-owned) | The Compose CLI reads `env_file` as the invoking user; docker-group membership is root-equivalent anyway |
| ADR-4 | Ports `127.0.0.1:8180` (api) / `:3100` (web); subnet `10.201.0.0/24`; `TRUSTED_PROXIES` = that subnet | Outside Docker's default pools so co-tenant networks cannot collide (prepare-host checks overlap and port use) |
| ADR-5 | Log rotation per service in `compose.yaml` (10 MB × 5), not `daemon.json` | Changing the daemon config means restarting Docker under the co-tenant apps |
| ADR-6 | **PTR unchanged**; SPF `mx ip4 ip6 -all`; no AAAA for web names | FCrDNS already passes; one PTR is shared by three apps; SPF + DKIM carry the domain identity. Exim sends over IPv6 too; HestiaCP vhosts listen on IPv4 only |
| ADR-7 | Mail = **4 mailboxes** `aktarul.islam`, `jafrin.myoria`, `atiqul.islam`, `noreply` + aliases `hello`, `dmarc`, `postmaster`, `abuse` → `aktarul.islam` | Reading of "the 4 emails" against architecture §7.1 — `TODO: Confirm` (G-9). No autoreply on `noreply@` (backscatter to spam senders hurts the shared IP) |
| ADR-8 | Passwords never on a command line or terminal | HestiaCP reads a password from a `/tmp` file path (checked in `func/main.sh`; scripts refuse otherwise); values go only to a root-only `/root/kushol-credentials-*.txt` |
| ADR-9 | HestiaCP mode detected: proxy templates (`nginx` in front of apache) or web templates (nginx-only) | One template source with `@HTTP_PORT@`/`@HTTPS_PORT@` placeholders; custom names `kushol-web`/`kushol-api` survive panel upgrades |
| ADR-10 | Smoke = curl, `local` (loopback) or `public` (real front door) | No login exists on `main` yet; Playwright login round-trip with 03 (G-4) |
| ADR-11 | Container hardening | api/worker/redis `read_only` + tmpfs, all `cap_drop: ALL` + `no-new-privileges`; web writable (Next writes `.next/cache`); redis runs as its image user so the entrypoint needs no capabilities |
| ADR-12 | `ops/migrate.sh <api-tag> status \| up --confirm` | Owner-run Gate 2 helper using that image's own migrations; `deploy.sh` only checks `migrate-status` and stops (exit 3) |
| ADR-13 | Worker healthcheck disabled | No HTTP and no shell in distroless — nothing to probe; restart policy covers crashes (G-2) |
| ADR-14 | **All deploy files in the docs repo under `infra/`** (owner, 2026-10-08) — `infra/deploy/` (bundle, runbook, reference docs, tests) and `infra/docker/` (`api.Dockerfile`, `web.Dockerfile` + `<name>.dockerignore`); nothing deploy-related in the app repos | App CI keeps `gate` + gitleaks; the `image` and `deploy-bundle` jobs are gone because their files left the repos — images are built by the owner with `-f` against each app repo (`images.md` §2); the bundle tests run from the docs repo and skip env parity when the app repos are absent. The docs repo is public, so the bundle is public (templates only) |

## Pinned versions (digests checked 2026-10-02)

| Image / action | Pin |
| --- | --- |
| api build | `golang:1.26.8-alpine3.24@sha256:8ac98ca5…49a0c` |
| api runtime | `gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec…555e3` |
| web build + runtime | `node:22.23.3-alpine3.24@sha256:0a7108bf…2e402` (`.nvmrc` 22; pnpm 11.8.0 via corepack) |
| redis | `redis:7.4.11-alpine3.21@sha256:858f009f…b3499` (same major as dev/testcontainers) |
| CI | `docker/setup-buildx-action@v4`, `login-action@v4`, `build-push-action@v7`, `gitleaks/gitleaks-action@v3` |

## Delivered

| Spec ID | Artifact | Status |
| --- | --- | --- |
| OPS-BE-001 | api `Dockerfile` + `.dockerignore` (cross-compiled static binary, distroless nonroot) | ✅ written · first build in CI |
| OPS-BE-002 | web `Dockerfile` + `.dockerignore` (standalone, `node` user) + CI boot check | ✅ written · first build in CI |
| OPS-BE-003 | `deploy/compose.yaml` (api/worker/web/redis, caps, healthchecks, loopback, fixed subnet) | ✅ |
| OPS-BE-004 | `deploy/env/{stack,api,web}.env.example` (api keys = `internal/config` exactly, test-enforced) | ✅ |
| OPS-BE-005 | CI `secrets` (gitleaks) in both app repos · ~~`image` + `deploy-bundle` jobs~~ removed 2026-10-08 (ADR-14): images are built by the owner from `docs/infra/docker` | ◐ |
| OPS-BE-006 | `deploy/hestia/templates/kushol-{web,api}.{tpl,stpl}` + `setup-web.sh` | ✅ · pending owner run |
| OPS-BE-007 | `deploy/ops/deploy.sh` (+ `lib.sh`, `smoke.sh`, `compose.sh`) | ✅ |
| OPS-BE-008 | `deploy/ops/rollback.sh` | ✅ · drill timing pending owner run |
| OPS-BE-012 | Bundle tests `bash infra/deploy/tests/run.sh` / `flow.sh` from the docs repo (`make deploy-check` removed with the move) | ◐ |
| OPS-BE-016 | `deploy/host/prepare-host.sh` | ✅ · host report pending owner run |
| (owner request) | `deploy/hestia/setup-mail.sh` — mail domain, 4 mailboxes, aliases, DNS values | ✅ · pending owner run |
| OPS-US-012 (Part A slice) | `docs/infra/deploy/DEPLOYMENT.md` — plan, runbook, exit codes, DNS, mail, troubleshooting, incidents | ✅ |
| Documentation (owner: "document everything") | `deploy/docs/images.md` (build + GHCR), `stack.md` (Compose, layout, config keys, security), `scripts.md` (script reference, exit codes, tests), `hestia.md` (routing, headers, TLS, templates, mail); pointers from both READMEs and the architecture plan §5 | ✅ 2026-10-02 |

## Evidence (agent side, 2026-10-02 — no containers, no server)

| Check | Result |
| --- | --- |
| `bash deploy/tests/run.sh` (OPS-UT-002 env parity, OPS-UT-003 tags, release log, compose rules, BR-001, templates, `bash -n`) | 72 passed, 0 failed |
| `bash deploy/tests/flow.sh` (real `deploy.sh`/`rollback.sh` vs fake docker + curl: first/partial deploy, red gate → auto-rollback, schema behind/dirty, pull failure, bad input, rollback walk-back) | 33 passed, 0 failed — found and fixed smoke output leaking into deploy's stdout |
| Mutation check (0.0.0.0 port, missing `mem_limit`, extra/missing env key, bad placeholder) | 5 of 5 caught |
| web `prettier --check` on the changed workflow and README | clean |
| Not run here | `shellcheck` (not installed on the dev Mac — CI runs it), `docker build` of both images and `docker compose config` (Docker off by owner rule — CI runs them), everything on the server |

## Owner run — record results here

1. Host report from `host/prepare-host.sh` (`/opt/kushol/state/host-check-*.txt`): ⏳
2. `hestia/setup-web.sh` pass 1 output (Nginx mode detected, templates applied): ⏳
3. 01 migrations on Neon via `ops/migrate.sh` (Gate 2 of 01): ⏳
4. First deploy line (`SERVING pilot api=… web=…`) and `ops/compose.sh ps`: ⏳
5. DNS change (agent can apply via the Hostinger API after explicit approval) → pass 2 → `SMOKE_OK public`: ⏳
6. `hestia/setup-mail.sh` → DNS (incl. DKIM) → certificate → test-mail headers: ⏳
7. Rollback drill timing (`ops/rollback.sh pilot`, target < 5 min): ⏳

---

## Part B — production hardening (2026-10-04, code-complete)

| Task | Evidence |
| --- | --- |
| `OPS-BE-009` | `deploy/ops/backup.sh` (deploy-lock + disk guards, versioned pg_dump client, sha256, R2 + off-site rclone, 30-day prune) + `env/backup.env.example` + cron lines in `deploy/docs/backups.md` |
| `OPS-BE-010` | `deploy/ops/restore.sh` (checksum → scratch restore → row-count sanity) + drill procedure (`docs/backups.md` §3) — **the drill itself is owner-run** |
| `OPS-BE-011` | `deploy/docs/secret-rotation.md` (per-credential order incl. `ERP_SECRET_KEY` re-encrypt caveat) |
| `OPS-BE-013` | `deploy/docs/prod-wiring.md` cutover checklist (Neon, R2+versioned backups, FCM, gateway sandbox→prod incl. webhook URL, SMS/SMTP, `EXPO_TOKEN`) — owner-run |
| `OPS-BE-014` | compose `json-file` rotation (already in Part A) + weekly `deploy/ops/redaction-probe.sh` (FND-BR-006 live probe; failure → incidents) |
| `OPS-BE-015` | `deploy/ops/maintenance.sh` flag + Nginx 503 bn/en page in both web templates + `NEXT_PUBLIC_MAINTENANCE_MODE` build input (`web src/env.ts`, `/maintenance` page, `ops.maintenance.*` i18n) |
| Uptime (G-7 Q1) | `deploy/ops/uptime-check.sh` minute-cron + optional healthchecks.io ping/fail |
| EAS (G-7) | `applications/app/.github/workflows/eas.yml` (dispatch + nightly preview APK, production build + optional submit; `EXPO_TOKEN` secret; profiles already in `eas.json`) |
| G-12 | web `image` CI job reordered: build (load) → boot check → push — a broken image never reaches GHCR |
| Tests | `deploy/tests/run.sh` **77/77** (adds Part B helpers, ops-script syntax/existence, backup-env parity, maintenance-flag template wiring); env parity fixed (`api.env.example` + `ERP_SECRET_KEY`/`PAYMENTS_WEBHOOK_SECRET`, `web.env.example` + maintenance/download flags) |

**Owner runs still pending:** first backup execution + restore drill (BR-007), uptime monitor
account, cutover checklist execution, EAS credentials + first queue, maintenance drill.
