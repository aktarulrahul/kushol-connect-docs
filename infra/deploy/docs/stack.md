# Stack, server layout, configuration and security

**Module:** `15-deployment-operations` (OPS-BE-003, -004, -016) · **Last updated:** 2026-10-02 ·
Runbook: [`../DEPLOYMENT.md`](../DEPLOYMENT.md)

## 1. The Compose stack — [`compose.yaml`](../compose.yaml)

Project name `kushol`, one stack on the shared KVM 2 (OPS-BR-004). Postgres (Neon) and media (R2)
are off-box, so the stack is exactly four services:

| Service | Image | Command | Host port → container | Memory | Restart | Healthcheck |
| --- | --- | --- | --- | --- | --- | --- |
| `api` | `${API_IMAGE}:${API_TAG}` | `serve` | `127.0.0.1:${API_PORT}` (8180) → 8080 | 512m, `GOMEMLIMIT=400MiB` | unless-stopped | `api healthcheck` (→ `/healthz`) every 15 s, 3 retries, 20 s start period |
| `worker` | same image | `worker` | none | 256m, `GOMEMLIMIT=200MiB` | unless-stopped | disabled — no HTTP, no shell (08-gaps G-2) |
| `web` | `${WEB_IMAGE}:${WEB_TAG}` | image default `node server.js` | `127.0.0.1:${WEB_PORT}` (3100) → 3000 | 512m | unless-stopped | `node -e fetch('http://127.0.0.1:3000/')` every 15 s, 3 retries, 30 s start period |
| `redis` | `redis:7.4.11-alpine3.21@sha256:…` | `--maxmemory 200mb --maxmemory-policy volatile-lru --save "" --appendonly no` | none (internal only) | 256m | unless-stopped | `redis-cli ping` every 10 s |

Total ≈ 1.5 GB for Kushol on an 8 GB box shared with HestiaCP (incl. the mail stack) and two other
apps. Adjust caps only after measuring (`docker stats --no-stream`, `free -m`).

**Wiring fixed in the Compose file** (not in env files): `HTTP_PORT=8080`,
`REDIS_URL=redis://redis:6379/0`, `TRUSTED_PROXIES=${KUSHOL_SUBNET},127.0.0.1/32,::1/128` for the
api/worker; `NODE_ENV=production`, `PORT=3000`, `HOSTNAME=0.0.0.0` for web.

**Ordering.** `api` and `worker` wait for `redis` to be healthy. `web` has no dependency — it
renders without the api and the browser talks to the api through Nginx.

**Network.** One bridge network `kushol` (`kushol_kushol` in `docker network ls`) with the fixed subnet
`${KUSHOL_SUBNET}` (10.201.0.0/24) — outside Docker's default 172.17–31.x / 192.168.x pools, so it
cannot collide with the co-tenant apps' networks (`prepare-host.sh` checks). Containers reach each
other by service name (`redis`, `api`).

**Why the api trusts the subnet.** Nginx connects to `127.0.0.1:8180`; Docker's port proxy forwards
that from the network's gateway address (10.201.0.1), so the api's TCP peer is the gateway, not
127.0.0.1. `TRUSTED_PROXIES` therefore names the subnet, and the api reads the client IP from Nginx's
`X-Forwarded-For` (which the templates overwrite, never append — architecture F9/F19).

**Ports.** Every published port binds `127.0.0.1` only: Docker-published ports bypass HestiaCP's
iptables firewall, so binding to all interfaces would expose the containers to the internet
(architecture F5). Only Nginx (ports 80/443) faces the internet.

**Hardening.**

| Measure | api | worker | web | redis |
| --- | --- | --- | --- | --- |
| Non-root user | 65532 (distroless `nonroot`) | 65532 | `node` | 999:1000 (image's `redis` user) |
| Read-only root filesystem | ✅ + tmpfs `/tmp` 16 MB | ✅ + tmpfs `/tmp` 16 MB | — (Next.js writes `.next/cache`) | ✅ + tmpfs `/data` 16 MB |
| `cap_drop: [ALL]` | ✅ | ✅ | ✅ | ✅ |
| `no-new-privileges` | ✅ | ✅ | ✅ | ✅ |
| init process | — (Go handles signals) | — | `init: true` | — |
| Graceful stop | 30 s (`SHUTDOWN_TIMEOUT` 20 s inside) | 30 s | default 10 s | default |

**Logs.** Every service logs JSON to stdout; Docker's `json-file` driver rotates at 10 MB × 5 files
per container (set per service, so Docker's global `daemon.json` — shared with the co-tenants — is
never touched). Read them with `ops/compose.sh logs …`.

**After a reboot** Docker starts the containers again (`restart: unless-stopped`), and they report
healthy within about a minute. A container someone stopped by hand stays stopped — redeploy the
current release with `ops/deploy.sh pilot` (no tags = keep the current ones).

## 2. Server layout

```text
/opt/kushol/                     owner kushol:kushol (prepare-host.sh)
├── compose.yaml                 the stack
├── DEPLOYMENT.md  docs/         these documents
├── env/                         0700
│   ├── stack.env                0600  stack settings (§3.1)
│   ├── api.env                  0600  api + worker secrets and settings (§3.2)
│   ├── web.env                  0600  web settings (§3.3)
│   └── *.env.example                  templates synced from the repo (deploy.sh checks against them)
├── ops/                         deploy.sh · rollback.sh · smoke.sh · migrate.sh · compose.sh · lib.sh
├── host/                        prepare-host.sh (root)
├── hestia/                      setup-web.sh · setup-mail.sh · lib.sh · templates/ (root)
└── state/                       written by the scripts, never synced from the repo
    ├── release.env              the tags now deployed: API_TAG=… WEB_TAG=…
    ├── release.candidate.env    only while a deploy runs
    ├── releases.log             one line per deploy/rollback result (§2.1)
    ├── incidents.log            one line per failed gate / rollback
    ├── deploy.lock              flock target — one deploy at a time
    └── host-check-<UTC>.txt     host reports from prepare-host.sh
```

Elsewhere on the server:

| Path | What | Written by |
| --- | --- | --- |
| `/usr/local/hestia/data/templates/web/nginx/kushol-{web,api}.{tpl,stpl}` (or `…/nginx/php-fpm/` on an nginx-only HestiaCP) | the Kushol Nginx templates, rendered with the ports | `hestia/setup-web.sh` |
| `/home/kusholconnect/conf/web/<domain>/` | the vhost configs HestiaCP generates from those templates (do not edit by hand — rerun the script) | HestiaCP |
| `/home/kusholconnect/mail/kusholconnect.com/` | the mailboxes | HestiaCP |
| `/var/log/apache2/domains/<domain>.log` / `.error.log` (proxy mode) or `/var/log/nginx/domains/…` (nginx-only) | Nginx access and error logs per domain | Nginx |
| `/root/kushol-credentials-<UTC>.txt` | new passwords from the HestiaCP scripts (root-only; shred after moving them to the password manager) | `hestia/*.sh` |
| `/home/kushol/.docker/config.json` | the Docker Hub login (read-only access token) | `docker login` |
| `/home/kushol/.ssh/authorized_keys` | who may deploy | `prepare-host.sh --ssh-key-file` |
| `/swapfile`, `/etc/sysctl.d/90-kushol-swap.conf` | 2 GB swap, `vm.swappiness=10` (only if the host had no swap) | `prepare-host.sh` |
| `/etc/apt/sources.list.d/docker.sources`, `/etc/apt/keyrings/docker.asc` | Docker's apt repository (only if Docker was missing) | `prepare-host.sh` |

### 2.1 `releases.log` format

```text
<UTC timestamp> <env> api=<tag> web=<tag> <RESULT> [note]
2026-10-05T09:12:44Z pilot api=main-1a2b3c4 web=main-9f8e7d6 SERVING
2026-10-06T10:01:02Z pilot api=main-5d6e7f8 web=main-9f8e7d6 FAILED
2026-10-06T10:02:40Z pilot api=main-1a2b3c4 web=main-9f8e7d6 SERVING auto-rollback
```

| Result | Written when |
| --- | --- |
| `SERVING` | a deploy (note empty), automatic rollback (`auto-rollback`) or operator rollback (`rollback`) passed the gate |
| `FAILED` | a deploy failed the gate or smoke |
| `ROLLED_BACK` | an operator ran `rollback.sh` away from this release (note `operator`) |
| `ROLLBACK_FAILED` | the automatic rollback also failed its gate |

The rollback target is the newest release whose **latest** line is `SERVING` and which is not the one
running now — `FAILED` and `ROLLED_BACK` releases are never targets, so repeated rollbacks walk
backwards. Never edit the log by hand; it is the rollback source of truth (OPS-BR-005).

## 3. Configuration reference

Three env files on the server, each with a committed template in [`../env/`](../env/). Values never
contain inline comments or quotes. `ops/deploy.sh` refuses to run while a file is missing, is not
chmod 600, or leaves a **required** key (uncommented in the template) empty or still containing
`REPLACE`.

### 3.1 `env/stack.env` — stack settings (no secrets)

Read by Compose for `${…}` interpolation and sourced by the scripts.

| Key | Default | Used by |
| --- | --- | --- |
| `KUSHOL_ENV` | `pilot` | the `<env>` argument of deploy/rollback must equal it; recorded in the logs |
| `API_IMAGE` / `WEB_IMAGE` | `docker.io/airahul/ai` (both) | Compose image names — one private repository |
| `API_TAG_PREFIX` / `WEB_TAG_PREFIX` | `api-` / `web-` | prefixed to the deployed tag, so `api=main-e71c776` pulls `airahul/ai:api-main-e71c776` |
| `API_PORT` / `WEB_PORT` | `8180` / `3100` | loopback ports (Compose) and the Nginx templates (`setup-web.sh`) — change both together: edit, rerun `setup-web.sh`, redeploy |
| `KUSHOL_SUBNET` | `10.201.0.0/24` | Compose network + `TRUSTED_PROXIES` |
| `SITE_DOMAIN` / `API_DOMAIN` | `kusholconnect.com` / `api.kusholconnect.com` | HestiaCP domains, smoke checks |
| `PUBLIC_IP` / `PUBLIC_IP6` | `72.61.114.20` / `2a02:4780:5e:99d7::1` | DNS readiness checks; SPF value printed by `setup-mail.sh` |
| `HESTIA_USER` | `kusholconnect` | the HestiaCP user owning the web and mail domains |
| `SMOKE_MODE` | `local` | `local` until DNS + certificates exist, then `public` (DEPLOYMENT.md §4) |

### 3.2 `env/api.env` — api and worker

Parsed only by the api's `internal/config` (FND-BR-002). `deploy/tests/run.sh` fails CI if a key the
config reads is missing from the template or the template has a key the config does not read
(OPS-UT-002).

| Key | Required | Module | Notes |
| --- | --- | --- | --- |
| `APP_ENV` | ✅ | 01 | `production` (also hides the Swagger docs) |
| `LOG_LEVEL` | ✅ | 01 | `info` |
| `DATABASE_URL` | ✅ | 01 | Neon `production` branch, **direct (unpooled)** URL with `sslmode=require` — golang-migrate's advisory lock does not work through the pooler |
| `JWT_SECRET` | ✅ | 03 | ≥ 32 bytes, `openssl rand -base64 48`. Required by the deploy check now so 03 can ship without an env change; the 01 binary ignores it |
| `OTP_PEPPER` | ✅ | 03 | ≥ 16 bytes, same generator |
| `SHUTDOWN_TIMEOUT`, `WORKER_CONCURRENCY` | — | 01 | defaults `20s`, `2` |
| `AUTH_ACCESS_TTL`, `AUTH_REFRESH_TTL`, `AUTH_SESSION_TTL`, `VERIFICATION_SLA_HOURS`, `OTP_RESEND_COOLDOWN`, `OTP_HOURLY_CAP_PER_TARGET`, `OTP_HOURLY_CAP_PER_IP`, `OTP_MAX_ATTEMPTS` | — | 03 | defaults in the template |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` | — | 03/06 | `mail.kusholconnect.com`, `587`, `noreply@kusholconnect.com`, password from the credentials file |
| `SMS_GATEWAY_URL`, `SMS_GATEWAY_API_KEY`, `SMS_GATEWAY_SENDER` | — | 03 | vendor `TODO: Confirm` |
| `GOOGLE_CLIENT_ID/SECRET`, `GITHUB_CLIENT_ID/SECRET` | — | 03 | SSO per provider |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_KEY`, `R2_BUCKET` | — | 05 | media; unset = media endpoints 501 |
| `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON` | — | 06 | push; the JSON on one line |
| `BOOTSTRAP_SUPER_ADMIN_EMAIL/PASSWORD/PHONE` | — | 03 | one-off `api bootstrap-super-admin`; remove after use |
| `HTTP_PORT`, `REDIS_URL`, `TRUSTED_PROXIES` | — | 01 | **set by `compose.yaml`** — do not set here |

A key a running binary does not know is ignored, so the file can carry later modules' settings
ahead of their release.

### 3.3 `env/web.env` — web

| Key | Value | Notes |
| --- | --- | --- |
| `NEXT_PUBLIC_API_URL` | `https://kusholconnect.com` | must equal the image's build arg ([`images.md`](images.md) §3.2) |
| `NEXT_PUBLIC_SITE_URL` | `https://kusholconnect.com` | same |

## 4. Security model

### 4.1 Accounts

| Account | Where | Used for | Access |
| --- | --- | --- | --- |
| `root` | VPS | `prepare-host.sh`, `hestia/*.sh`, HestiaCP CLI | owner only |
| `kushol` | VPS (Linux) | deploys, rollbacks, logs | SSH key only (password locked); member of `docker` — **root-equivalent**, so only operators' keys go in its `authorized_keys` |
| `kusholconnect` | HestiaCP panel user (also a Linux user HestiaCP manages) | owns the web and mail domains | panel login; password in the credentials file |
| HestiaCP administrator (usually `admin`) | HestiaCP | panel administration, "login as" any panel user | owner |
| GitHub `aktarulrahul` | GitHub | repos, Actions | owner |
| Docker Hub `airahul` | Docker Hub | private image repository `airahul/ai` | owner |

### 4.2 Secrets — where each one lives

| Secret | Lives in | Never in | Rotation |
| --- | --- | --- | --- |
| CI push credential | the run's ephemeral `GITHUB_TOKEN` (`packages: write`, image job only) | — | automatic per run |
| Docker Hub pull token (personal access token, Read-only) | `/home/kushol/.docker/config.json` + password manager | repo, env files, CI | on expiry or rotation: new token, `sudo -iu kushol docker login docker.io` again |
| `DATABASE_URL` (Neon password) | `env/api.env` + password manager | repo, images, CI logs | Neon console → reset password → update `api.env` → `ops/deploy.sh pilot` |
| `JWT_SECRET`, `OTP_PEPPER` | `env/api.env` + password manager | anywhere else | `JWT_SECRET` change invalidates issued tokens (users sign in again); `OTP_PEPPER` change invalidates codes in flight (5-minute TTL) — do it in a quiet window, then redeploy |
| `SMTP_PASSWORD` (noreply@) | `env/api.env` + password manager | — | change in HestiaCP → update `api.env` → redeploy |
| Mailbox and panel passwords | password manager (via the root-only credentials file, then shredded) | terminal output, command lines, logs | HestiaCP panel |
| Neon console, Hostinger, GitHub logins | owner's password manager | the server | provider |

### 4.3 Controls

- No secret in git (`.gitignore` for `deploy/env/*.env` and `deploy/state/`; gitleaks in CI on both
  repos), in an image (`.dockerignore`; nothing secret is a build arg) or in a `NEXT_PUBLIC_*` value.
- Env files `0600` in a `0700` directory, owned by `kushol` (the Compose CLI reads `env_file` as the
  invoking user — 07-progress ADR-3).
- Containers: non-root, loopback-only ports, read-only filesystems where possible, all capabilities
  dropped, `no-new-privileges` (§1).
- HestiaCP scripts pass passwords as `/tmp` file paths (HestiaCP reads the first line), so they never
  appear in `ps` output or HestiaCP's action log; the scripts refuse to run on a HestiaCP without that
  feature.
- TLS: Let's Encrypt via HestiaCP (auto-renewed), HTTPS forced, HSTS on, TLS 1.3 early data refused
  (`425`) so requests cannot be replayed into the apps.
- Images pinned by digest; the server only pulls tags that passed CI.
