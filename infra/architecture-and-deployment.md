# Kushol Connect — Architecture, Deployment & Email Plan

| | |
| --- | --- |
| **Status** | 🟡 Proposed — owner review (items marked **Decision** need Rahul) |
| **Date** | 2026-09-30 |
| **Owner** | Rahul (product owner) |
| **Scope** | Runtime architecture, Hostinger KVM 2 deployment, domain/DNS, email |
| **Binding sources** | `prompt.txt`, `docs/tech-stack.md`, `docs/modules/01-foundations`, `docs/modules/15-deployment-operations`, `docs/modules/README.md` (cross-module registries) |

> The module specs were aligned with this plan on 2026-09-30 (§9). Future changes update both in the
> same commit.

---

## 1. Verified facts (checked 2026-09-30)

| Item | Fact | How verified |
| --- | --- | --- |
| VPS | Hostinger **KVM 2**, id `1100749`, `srv1100749.hstgr.cloud`, 2 vCPU / 8 GB RAM / 100 GB disk, IPv4 `72.61.114.20`, IPv6 `2a02:4780:5e:99d7::1`, running since 2025-11-02 | Hostinger VPS API |
| VPS OS image | "Ubuntu 24.04 with HestiaCP" — shared with 2 other applications | Hostinger VPS API + `tech-stack.md` |
| Docker Manager | **Not available** on this image (`[VPS:2044] Currently installed operating system does not support Docker Manager`) | Hostinger VPS API |
| VPS data centre | id `21` — **location not yet confirmed** (API check blocked) | `TODO: Confirm` in hPanel → VPS → Overview |
| Domain | `kusholconnect.com`, registrar Hostinger, created 2026-09-29, expires 2029-09-29, auto-renew on | WHOIS + billing API |
| Domain DNS today | **Parked**: NS `horizon.dns-parking.com` / `orbit.dns-parking.com`; `@` and `www` → `2.57.91.91` (Hostinger parking); no MX; no `api` record | `dig` |
| Other subscriptions | Premium Web Hosting (in trial, renews 2026-11-09) — not used for Kushol | Hostinger billing API |
| Email | **Owner decision 2026-09-30: mail for `kusholconnect.com` is managed by HestiaCP's mail server on the KVM 2** (Exim + Dovecot, webmail) | owner |
| Code | Each application is its own git repo (`applications/api`, `web`, `app`, `ai`; no shared package — owner 2026-09-30). The api, web and app repos are scaffolded by module 01 (nothing committed yet); nothing deployable yet | workspace |
| Tooling access | Hostinger VPS/domains/billing connectors work; `hostinger-dns` and `hostinger-reach` disconnected (owner reconnects via `/mcp`); no SSH access for the agent | session |

## 2. Findings (architecture, deployment, tech-stack review)

Severity: **H** = would break or cause an outage/security issue · **M** = real cost/risk · **L** = hygiene.

| # | Sev | Finding | Resolution | Status |
| --- | --- | --- | --- | --- |
| F1 | H | VPS ↔ Neon latency: every api request makes several DB round trips; if the VPS is not in Asia, each costs ~150–250 ms | Put Neon in the region nearest the VPS (Neon region is a project setting; moving the shared VPS is not) | **Decision** after confirming VPS location |
| F2 | H | 15's `deploy.sh` runs `migrate up`, contradicting "owner runs SQL manually" (Gate 2) | Deploy **verifies** DB schema version ≥ the image's expected version and refuses otherwise; never applies migrations | Applied (§9) |
| F3 | H | Rollback claim "old containers keep serving" is false — `compose up -d` replaces them before the gate | Pilot: accept a short restart blip + automatic rollback on gate failure. Later: blue/green slots (§5.7) | Applied (§9) |
| F4 | H | Web auth across subdomains: 03's host-only `__Host-` session cookie set by `api.` cannot be read by the web server on another host; `NEXT_PUBLIC_API_URL` bakes the API host into the image | Same-origin: `kusholconnect.com/api/*` → api; server-side calls via `API_INTERNAL_URL` | **Done in docs** (03, 07, 15) |
| F5 | H | Docker-published ports bypass HestiaCP's firewall (iptables) | Every port binds `127.0.0.1:` only; CI lint on the Compose file | Applied (§9 — 15 Compose) |
| F6 | M | Neon free tier: the jobs worker (≈1 s poll) and `/readyz` checks keep compute awake, so "scale to zero / cold start" won't happen — the constraint becomes the free plan's compute + storage allowance (chat grows storage) | Budget Neon Launch before the pilot; verify current plan limits | **Decision** |
| F7 | M | Memory caps (api 1.5 g / web 1 g / redis 512 m) are oversized for a box shared with HestiaCP + 2 apps | api 512 m (`GOMEMLIMIT=400MiB`), worker 256 m, web 512 m, redis 256 m (`maxmemory 200mb`, `volatile-lru`); swap file; measure `free -m` first | Applied (§9) |
| F8 | M | Job-worker placement undefined | Same api image, second container `worker` (own restart + memory cap) | Applied (§9 — 01 `FND-BE-014`, 15 Compose) |
| F9 | M | Per-IP OTP limits (20/h/IP) will block schools: Bangladeshi mobile carriers share IPs (CGNAT) and onboarding happens on school Wi-Fi | Per-phone limits primary; per-IP limits much higher; real IP only from trusted proxy | Applied (§9) |
| F10 | M | Bengali PDF receipts (12) and OG images (07): many PDF/SVG renderers don't shape Bengali conjuncts | Spike before module 12 (Go text-shaping lib vs. a renderer in the api image) | Spike task `PAY-BE-000` added (12) |
| F11 | M | App must send email (OTP codes, notifications, vendor invite, staff password reset) but no module owns email | `noreply@` via HestiaCP SMTP (§7.3); 03 adds an email OTP channel + staff forgot-password; 06 adds an `email` notification channel | Applied (§9) |
| F12 | M | No error/crash tracking (low-end Android crashes invisible) | Sentry-class free tier for api/web/app (`TODO: Confirm` vendor) | **Decision** |
| F13 | L | Unpinned choices: "golang-migrate **or** goose", "envconfig/viper-style" | golang-migrate (all specs assume it) · one config lib chosen at 01 build | golang-migrate pinned; Go env parser picked at 01 |
| F14 | L | App stack gaps: no persistent offline store (chat queue), image compression, audio | react-native-mmkv or expo-sqlite · expo-image-manipulator · expo-audio | Applied (§9) |
| F15 | L | `@react-native-firebase` means EAS development builds (no Expo Go) | State in tech-stack | Applied (§9) |
| F16 | L | Consider River (Postgres job queue for Go) instead of hand-building 01's `jobs` | Evaluated in 01 Stage 1: keep the spec'd hand-built queue (River brings its own schema/migration tooling and maintenance loops that clash with owner-run migrations and Neon idle) | Decided (01, 2026-09-30) |
| F17 | M | Self-hosted mail on a shared VPS: deliverability depends on reverse DNS, SPF/DKIM/DMARC and the IP's reputation; ClamAV/SpamAssassin use RAM on the same 8 GB box | §7.2 checklist (PTR = `mail.kusholconnect.com`, DKIM from HestiaCP, DMARC), include the mail stack in the memory budget, verify outbound port 25 is open on the VPS | Owner actions §8 |
| F18 | M | With one repo per application there is no monorepo home for `docker-compose.yml`, `deploy/hestia/` templates, `ops/` scripts and the release log | Options: keep them in the api repo under `deploy/` (simplest), or a small separate `ops` repo; each app repo's CI builds and pushes only its own image | Owner decision (§8 #9) |
| F19 | M | Behind Docker port publishing the api sees the bridge gateway (not 127.0.0.1) as the TCP peer, so a loopback-only proxy trust list would ignore Nginx's `X-Forwarded-For` and rate-limit everyone as one IP | 01 adds `TRUSTED_PROXIES` (IPs/CIDRs, default loopback); 15's Compose sets it to the project network CIDR (fixed subnet in `docker-compose.yml`) | Applied in 01; 15 to set |

## 3. Target architecture

### 3.1 Topology

```text
                         ┌──────────────── Hostinger KVM 2 (72.61.114.20, HestiaCP, shared) ───────────────┐
 Browser ──HTTPS──► Nginx (HestiaCP, Let's Encrypt, fail2ban)                                               │
   kusholconnect.com ─────────────► 127.0.0.1:3100  web     (Next.js standalone)                           │
   kusholconnect.com/api/* ───────► 127.0.0.1:8180  api     (Go: REST)                                     │
 Mobile app ──HTTPS/WSS──►                                                                                  │
   api.kusholconnect.com ─────────► 127.0.0.1:8180  api     (Go: REST + WebSocket /ws)                     │
                                                  worker  (same Go image, `worker` mode: jobs)             │
                                                  redis   (cache, presence, rate limits — not a store)    │
                         └──────────────────────────────────────────────────────────────────────────────────┘
   api/worker ──TLS──► Neon Postgres (region = nearest to VPS, F1)
   api/worker ──TLS──► Cloudflare R2 (media, receipts; backups bucket)
   api/worker ──HTTPS─► FCM · SMS gateway · DeepSeek · SSLCommerz/bKash/Nagad
   api/worker ──SMTP 587 (STARTTLS)─► HestiaCP Exim on the same VPS (noreply@) ─► recipients (§7.3)
   Team mail clients ──IMAPS 993 / SMTP 587 / webmail──► mail.kusholconnect.com (HestiaCP Dovecot/Exim)
   Mobile/web ──HTTPS─► R2 presigned URLs (uploads/downloads never pass through the VPS)
   GitHub Actions ──► GHCR (images) ──pull──► VPS          EAS ──► APK / TestFlight
```

Ports `3100`/`8180` are placeholders chosen to avoid common defaults the co-tenant apps may use —
final values after `ss -tlnp` on the host (§5.1).

### 3.2 Runtime processes

| Process | Image | Role | Memory cap | Scaling note |
| --- | --- | --- | --- | --- |
| `api` | `ghcr.io/<org>/kushol-api:<tag>` | chi REST + gorilla WebSocket gateway; stateless apart from WS connections | 512 m (`GOMEMLIMIT=400MiB`) | One instance for pilot; Redis pub/sub already allows a second |
| `worker` | same image, command `worker` | `jobs` claim loop (SKIP LOCKED), cron-like schedules (SLA reminders, archival, backups trigger) | 256 m | Poll interval backs off when idle (F6) |
| `web` | `ghcr.io/<org>/kushol-web:<tag>` | Next.js standalone: landing + Command Center; server-side calls → `http://api:8080` | 512 m | Static assets cached by Nginx |
| `redis` | `redis:7-alpine` (pinned digest) | cache, presence, rate limits, idempotency *hints* (DB unique constraints are the real guard) | 256 m, `maxmemory 200mb`, `volatile-lru`, no persistence required | Loss = degraded, never data loss |
| `ai` (Phase 2+, optional) | `kushol-ai` FastAPI | only if DeepSeek orchestration outgrows the Go `AIService` | 384 m | Internal network only |

Total Kushol containers ≈ 1.5 GB (+ ai later). The HestiaCP mail stack (Exim, Dovecot, and
especially ClamAV ≈ 1 GB if enabled) runs on the host outside Docker and must fit in the same
8 GB alongside the 2 co-tenant apps — confirm with `free -m` after mail is enabled.

### 3.3 Request paths

| Path | Flow |
| --- | --- |
| Web page (Command Center) | Browser → Nginx → web (Server Component) → `http://api:8080` with the forwarded `__Host-` session cookie → Neon |
| Web client-side fetch | Browser → `kusholconnect.com/api/v1/...` → Nginx → api (same origin: no CORS, cookie host-only) |
| Mobile REST | App → `api.kusholconnect.com/api/v1/...` with `Authorization: Bearer <15-min JWT>`; refresh rotation (03) |
| Mobile chat | App → `wss://api.kusholconnect.com/ws` (Nginx upgrade, `proxy_read_timeout 300s`, app pings) |
| Media | App/web asks api for a presigned R2 URL → uploads directly to R2 → api confirms (magic-byte sniff) |
| Push | api → FCM (topics `city-/school-/section-{id}` + per-token) → devices |
| Payments (Phase 3) | App → gateway page → callback/webhook `api.kusholconnect.com/api/v1/webhooks/...` → server-to-server status confirm → ledger |

### 3.4 Cross-cutting rules (from module 01, restated for operators)

`X-Request-Id` on every request and log line · RFC-7807 errors · `/healthz` (liveness, no deps) and
`/readyz` (Neon + Redis) · env read only via the config module · real client IP taken from
`X-Forwarded-For` **only** when the peer is `127.0.0.1` (Nginx) · containers non-root · no secrets
in images, logs or `NEXT_PUBLIC_*`.

## 4. Environments

| Env | Where | Database | Domain | Notes |
| --- | --- | --- | --- | --- |
| dev | developer machine (`go run`, `next dev`, Expo dev build) | Neon dev branch | localhost | MinIO allowed locally only |
| pilot | KVM 2, Compose project `kushol` | Neon project (region per F1) | `kusholconnect.com`, `api.kusholconnect.com` | The only server environment during pilot |
| prod | same box, **after pilot** | Neon paid plan | same domains | Pilot environment is promoted, not duplicated — the shared 8 GB box cannot hold two stacks comfortably |

A separate staging stack is **not** run on the KVM 2; use Neon branches + local Compose for
pre-release checks.

## 5. Deployment plan — Hostinger KVM 2 (Docker Engine + Compose, behind HestiaCP)

### 5.1 One-time host checks (owner, via SSH)

```bash
lsb_release -a            # expect Ubuntu 24.04
free -m                   # real headroom → confirm memory caps (F7)
df -h /                   # disk headroom for images + logs
ss -tlnp                  # ports already taken by co-tenant apps → choose web/api ports
docker --version || echo "docker not installed"
docker compose version || true
```

Record results in `docs/modules/15-deployment-operations/07-progress.md` when module 15 starts.

### 5.2 Host preparation

1. **Docker Engine + Compose plugin** from Docker's official apt repository (not the snap).
   Enable log rotation in `/etc/docker/daemon.json`: `json-file`, `max-size 10m`, `max-file 5`.
2. **Deploy user** `kushol` (non-root, in the `docker` group), SSH key-only; HestiaCP fail2ban
   already covers SSH.
3. **Swap file** 2 GB if none exists (protects co-tenants from OOM spikes).
4. **Directories:** `/opt/kushol/` → `docker-compose.yml`, `.env` (chmod 600, owner root),
   `ops/` scripts, `releases.log`.
5. **GHCR pull token** (read-only) in `/opt/kushol/.env`; `docker login ghcr.io`.

### 5.3 Compose file (shape — final file lands with module 15 Part A)

```yaml
name: kushol
services:
  api:
    image: ghcr.io/<org>/kushol-api:${API_TAG}
    command: ["serve"]
    env_file: .env
    environment: { GOMEMLIMIT: 400MiB }
    ports: ["127.0.0.1:8180:8080"]          # loopback only (F5)
    mem_limit: 512m
    restart: unless-stopped
    read_only: true
    user: "65532:65532"
    healthcheck: { test: ["CMD", "/app", "healthcheck"], interval: 15s, retries: 3 }
    depends_on: [redis]
  worker:
    image: ghcr.io/<org>/kushol-api:${API_TAG}
    command: ["worker"]
    env_file: .env
    mem_limit: 256m
    restart: unless-stopped
    read_only: true
    user: "65532:65532"
    depends_on: [redis]
  web:
    image: ghcr.io/<org>/kushol-web:${WEB_TAG}
    env_file: .env.web
    environment: { API_INTERNAL_URL: "http://api:8080" }
    ports: ["127.0.0.1:3100:3000"]
    mem_limit: 512m
    restart: unless-stopped
  redis:
    image: redis:7-alpine@sha256:<pinned>
    command: ["redis-server", "--maxmemory", "200mb", "--maxmemory-policy", "volatile-lru", "--save", ""]
    mem_limit: 256m
    restart: unless-stopped
```

(The distroless api image has no shell/curl, so its healthcheck is a subcommand of the binary.)

### 5.4 Nginx via HestiaCP

- Add web domains in HestiaCP: `kusholconnect.com` (alias `www.kusholconnect.com`) and
  `api.kusholconnect.com`; issue Let's Encrypt certificates there.
- Custom **proxy templates** (versioned in repo under `deploy/hestia/`; re-applied after HestiaCP
  upgrades; repo home per F18):
  - `kusholconnect.com`: `/` → `127.0.0.1:3100`; `/api/` → `127.0.0.1:8180`; `www` → 301 to apex;
    immutable caching for `/_next/static/`; security headers + CSP; `client_max_body_size 2m`
    (uploads go to R2 directly).
  - `api.kusholconnect.com`: `/` → `127.0.0.1:8180`; `/ws` with `Upgrade`/`Connection` headers,
    `proxy_read_timeout 300s`; `client_max_body_size 2m`; payment/ERP webhook paths allowed without
    auth (signature-verified in the api).
  - Both: `proxy_set_header X-Forwarded-For $remote_addr` (overwrite, not append), `X-Request-Id`
    pass-through, gzip/brotli.
- Maintenance mode: a flag file that makes Nginx serve the static bn/en page with `503` + `no-store`.

### 5.5 CI/CD

| Step | Where | Detail |
| --- | --- | --- |
| Quality gate | GitHub Actions | api: `gofmt`, `golangci-lint`, `go vet`, `go test`, testcontainers ITs · web/app: lint, typecheck, test, build · contract drift check · gitleaks |
| Images | GitHub Actions → GHCR, one workflow per app repo | `kushol-api` (api repo), `kushol-web` (web repo); tag `main-<sha7>` (immutable); multi-arch not needed (amd64); base images pinned by digest |
| Deploy | Operator runs `ops/deploy.sh <tag>` over SSH (manual, pilot) | Optional later: GitHub Actions job with an SSH key restricted to that script |
| Mobile | EAS Build/Submit | profiles development/preview/production; `EXPO_PUBLIC_API_URL=https://api.kusholconnect.com` for preview/production |

### 5.6 Deploy script behaviour (fixes F2)

```text
ops/deploy.sh <tag>
 1. take lock; validate tag format; check .env keys against .env.example
 2. docker compose pull (new tags) — failure → exit, nothing changed
 3. schema check: `api migrate-status` (read-only) → DB version must be ≥ the version the image
    embeds; if lower → STOP: "run migrations <files> manually first" (owner Gate 2); never auto-apply
 4. docker compose up -d api worker web (brief restart of changed services)
 5. poll /readyz up to 120 s; run smoke (healthz, landing 200, login round-trip)
 6. green → append releases.log · red → automatic rollback to the previous logged tag (step 4–5
    with old tags) + incident note, exit ≠ 0
```

Migrations follow expand/contract so the previous image still works against the newer schema —
this is what makes automatic rollback safe.

### 5.7 Zero-downtime (later, optional — F3)

Two api slots (`api_blue` on 8180, `api_green` on 8181) and an Nginx upstream include file that the
deploy script rewrites + `nginx -t && systemctl reload nginx` (needs a narrowly scoped sudo rule).
Adopt when deploy blips become visible to users; WebSocket clients reconnect with backoff either way.

### 5.8 Backups & restore

| What | How | Retention |
| --- | --- | --- |
| Postgres | Neon built-in backups/PITR (plan-dependent) **plus** nightly `pg_dump -Fc` at 02:30 Asia/Dhaka run from a `postgres:<major>` container (client ≥ server version) → sha256 → R2 backups bucket (versioned) → off-site copy (`TODO: Confirm` target) | 30 days |
| Media / receipts | R2 bucket versioning | per bucket policy |
| Host config | `/opt/kushol` (minus secrets) + HestiaCP templates in git | git |
| Secrets | Owner's password manager (not on the box only) | — |
| Drill | Restore latest dump to a Neon branch + api smoke; quarterly and before pilot sign-off | evidence in 15's `07-progress.md` |

### 5.9 Monitoring

- External uptime checker (`TODO: Confirm` provider): `https://api.kusholconnect.com/healthz` every
  60 s, `/readyz` every 5 min, alerts by email + Telegram.
- Error tracking (F12, **Decision**): api + web + app.
- Weekly: `docker stats` memory review, disk usage, backup log, failed `jobs` (DEAD) count.
- Logs: JSON stdout, rotated by Docker (10 MB × 5); redaction verified weekly.

### 5.10 Rollout sequence

| Step | When | Output |
| --- | --- | --- |
| 0 | Now | Owner: confirm VPS location (F1), run §5.1 checks, point DNS (§6), set up mailboxes (§7) |
| 1 | After module 01 | api image with `/healthz` + `/readyz`; host prepared (§5.2) |
| 2 | After module 02 | web image (landing shell); **module 15 Part A**: Compose + Nginx + TLS + deploy/rollback scripts live on `kusholconnect.com` |
| 3 | Modules 03–07 | Each module deploys through the same script; owner runs each module's SQL before its deploy |
| 4 | Pilot readiness | Neon plan decision (F6), backups + restore drill, uptime + error tracking, EAS preview → pilot schools |
| 5 | After module 14 | **Part B** hardening: production keys (FCM, gateways), prod app channels, runbooks, `DEPLOYMENT.md` |

## 6. DNS plan for `kusholconnect.com`

Records to create once hosting decisions are confirmed (owner applies in hPanel → Domains → DNS,
or approves when the `hostinger-dns` connector is reconnected):

| Type | Name | Value | Purpose |
| --- | --- | --- | --- |
| A | `@` | `72.61.114.20` | web |
| A | `www` | `72.61.114.20` | redirect to apex |
| A | `api` | `72.61.114.20` | mobile API + WebSocket + webhooks |
| AAAA | `@`, `www`, `api` | `2a02:4780:5e:99d7::1` | IPv6 (optional; only if Nginx listens on IPv6) |
| A | `mail` | `72.61.114.20` | HestiaCP mail host (SMTP/IMAP, Let's Encrypt cert) |
| A | `webmail` | `72.61.114.20` | HestiaCP webmail |
| MX | `@` | `10 mail.kusholconnect.com` | inbound mail to HestiaCP |
| TXT | `@` | `v=spf1 a mx ip4:72.61.114.20 ip6:2a02:4780:5e:99d7::1 -all` (drop `ip6` if mail isn't sent over IPv6) | SPF — **one** record only |
| TXT | `mail._domainkey` | public key HestiaCP generates for the mail domain (Mail → domain → DNS records / DKIM) | DKIM |
| PTR (set in hPanel/VPS API, not in the zone) | `72.61.114.20` (+ IPv6) | `mail.kusholconnect.com` | reverse DNS — currently `srv1100749.hstgr.cloud`; **shared with the 2 co-tenant apps**, so check whether they send mail under another name before changing it |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@kusholconnect.com` → tighten to `quarantine` after 2–4 weeks of clean reports | DMARC |
| CAA (optional) | `@` | `0 issue "letsencrypt.org"` | restrict certificate issuers |

Nameservers: keep Hostinger DNS (simplest) — the domain currently uses the parking nameservers,
which must be switched to Hostinger's regular DNS nameservers (or records added if hPanel manages
the parking zone directly). Moving DNS to Cloudflare (already used for R2) is an option if we
later want its proxy/DDoS protection; not required for the pilot.

## 7. Email plan

### 7.1 Addresses requested

| Address | Type | Who reads it | Notes |
| --- | --- | --- | --- |
| `aktarul.islam@kusholconnect.com` | Personal mailbox | Aktarul Islam | |
| `jafrin.myoria@kusholconnect.com` | Personal mailbox | Jafrin Myoria | Requested as `jafrin.myoria@@…` — double `@` assumed to be a typo |
| `atiqul.islam@kusholconnect.com` | Personal mailbox | Atiqul Islam | |
| `hello@kusholconnect.com` | Forwarder (or shared mailbox) | team | Public contact on the landing page, pilot enquiries; forward to the people who answer |
| `noreply@kusholconnect.com` | App sending mailbox | nobody (autoreply/discard) | Sends **OTP codes, notifications**, invites and resets; the api authenticates to HestiaCP SMTP with it (§7.3); `Reply-To: hello@…` |

Also recommended: `dmarc@` (alias → a personal mailbox) for DMARC reports, and `postmaster@` /
`abuse@` aliases.

### 7.2 Mailboxes (people) — HestiaCP mail server (owner decision 2026-09-30)

Mail for `kusholconnect.com` runs on the KVM 2 under HestiaCP (Exim for SMTP, Dovecot for IMAP,
webmail, optional SpamAssassin/ClamAV). It is independent of Docker: the Kushol containers never
bind ports 25/465/587/993.

**Setup checklist (owner — the agent does not create accounts or set passwords):**

1. HestiaCP → **Mail** → *Add mail domain* `kusholconnect.com` — enable DKIM, anti-spam, and
   (if RAM allows) anti-virus; enable SSL (Let's Encrypt) for `mail.kusholconnect.com`.
2. Add the A/MX/SPF/DKIM/DMARC records from §6 (HestiaCP shows the exact DKIM TXT value on the
   mail domain's DNS page). If Hostinger keeps DNS, copy them into hPanel DNS; do **not** also run
   the zone in HestiaCP's DNS server unless nameservers point to the VPS.
3. Create mailboxes: `aktarul.islam`, `jafrin.myoria`, `atiqul.islam` (strong unique passwords,
   shared privately with each person; set a quota per mailbox).
4. Create `hello` as a **forwarder/alias** to the people who answer enquiries (or a mailbox if a
   shared login is preferred). Add `dmarc`, `postmaster` and `abuse` as forwarders.
5. Create `noreply` as a **mailbox** (the app authenticates to SMTP with it — §7.3); set an
   autoreply ("this address is not monitored — write to hello@kusholconnect.com") or discard
   filter.
6. Reverse DNS: set the PTR of `72.61.114.20` to `mail.kusholconnect.com` (hPanel → VPS → Settings,
   or the Hostinger VPS API) — **coordinate with the 2 co-tenant apps** first, because one IP has
   only one PTR.
7. Check outbound port 25 is open from the VPS (`nc -vz gmail-smtp-in.l.google.com 25`); if the
   provider blocks it, request unblocking or relay via a smarthost.
8. Verify: send to a Gmail and an Outlook address, check headers for `spf=pass`, `dkim=pass`,
   `dmarc=pass`; test with a mail-tester service; confirm the IP is not on common blocklists.
9. Client settings for the team: IMAP `mail.kusholconnect.com:993` (SSL), SMTP
   `mail.kusholconnect.com:587` (STARTTLS), webmail `https://webmail.kusholconnect.com`.
10. Backups: mailboxes live on the VPS disk — include HestiaCP's user backups (or `/home/<user>/mail`)
    in the off-box backup plan (§5.8); mail is not in Neon or R2.

**Risks:** a new VPS IP has no sending reputation, so early mail to Gmail/Outlook may land in spam
until SPF/DKIM/DMARC pass and volume is steady; the IP is shared with two other apps, so their
mail behaviour affects Kushol's reputation (and vice versa); the VPS is a single point of failure
for mail as well as the app.

### 7.3 Application email (transactional)

| Item | Plan |
| --- | --- |
| What the app sends (owner decision 2026-09-30: all from `noreply@`) | **OTP codes by email** (03 — new `email` OTP channel: staff login/verification, and a fallback when SMS is delayed) · **notifications by email** (06 — new `email` channel next to push/SMS, per-user preferences) · vendor portal invite (07 → 03 `users.CreateVendorLogin`) · staff password reset (03 — flow to be specified) · receipts later (12, optional) |
| How (pilot) | The Go api/worker sends over **SMTP submission to HestiaCP's Exim** — `mail.kusholconnect.com:587`, STARTTLS, authenticated as `noreply@kusholconnect.com`; **no SMTP server in Docker** |
| Upgrade path | If deliverability or volume becomes a problem, switch the 06 email channel to a transactional provider's HTTPS API (Amazon SES, Postmark, Resend or Brevo — `TODO: Confirm`) — a config/adapter change only |
| Sending identity | From `Kushol Connect <noreply@kusholconnect.com>`, Reply-To `hello@kusholconnect.com`; same SPF/DKIM as the team's mail (one server). Keep volume low (invites, resets) so app mail doesn't hurt the team's deliverability |
| Code owner | Module **06 notifications** adds an `email` channel next to push and SMS (templates bn + en, delivery rows, retries via `jobs`) |
| Env | `SMTP_HOST=mail.kusholconnect.com`, `SMTP_PORT=587`, `SMTP_USERNAME=noreply@kusholconnect.com`, `SMTP_PASSWORD`, `EMAIL_FROM`, `EMAIL_REPLY_TO` (config module only; password only in the host `.env`) |
| OTP email rules | Same store and limits as SMS OTP (03 `otp_codes`, HMAC with `OTP_PEPPER`, 5-min TTL, ≤ 3 attempts, 60 s resend cooldown, per-address hourly cap); subject and body bilingual (bn default) with the code only — no login link, no account details; sent **immediately** (not batched) with a short SMTP timeout and one retry, then the UI offers SMS/resend; phone OTP stays the primary path for students/guardians unless the owner decides otherwise |
| Notification email rules | Only for notification classes the user has email enabled for (06 preferences); `List-Unsubscribe` + footer opt-out on non-essential mail; titles/ids only for chat — never message bodies of minors' chats; digest instead of one mail per event where volume is high |
| Reset/invite links | Single-use, ≤ 30 min, hashed at rest |
| Volume & deliverability guard | OTP + notification mail makes `noreply@` the highest-volume sender on a new, shared VPS IP. Set an Exim per-account send limit for `noreply` in HestiaCP (`verify` setting), watch bounces/spam reports weekly, and move the 06 channel to a transactional provider (upgrade path above) if OTP mail is delayed or lands in spam, or if volume grows past what the box handles comfortably — OTP delivery time is a user-facing SLA |

## 8. Owner decisions & actions

| # | Item | Needed by |
| --- | --- | --- |
| 1 | Confirm VPS data-centre location → choose Neon region (F1) | Before module 01 build |
| 2 | Run §5.1 host checks and share output | Before module 15 Part A |
| 3 | Switch domain off parking + add A records (§6) | Before first deploy |
| 4 | HestiaCP mail setup (§7.2 checklist): mail domain, 5 addresses, DNS records, PTR (coordinate with co-tenants), port-25 check | Anytime (independent of the app) |
| 5 | Confirm pilot app mail via HestiaCP SMTP (`noreply@`) vs a transactional provider (§7.3) | Before module 07 vendor approval / 03 staff reset |
| 6 | Neon plan for pilot (F6) | Before pilot |
| 7 | Error-tracking vendor (F12) and uptime checker | Before pilot |
| 8 | Reconnect `hostinger-dns` via `/mcp` if you want DNS changes prepared through the connector | Optional |
| 9 | Where deploy files live now that each app is its own repo (F18) | Before module 15 Part A |

## 9. Spec edits (applied 2026-09-30)

| Module / file | Edit | Status |
| --- | --- | --- |
| 15 (`01`/`02`/`03`/`06`/`technical-document`) | Deploy never migrates (read-only `migrate-status` check, owner runs SQL); auto-rollback on gate/smoke failure; `worker` container; caps api 512m / worker 256m / web 512m / redis 256m; configurable ports (8180/3100); one server stack promoted pilot → prod; host-prep runbook `OPS-BE-016`; HestiaCP mail backups; Docker Engine (no Docker Manager); apex + `api.` templates | ✅ |
| 01 | `FND-BE-014` subcommands `serve`/`worker`/`migrate`/`migrate-status`/`healthcheck`; worker idle back-off to 30 s; RealIP trusts only the local proxy; golang-migrate pinned | ✅ |
| 03 | Email OTP channel (`otp_codes.channel`/`email`, `reset` purpose); forgot/reset password endpoints + `IDT-US-015`; vendor first-password via reset OTP; per-IP limits raised for CGNAT (per-target caps primary) | ✅ |
| 06 | `notify.SendEmail` (otp/account/notification), SMTP to HestiaCP as `noreply@`, OTP never persisted, `channel`/`provider` columns (stale `expo` removed), `email_enabled` preference + `List-Unsubscribe`, `NTF-BE-023`, SMTP env | ✅ |
| 12 | Bengali PDF spike `PAY-BE-000` before the receipt job; risk row added | ✅ |
| `tech-stack.md` | EAS dev builds (no Expo Go); MMKV + secure-store; image-manipulator + expo-audio; golang-migrate pinned; worker; email (HestiaCP SMTP); PDF `verify`; monitoring row; Go env parser (no viper); container caps | ✅ |
| `prompt.txt` | SMTP/email env vars, `API_INTERNAL_URL`, `API_PORT`/`WEB_PORT` | ✅ |

## 10. Change log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial plan: verified Hostinger facts, review findings F1–F16, target architecture, KVM 2 Docker deployment, DNS and email plan | Claude |
| 2026-09-30 | §9 spec edits applied to 01, 03, 06, 12, 15, `tech-stack.md`, `prompt.txt` | Claude |
| 2026-09-30 | `noreply@` confirmed as the sender for OTP codes and notifications (§7.3 rules, volume guard) | Claude |
| 2026-09-30 | Email switched to HestiaCP's mail server per owner (§7.2 checklist, SMTP-based app mail, F17, mail DNS/PTR records) | Claude |
| 2026-09-30 | Isolated application repos (owner): per-repo image builds, F18 (home for deploy files), F19 (`TRUSTED_PROXIES` behind Docker), F16 decided | Claude |
