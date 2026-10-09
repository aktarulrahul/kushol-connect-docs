# Kushol Connect — Deployment runbook (Hostinger KVM 2)

**Module:** `15-deployment-operations` Part A · **Last updated:** 2026-10-02 · **Audience:** operator
(English, OPS-BR-008). Architecture and the reasoning behind it: `docs/infra/architecture-and-deployment.md`.

This file is the runbook — what to do, in order. The reference documents explain how each part
works:

| Document | Covers |
| --- | --- |
| [`docs/images.md`](docs/images.md) | How the api and web images are built (Dockerfiles in `docs/infra/docker`), tagged and pushed to the registry; pull token; building without CI; updating base images |
| [`docs/stack.md`](docs/stack.md) | The Compose stack (services, limits, network, hardening, logs), the server layout and state files, every configuration key, the security model (accounts, secrets, rotation) |
| [`docs/scripts.md`](docs/scripts.md) | Every script — who runs it, arguments, steps, output, exit codes — and the bundle tests |
| [`docs/hestia.md`](docs/hestia.md) | HestiaCP: domains and routing, headers, TLS, the Nginx templates; mail domain, mailboxes, DNS, client settings, deliverability |
| [`docs/backups.md`](docs/backups.md) | Part B: nightly backup, restore drill, cron entries (backup, redaction probe, uptime check) |
| [`docs/prod-wiring.md`](docs/prod-wiring.md) | Part B: production cutover checklist (Neon, R2, FCM, payment gateways) |
| [`docs/secret-rotation.md`](docs/secret-rotation.md) | Part B: rotating each secret |

Contents: 1 At a glance · 2 First deployment plan · 3 One-time setup · 4 DNS and TLS · 5 Mail ·
6 Day-2 operations · 7 Troubleshooting · 8 Incidents · 9 Not yet

## 1. At a glance

```text
Browser ─HTTPS─► HestiaCP Nginx (Let's Encrypt) ─┬─ kusholconnect.com/      → 127.0.0.1:3100 → web    (Next.js)
                                                 ├─ kusholconnect.com/api/  → 127.0.0.1:8180 → api    (Go, same origin)
Mobile ─HTTPS/WSS─►                              └─ api.kusholconnect.com   → 127.0.0.1:8180 → api    (REST + /api/v1/ws)
                                                                                    worker (same image) · redis
api/worker ─TLS─► Neon Postgres (Singapore)     api/worker ─SMTP 587─► HestiaCP Exim (noreply@)
Owner's Mac (docs/infra/docker) ─► registry ─pull─► VPS (never built on the VPS)
```

| Item | Value |
| --- | --- |
| Server | Hostinger KVM 2 `srv1100749.hstgr.cloud` · `72.61.114.20` · Kuala Lumpur (data centre 21) · Ubuntu 24.04 + HestiaCP · shared with 2 other apps |
| Stack | Compose project `kushol` in `/opt/kushol`: api 512m · worker 256m · web 512m · redis 256m |
| Images | private Docker Hub repository `airahul/ai`: `api-main-<sha7>` and `web-main-<sha7>` (`API_IMAGE`/`WEB_IMAGE` + tag prefixes in `env/stack.env`) — built from `docs/infra/docker/` by the owner ([`docs/images.md`](docs/images.md)) |
| Database | Neon `kushol-connect-db`, branch `production` (off-box; migrations are owner-run — Gate 2) |
| Mail | HestiaCP Exim/Dovecot on the same box: 4 mailboxes + aliases (§5) |
| Users | `root` (HestiaCP scripts, host prep) · `kushol` (deploys; docker group) · HestiaCP panel user `kusholconnect` (owns the domains) |

Bundle files (this folder, `docs/infra/deploy/` in the docs repo; the Dockerfiles are in `docs/infra/docker/`):

| Path | Purpose |
| --- | --- |
| `compose.yaml` | The stack (loopback ports only, memory caps, healthchecks, log rotation) |
| `env/*.env.example` | Templates for `env/stack.env`, `env/api.env`, `env/web.env` (real files only on the server, chmod 600) |
| `ops/deploy.sh` · `ops/rollback.sh` | Gated deploy and rollback (§6) |
| `ops/smoke.sh` · `ops/compose.sh` · `ops/migrate.sh` | Smoke check · `docker compose` wrapper · owner-run migrations (Gate 2) |
| `host/prepare-host.sh` | One-time host preparation (root) |
| `hestia/setup-web.sh` · `hestia/templates/` | HestiaCP web domains + Kushol Nginx templates (root) |
| `hestia/setup-mail.sh` | Mail domain, mailboxes, aliases, DNS values (root) |
| `tests/run.sh` · `tests/flow.sh` | Bundle checks and deploy/rollback flow tests — run from the docs repo: `bash infra/deploy/tests/run.sh` / `flow.sh` (not synced to the server) |
| `docs/` | Reference documents (table above) |

## 2. First deployment — the plan

Do the steps in order. **Owner** = Rahul on the server/GitHub/hPanel; **agent** = Claude in the
repo (it has no SSH and never runs the stack).

| # | Who | Step | Section |
| --- | --- | --- | --- |
| 1 | Owner | Build and push both images from the workspace (`main`, gates green) | §3.1 |
| 2 | Owner | Create a read-only Docker Hub access token for the server's `docker pull` | §3.1 |
| 3 | Owner | Copy the bundle to the server, run `host/prepare-host.sh`, share the host report | §3.2–3.3 |
| 4 | Owner | Fill `env/api.env` (Neon direct URL, secrets) and log the `kushol` user in to Docker Hub | §3.4–3.5 |
| 5 | Owner | `hestia/setup-web.sh` (pass 1: domains + templates) | §3.6 |
| 6 | Owner | Run the api migrations on Neon (Gate 2) | §3.7 |
| 7 | Owner | First deploy with `SMOKE_MODE=local` | §3.8 |
| 8 | Owner (or agent with approval) | DNS: point `@` and `api` at the server | §4 |
| 9 | Owner | `hestia/setup-web.sh` (pass 2: certificates, HTTPS, www → apex); switch to `SMOKE_MODE=public`; `ops/smoke.sh` | §4 |
| 10 | Owner | `hestia/setup-mail.sh`; add the mail DNS records; rerun for the mail certificate; test | §5 |

### Fast path (web + api, no mail)

Steps 3–7 and 9 in one interactive run, after the images are pushed (§3.1), the bundle is synced
(§3.2) and — ideally — the two DNS A records are set (§4), so certificates are issued in the same run:

```bash
ssh -t root@72.61.114.20 bash /opt/kushol/host/first-deploy.sh api=main-<api-sha7> web=main-<web-sha7>
```

It asks for the Neon production URL (hidden) and, if needed, a read-only registry login; generates
`JWT_SECRET`, `OTP_PEPPER`, `PAYMENTS_WEBHOOK_SECRET` and `ERP_SECRET_KEY` on the server; applies
pending migrations only after you type `apply` (Gate 2). Rerun it any time — finished steps are
skipped. Details: [`docs/scripts.md`](docs/scripts.md).

## 3. One-time setup

### 3.1 Images and the pull token

Full detail: [`docs/images.md`](docs/images.md).

- The app repos' CI no longer builds images (everything deploy-related is in `docs/infra` since
  2026-10-08). Build from the workspace on your Mac — never on the VPS — from a clean, committed
  `main` whose gate is green; the commands are in [`docs/images.md`](docs/images.md) §2. The tag to
  deploy is `main-<sha7>` of each repo's commit.
- The repository `airahul/ai` is **private** — keep it that way. For the server, create a Docker Hub
  **personal access token with Read-only scope** (Docker Hub → Account settings → Personal access
  tokens), never the account password. It is used in
  §3.5 and lives only in the `kushol` user's Docker config on the server.

### 3.2 Copy the bundle to the server

From the workspace on your Mac (first time as `root`; later as `kushol`):

```bash
rsync -av --delete --exclude 'env/*.env' --exclude 'state/' --exclude 'tests/' docs/infra/deploy/ root@72.61.114.20:/opt/kushol/
```

Real env files and server state are excluded, so a re-sync never overwrites them.

### 3.3 Prepare the host (root)

```bash
ssh root@72.61.114.20 'bash /opt/kushol/host/prepare-host.sh --ssh-key-file /root/.ssh/authorized_keys'
```

It records `free -m`, `df -h`, `ss -tlnp`, Docker and HestiaCP facts in
`/opt/kushol/state/host-check-*.txt` (send it to the agent for `07-progress.md`), stops if port
3100/8180 or subnet `10.201.0.0/24` is taken, installs Docker from Docker's repository only when it is
missing, adds 2 GB swap only when there is none, creates the `kushol` user and the env files. Choose
another key file than root's if not every root key holder should deploy. If it reports port 25
blocked, ask Hostinger support to open outbound SMTP before §5.

### 3.4 Fill the env files (`/opt/kushol/env/`, chmod 600)

| File | What to set |
| --- | --- |
| `stack.env` | Usually nothing. Keep `SMOKE_MODE=local` until §4 is done |
| `api.env` | `DATABASE_URL` = Neon **direct** (unpooled) connection string of branch `production`; `JWT_SECRET` and `OTP_PEPPER` = `openssl rand -base64 48` (generate on the server). Optional keys stay commented until their module ships |
| `web.env` | Nothing (must match the image's build args: `https://kusholconnect.com`) |

`ops/deploy.sh` refuses to run while a required key is empty or still says `REPLACE`, or a file is
not chmod 600.

### 3.5 Log the deploy user in to Docker Hub

```bash
ssh root@72.61.114.20
sudo -iu kushol docker login docker.io -u airahul    # paste the READ-ONLY access token at the prompt
```

### 3.6 HestiaCP web domains — pass 1 (root)

```bash
bash /opt/kushol/hestia/setup-web.sh
```

It creates the panel user `kusholconnect` (password → `/root/kushol-credentials-*.txt`), the web
domains `kusholconnect.com` (+ `www`) and `api.kusholconnect.com`, installs the `kushol-web` /
`kushol-api` Nginx templates and applies them. Certificates are skipped until DNS points here.
Nginx answers 502 until the first deploy.

### 3.7 Database migrations — Gate 2 (owner only)

The deploy never migrates; it stops when the database is behind the image. Apply the migrations the
api image embeds, from the server, with that image:

```bash
ssh kushol@72.61.114.20
/opt/kushol/ops/migrate.sh main-<api-sha7> status
/opt/kushol/ops/migrate.sh main-<api-sha7> up --confirm
```

(The same can be done from the Mac with `api migrate up --confirm` and the Neon direct URL.) Record the
result in the module's `07-progress.md`.

### 3.8 First deploy

```bash
ssh kushol@72.61.114.20
/opt/kushol/ops/deploy.sh pilot api=main-<api-sha7> web=main-<web-sha7>
```

Success prints `SERVING pilot api=… web=…`. Check: `/opt/kushol/ops/compose.sh ps` (all healthy;
the worker shows no health state — 08-gaps G-2).

## 4. DNS and TLS

DNS is Hostinger's (`*.dns-parking.com` are Hostinger's nameservers; the zone is edited in
hPanel → Domains → kusholconnect.com → DNS, or by the agent through the Hostinger API **after your
approval**). Today the zone is `@ A 2.57.91.91` (parking) and `www CNAME kusholconnect.com`.

| Type | Name | Value | Note |
| --- | --- | --- | --- |
| A | `@` | `72.61.114.20` | replaces the parking address — do this after §3.6 so the name never lands on another site |
| CNAME | `www` | `kusholconnect.com` | already present; 301 → apex once pass 2 ran |
| A | `api` | `72.61.114.20` | mobile api, WebSocket, webhooks |
| A | `mail` · `webmail` | `72.61.114.20` | §5 |
| MX | `@` | `mail.kusholconnect.com` (priority 10) | §5 |
| TXT | `@` | `v=spf1 mx ip4:72.61.114.20 ip6:2a02:4780:5e:99d7::1 -all` | §5 — one SPF record only |
| TXT | `mail._domainkey` | printed by `setup-mail.sh` | §5 |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@kusholconnect.com` | tighten to `quarantine` after 2–4 clean weeks |
| CAA (optional) | `@` | `0 issue "letsencrypt.org"` | |

No AAAA records for the web names: HestiaCP's vhosts listen on IPv4 only. The PTR stays
`srv1100749.hstgr.cloud` — it already resolves back to the server on IPv4 and IPv6, it is shared with
the co-tenant apps, and SPF + DKIM carry the `kusholconnect.com` identity.

After the records resolve (`dig +short kusholconnect.com` → `72.61.114.20`):

```bash
ssh root@72.61.114.20 'bash /opt/kushol/hestia/setup-web.sh'      # pass 2: certificates, HTTPS, HSTS, www → apex
ssh kushol@72.61.114.20 "sed -i 's/^SMOKE_MODE=.*/SMOKE_MODE=public/' /opt/kushol/env/stack.env && /opt/kushol/ops/smoke.sh"
```

`SMOKE_OK public` means: api health/readiness over TLS, landing page, http → https, www → apex,
and `/api/` reaching the api same-origin.

## 5. Mail (HestiaCP)

```bash
ssh root@72.61.114.20 'bash /opt/kushol/hestia/setup-mail.sh'
```

Creates the mail domain (DKIM 2048, anti-spam, anti-virus if ClamAV is installed, webmail) and:

| Address | Kind | Quota |
| --- | --- | --- |
| `aktarul.islam@kusholconnect.com` | mailbox | 2 GB |
| `jafrin.myoria@kusholconnect.com` | mailbox | 2 GB |
| `atiqul.islam@kusholconnect.com` | mailbox | 2 GB |
| `noreply@kusholconnect.com` | mailbox — the api's SMTP login for OTP/notification mail | 256 MB |
| `hello@`, `dmarc@`, `postmaster@`, `abuse@` | aliases → `aktarul.islam@` | — |

Override before running if needed: `MAILBOXES="name:quotaMB …"`, `MAIL_ALIASES="…"`,
`ALIAS_OWNER=…`. Passwords are generated and written only to `/root/kushol-credentials-*.txt`:
move them into the password manager, give each person theirs privately, put noreply's into
`env/api.env` (`SMTP_*`, when 03's email OTP ships), then `shred -u` the file. Rerunning never
changes an existing mailbox.

Then: add the mail DNS records it prints (§4 table + the DKIM value), wait for them to resolve, run
it again for the `mail.`/`webmail.` certificate, and verify — send to a Gmail and an Outlook
address, check the headers for `spf=pass dkim=pass dmarc=pass`, and score it on a mail-tester
site. A new IP may land in spam at first.

| Client setting | Value |
| --- | --- |
| IMAP | `mail.kusholconnect.com:993` SSL/TLS |
| SMTP | `mail.kusholconnect.com:587` STARTTLS, login = full address |
| Webmail | `https://webmail.kusholconnect.com` |

Mailboxes live on the VPS disk — HestiaCP's user backups must be copied off-box (Part B backups).

## 6. Day-2 operations

| Task | Command (as `kushol` on the server unless noted) |
| --- | --- |
| Deploy api and/or web | `/opt/kushol/ops/deploy.sh pilot api=main-<sha7> web=main-<sha7>` (omit one to keep it) |
| Roll back to the previous release | `/opt/kushol/ops/rollback.sh pilot` |
| Status · logs · restart | `/opt/kushol/ops/compose.sh ps` · `… logs -f --tail 100 api` · `… restart web` |
| Smoke | `/opt/kushol/ops/smoke.sh` |
| Release history | `cat /opt/kushol/state/releases.log` (`incidents.log` next to it) |
| Migrations (owner, Gate 2) | `/opt/kushol/ops/migrate.sh main-<sha7> status` / `up --confirm` |
| Memory check (weekly) | `docker stats --no-stream` · `free -m` · `df -h /` |
| Disk: old images | `docker image prune -f` (dangling only — keep recent tags so rollbacks stay fast) |
| Update templates/scripts | edit in the repo, re-sync (§3.2), rerun `hestia/setup-web.sh` as root |
| After a HestiaCP upgrade | rerun `hestia/setup-web.sh` (custom templates survive, but re-applying is cheap) |
| After changing HestiaCP firewall rules | if containers lose outbound access (`/readyz` red on Neon): `systemctl restart docker` (root) |

Deploy flow: lock → tags and env checked → pull (failure changes nothing) → schema check with the
new image (behind → stop, nothing changed) → `up -d` (brief restart) → `/readyz` ≤ 120 s → smoke →
`SERVING` line in `releases.log`. A red gate or smoke rolls back to the release that was serving
and writes `incidents.log`. Rollback picks the newest release whose last log line is `SERVING` and
marks the abandoned one `ROLLED_BACK`, so repeated rollbacks walk backwards.

### Exit codes (`deploy.sh`, `rollback.sh`)

| Code | Meaning |
| --- | --- |
| 0 | Serving the requested release |
| 1 | Failed — rolled back when a previous release existed (see stdout: `ROLLED_BACK` / `ROLLBACK_FAILED` / `FAILED`) |
| 2 | Usage or precondition: bad tag, env file incomplete or not 600, env name mismatch, lock held, nothing to roll back to |
| 3 | Database behind the new image — owner runs the migrations (§3.7), then redeploys; nothing changed |
| 4 | Database schema dirty — a migration failed midway; fix forward before deploying; nothing changed |
| 5 | Image pull failed (registry login/token, unknown tag, network); nothing changed |

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `deploy.sh` exit 5 (pull failed) | registry token expired or not logged in; tag never pushed; network | `sudo -iu kushol docker login docker.io -u airahul`; check the tag exists in the registry; retry — nothing changed |
| exit 3 (database behind) | the new api image embeds migrations the database lacks | owner runs `ops/migrate.sh <tag> up --confirm` (Gate 2), then deploys again |
| exit 4 (database dirty) | a migration failed midway | inspect with `ops/migrate.sh <tag> status`; fix forward per the api README "Migrations"; never edit an applied file |
| exit 2 naming env keys | an env file is incomplete, still has `REPLACE`, or is not chmod 600 | fill the named keys; `chmod 600 /opt/kushol/env/*.env` |
| exit 2 "another deploy … holds" | a deploy or rollback is running (or crashed holding the lock — the lock is released when its process ends) | wait; check `ps aux \| grep deploy.sh` |
| Gate: `/readyz` not 200 | Neon unreachable or suspended; wrong `DATABASE_URL`; Redis down | `ops/compose.sh logs --tail 100 api`; `curl -s http://127.0.0.1:8180/readyz` names the failing dependency; check the Neon console |
| `/readyz` red on Neon right after a HestiaCP firewall change | HestiaCP rebuilt iptables and the containers lost outbound access | `systemctl restart docker` (root) — containers come back by restart policy; then `ops/smoke.sh` |
| Nginx 502 on the site or `api.` | containers not running, or ports in `stack.env` differ from the installed templates | `ops/compose.sh ps`; if ports changed, rerun `hestia/setup-web.sh`, then `ops/deploy.sh pilot` |
| Default HestiaCP page or another site on `kusholconnect.com` | DNS points here but the web domain or template is missing | rerun `hestia/setup-web.sh` |
| Let's Encrypt fails in `setup-web.sh`/`setup-mail.sh` | name does not resolve here yet; port 80 blocked; a CAA record not allowing Let's Encrypt | `dig +short <name>`; check the HestiaCP log under `/var/log/hestia/`; rerun |
| `www` does not redirect | pass 2 of `setup-web.sh` not run (the redirect is added after the certificate) | rerun `hestia/setup-web.sh` |
| Browser calls the wrong api URL | the web image was built with other `NEXT_PUBLIC_*` values | fix the repo variables, rebuild (new image), deploy it ([`docs/images.md`](docs/images.md) §3.2) |
| Compose "Pool overlaps with other one on this address space" | `KUSHOL_SUBNET` collides with a new co-tenant network | choose another subnet in `stack.env` (TRUSTED_PROXIES follows it), `ops/deploy.sh pilot` |
| A container stopped and stays down after a reboot | it was stopped by hand (`unless-stopped` honours that) | `ops/deploy.sh pilot` (no tags = redeploy the current release) |
| Container restarting / OOM | memory cap hit | `docker stats --no-stream`, `ops/compose.sh logs <svc>`; raise the cap in `compose.yaml` only with measured headroom |
| Disk filling | old images, logs | `docker image prune -f`; container logs are capped at 50 MB each; `df -h /` |
| Mail lands in spam | new IP reputation; SPF/DKIM/DMARC not passing | check message headers; confirm the DNS records ([`docs/hestia.md`](docs/hestia.md) §2.2); mail-tester |
| Mail does not leave the server | outbound port 25 blocked by the provider | `prepare-host.sh`/`setup-mail.sh` report it; ask Hostinger support to unblock SMTP |

## 8. Incidents

Write one entry per incident in `state/incidents.log` (the scripts add one-liners automatically)
and a full note in the module's `07-progress.md`:

```text
When (UTC) · detected by (uptime alert / deploy gate / user) · impact (who, what, how long)
Timeline · cause · actions (rollback / restore / restart) · follow-ups (owner, date)
```

`ROLLBACK_FAILED`: check `ops/compose.sh ps` and `logs`; if Neon or Redis is the cause, fix it and
rerun `ops/rollback.sh pilot`; if the images are gone, pull an older logged tag explicitly with
`ops/deploy.sh`.

## 9. Not yet (module 15 Part B and other modules)

Written but never executed (owner-run): backup cron + restore drill, uptime check, weekly
log-redaction probe, maintenance mode (`ops/maintenance.sh on|off`) — see `docs/backups.md`.
Not built: error tracking · Playwright login smoke (with 03) · blue/green zero-downtime deploys.
Tracked in `docs/modules/15-deployment-operations/08-gaps.md`.
