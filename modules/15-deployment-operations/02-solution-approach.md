# Deployment & Operations — Solution Approach

**Module:** `15-deployment-operations` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Two parts: **Part A** (walking skeleton, after 01/02) and **Part B** (production hardening, after 14) — see 01 §1. Binding correction throughout: per `docs/tech-stack.md` §Infrastructure (decision 2026-09-29), Postgres is **off-box on Neon** and media **off-box on Cloudflare R2**; Compose runs **api + web + redis only** (the README row's "Postgres/MinIO" is superseded, not silently dropped).

---

## 1. Domain Model

### 1.1 Entities

No database entities — **"None — infrastructure module"** (15 owns no tables; product tables incl. 01's `audit_log`/`jobs` are owned by 01–14 and probed via `/readyz`). The operational entities below live as infra state, not rows:

| Entity | Description | Owned here? |
| --- | --- | --- |
| Release | One immutable deploy unit: GHCR tag (`main-<sha7>`) + env + timestamp, recorded in `ops/releases.log` | Yes — log file + compose labels only |
| Environment | `dev` (local) / `pilot` / `prod`: one Compose project + one `.env` + one pair of subdomains (BR-004) | Yes — infra config |
| Backup artifact | `pg_dump` custom-format file + sha256, in the versioned R2 backups bucket + off-site copy | Yes — object storage only |
| Runbook / incident entry | English operator procedures; incident log template with timeline/impact/follow-up | Yes — docs in repo |
| App release channel | `development` / `preview` / `production` EAS profiles + OTA channel mapping (05-app §4) | Yes — `eas.json` wiring |

### 1.2 Relationships

```text
  GitHub Actions (CI) ──build+push──► GHCR : ghcr.io/<org>/kushol-{api,web}:main-<sha7>
        │                                     │ pull exact tags (never build on VPS, BR-001)
        ▼                                     ▼
  gitleaks / quality gates            ops/deploy.sh ─► migrate (01 golang-migrate) ─► compose up -d
                                              │ gate: GET /readyz (01) ≤120s ─► smoke (OPS-E2E-001)
users ─HTTPS─► HestiaCP Nginx (TLS, Let's Encrypt, fail2ban)                     ▼
   │        ├─ api.<domain> ──► 127.0.0.1:8080 ── Docker Compose project kushol-<env>
   │        ├─ web.<domain> ──► 127.0.0.1:3000 ──   ├─ api   (mem 1.5g, restart, healthcheck)
   │        └─ maintenance flag ─► static bn/en page └─ web   (mem 1g)   └─ redis (mem 512m, loopback)
   │
   ├─ api ──TLS──► Neon Postgres (off-box, ap-southeast-1)      ◄── cron 02:30 ops/backup.sh ──┐
   ├─ api ──TLS──► Cloudflare R2 (media/receipts, presigned)         pg_dump → sha256 → R2 ────┤
   ├─ api ──► FCM · bKash/Nagad/SSLCommerz · DeepSeek · SMS (module-owned code, 15-wired env)    │
   └─ external uptime checker ──► GET /healthz (60s) + /readyz (5 min)                           │
                                                        R2 backups bucket (versioned) ─► off-site rclone copy
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-001 | Images are built only in CI (GHCR); the VPS only pulls | CI workflow + host-script lint (BR-001) |
| INV-002 | No secret in git, CI logs, or images; env only via host `.env` (chmod 600) + 01 config modules | gitleaks + masking + perms (BR-002) |
| INV-003 | Traffic swaps only after `/readyz` green + smoke pass | `ops/deploy.sh` gate (BR-003) |
| INV-004 | One Compose project per environment; no cross-env sharing | Compose project names (BR-004) |
| INV-005 | Containers bind `127.0.0.1` only; 80/443 + SSH are the host's only open ports | Compose port bindings + HestiaCP firewall/fail2ban |
| INV-006 | Tags are immutable; rollback = redeploy previous logged tag | GHCR scheme + release log (BR-005) |
| INV-007 | Every container has `mem_limit` + `restart` policy + healthcheck | Compose file review (BR-006) |

## 2. Module Boundary

**Owns (writes):** `deploy/` (Dockerfile.api, Dockerfile.web, docker-compose.yml, Nginx/HestiaCP template notes, `.dockerignore`), `ops/` (deploy/rollback/backup/restore scripts, release log, cron definitions, Makefile targets), `.env.example` per deployable, CI image-publish workflow, `eas.json` build wiring, static maintenance page, runbooks + `DEPLOYMENT.md`, `ops.*` string keys in `packages/shared`.

**Reads from other modules (via their exported contracts only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 01 | `/healthz` + `/readyz`, config-module env names, golang-migrate entrypoint, jobs metrics | The gate must test the real health contract, not a copy; migrations belong to the schema owner |
| 02 | Web `standalone` output; app icon/splash assets; brand tokens for the ops page/banner | Assets' single source is 02 |
| 03 | EAS Build/Submit wiring + credentials patterns | App build knowledge lives with the app module |
| 06 | FCM prod credential shape + post-cutover test push | 06 owns the FCM SDK; 15 only wires env |
| 12 | Production gateway key list + webhook URLs (sandbox→prod cutover) | 12 owns gateway code; 15 owns the cutover ceremony |

**Cache keys / tags revalidated / consumed:** None — infrastructure module; see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
Release:  (merge) ─CI─► BUILT ─pull─► PULLED ─migrate up─► MIGRATED ─compose up -d─► GATED
          GATED ─readyz+smoke green─► SERVING ──rollback.sh──► SERVING(prev tag)
          GATED ─gate red─► ABORTED (old containers still serving; incident entry)
App:      channel build/submit per 05-app §4; OTA publish = channel-scoped, runtimeVersion-matched
Backup:   nightly cron ─► dump ─► checksum ─► R2 ─► off-site ─► prune ─► (quarterly) DRILL
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| merge to `main` | CI builds + pushes `main-<sha7>` | BUILT | quality gates + gitleaks green | GHCR tags exist; nothing deployed |
| BUILT | `ops/deploy.sh` pull | PULLED | deploy lock held; tag matches scheme | old stack untouched (pull before swap) |
| PULLED | `migrate up` (01) | MIGRATED | expand/contract only; reversible migrations | DB schema advanced |
| MIGRATED | `compose up -d` | GATED | healthchecks pass in-container | new containers up behind Nginx |
| GATED | `/readyz` 200 ≤ 120 s + smoke green | SERVING | BR-003 | release log entry; traffic on new tags |
| GATED | gate red / smoke red | ABORTED → rollback path | automatic script exit ≠ 0 | incident entry; old containers serving |
| SERVING | `ops/rollback.sh` | SERVING (prev tag) | previous tag exists in release log | redeploy < 5 min (drill-timed) |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| Web landing + Command Center (prod) | Next standalone container behind Nginx; static assets cache-immutable at Nginx | App-level caching owned by 07 (Next cache/TanStack), not by 15 | — |
| api REST/WS | Container; no page caching; `/healthz` `/readyz` are `no-store` (01) | Redis is an app cache (01/05), not an ops concern | — |
| Maintenance page | Static file served by Nginx on flag; `no-store` so recovery is instant | none | — |
| Backup artifacts | Object storage only (R2, versioned + off-site copy) | none | — |

## 5. Configuration — the two lists

| Owner can change (host `.env` + runbook step — no admin UI in pilot) | Fixed in code |
| --- | --- |
| Deployed image tags per env (release log) | Memory caps (api 1.5g / web 1g / redis 512m) + restart policies |
| `APP_ENV`, `LOG_LEVEL`, feature env values from module `.env.example`s | Healthcheck paths/intervals; `/readyz` gate timeout (120 s) |
| Maintenance flag (Nginx file + `NEXT_PUBLIC_MAINTENANCE_MODE` build input) | `127.0.0.1`-only port bindings; GHCR tag scheme `main-<sha7>` |
| Backup schedule (cron) + retention counts; uptime checker contacts | Backup artifact naming + checksum format; prune policy |
| Ops alert routing (email/Telegram) | `ops.*` string keys (bn/en copy editable in `packages/shared` only) |

**Environment matrix**

| | dev (local) | pilot | prod |
| --- | --- | --- | --- |
| Compose project | `kushol-dev` (or bare `go run`/`next dev`) | `kushol-pilot` | `kushol-prod` |
| Database | Neon dev branch | Neon (pilot DB on free tier) | Neon prod DB — upgrade decision at trigger (01 §9 Q1 / 15 §9 Q4) |
| Media | R2 dev bucket (or MinIO *locally only* for offline dev) | R2 | R2 (versioning on) |
| TLS/domain | none (localhost) | `api.`/`web.` LE certs | same hosts, stricter headers |
| App channel | `development` | `preview` (APK, internal) | `production` (AAB/APK + TestFlight) |
| Monitoring | manual | uptime checker on | uptime checker + weekly ops review |

## 6. Security

Entry points and their rules (none touch product data — **tenant scope: N/A, no DB tables owned**; backups carry tenant data and are protected as below):

| Entry point | Rule |
| --- | --- |
| SSH | Key-only, non-root deploy user, fail2ban (HestiaCP); no password auth |
| 80/443 (HestiaCP Nginx) | TLS via Let's Encrypt (auto-renew); HSTS; security headers set at the proxy (04 §9 OPS-FE-002); WS upgrade only for the api gateway path |
| Containers | Bound to `127.0.0.1`; never published; non-root images; read-only capability set by default |
| GHCR | CI pushes with `GITHUB_TOKEN`; VPS pulls with a read-only token stored in host `.env` (BR-002) |
| Secrets | Host `.env` chmod 600 root-owned; rotation runbook (US-010) with per-credential order; CI masking verified (OPS-IT-003); backups are private-bucket objects over TLS, never presigned |
| Supply chain | Pinned base images by digest in CI; gitleaks on every merge; dependabot-style bumps reviewed |

## 7. Accessibility & Motion

No product UI in this module. The two user-facing surfaces — the static maintenance page and the maintenance banner — follow the platform rules: bn (default) + en copy from `packages/shared` `ops.*`, WCAG AA contrast on paper background, correct `lang` attribute per language, `role="status"` banner announcement, and static/instant rendering (no animation dependency). Details in 04 §2/§5/§7.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Neon cold start (free tier, ~hundreds of ms) | `/readyz` blips red; 503 problems | Seconds of degraded API; no hang | Tolerated by design; readyz green after warm-up (01 contract) |
| 2 | Neon hard outage | uptime checker + readyz red | api serves 503 problem envelope (bn/en); web static landing + maintenance page stay up | Incident runbook; RPO = last nightly dump (≤ 24 h) or Neon PITR (paid); jobs QUEUED resume |
| 3 | VPS reboot / crash | uptime checker; absent heartbeats | Full kushol outage; off-box data safe (Neon/R2) | Restart policies + healthchecks self-heal; DR path = fresh box + Hestia + restore scripts + DNS (runbook) |
| 4 | Failed deploy (gate or smoke red) | `ops/deploy.sh` exit ≠ 0 | None — old tags still serving | Abort before swap; if swapped, `ops/rollback.sh` < 5 min; incident entry |
| 5 | Redis container down | in-container healthcheck + readyz red | Degraded presence/limits (01 fallbacks); readyz red | `restart: unless-stopped` + go-redis reconnect; alarm if flapping |
| 6 | R2 unavailable | api error rates; backup job failure alarm | Media/receipts degraded (05/08/12); nightly backup fails | Retry with backoff; backup re-run; media features recover automatically |
| 7 | GHCR unreachable | deploy script pull error | Deployments blocked; running version unaffected | Retry/backoff; publish/repull when registry returns |
| 8 | Disk near-full on VPS | backup pre-flight guard + weekly review | Backups abort (safe); logs bounded by rotation | Prune per retention; enlarge/inspect; alarm stays until resolved |
| 9 | Cert renewal failure | HestiaCP alert + uptime TLS check | Old cert serves until expiry | Manual renew runbook; re-apply template if panel upgrade touched it |

## 9. Performance

- Deploy ≤ 5 min wall-clock (pull + migrate + gate + smoke); rollback ≤ 5 min operator time (drill-timed, US-004).
- Images: api distroless/alpine target < 40 MB; web standalone < 250 MB — small pulls keep deploys fast on the shared line.
- Gate: poll `/readyz` every 2 s up to 120 s (covers Neon cold start + boot); smoke ≤ 30 s.
- Resource budget on the 8 GB shared host: HestiaCP + 2 co-tenant apps ≈ 5 GB; Kushol capped ≈ 3 GB (api 1.5g / web 1g / redis 512m — 15 §9 Q5).
- Nginx: gzip/brotli + immutable static caching on the landing page (CWV budgets verified by Lighthouse CI, OPS-FE-003); proxy buffers tuned for WS.
- Backups at 02:30 Asia/Dhaka (off-peak); dump duration recorded; alarm if > 30 min.

## 10. Alternatives Considered

### Option A — Docker Compose · Option B — systemd units per process

| | A: Compose | B: systemd units |
| --- | --- | --- |
| Advantages | One file declares api+web+redis, mem caps, healthchecks, env profiles; matches `tech-stack.md`; local dev parity | Slightly lighter; host-native logging/journald |
| Disadvantages | Docker Engine on a shared panel host | Hand-written per-service units; no portable env/profile story; drift from docs |
| Complexity / weight | Low, declarative, one artifact to review | Low weight, higher maintenance spread |

### Option A — Neon off-box (chosen) · Option B — self-hosted Postgres in Compose

| | A: Neon (ap-southeast-1) | B: Compose Postgres on VPS |
| --- | --- | --- |
| Advantages | Managed backups/PITR path, branches fit the migration workflow, zero RAM/CPU on the 2-vCPU shared host, free tier to start | No network hop; no vendor limits; full control |
| Disadvantages | Cold starts; free-tier compute-hour/connection limits; region latency | Eats the shared host's RAM/CPU; backup/restore becomes fully ours; one more stateful container to operate |
| Complexity / weight | Lowest ops weight for a small team | Higher — stateful service on a contested host |

**Recommendation:** A — already decided and binding: `tech-stack.md` §Infrastructure ("Postgres off-box on Neon… move back to a Compose container when real school traffic starts", decision 2026-09-29). This module implements that decision and documents the revisit trigger (15 §9 Q4). ADR lives in the README "Blocked before build" row 15 + `tech-stack.md`.

### Option A — GHCR · Option B — Docker Hub

| | A: GHCR | B: Docker Hub |
| --- | --- | --- |
| Advantages | Same provider as CI; `GITHUB_TOKEN` push; private images free in the needed volume; provenance near the code | Widely cached; familiar |
| Disadvantages | Pull token management on the VPS | Separate account/creds; rate limits on anonymous pulls |
| Complexity / weight | Low | Low but extra credential surface |

### Option A — HestiaCP proxy templates · Option B — hand-managed Nginx conf

| | A: HestiaCP templates (chosen) | B: hand-managed Nginx |
| --- | --- | --- |
| Advantages | Panel keeps TLS renewal, firewall, fail2ban coherent for all 3 apps on the box; templates versioned in repo | Total control; no panel interactions |
| Disadvantages | Panel upgrades can touch generated conf — templates must be re-applied/diffed (runbook) | Easy to conflict with HestiaCP's regenerated confs; TLS renewal wiring becomes manual |
| Complexity / weight | Low, one custom template pair (`api.`, `web.`) | Medium, hidden coupling |

**Recommendation:** A in all four rows. **ADR:** record non-trivial deviations in this module's `07-progress.md` (or `docs/decisions/NNN-<slug>.md` if they affect other modules).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Shared host contention: 2 co-tenant apps can starve CPU/RAM | Latency spikes; OOM kills | Hard `mem_limit`s (INV-007), uptime + weekly `docker stats` review; escalation = separate VPS (trigger in `DEPLOYMENT.md`) |
| 2 | Neon free-tier limits (compute hours, cold starts, connection ceiling) | Refusals or pauses at pilot growth | Monitor usage; upgrade Neon or move Postgres into Compose at the documented trigger (15 §9 Q4) |
| 3 | Single-VPS SPOF accepted for pilot | Full outage until reprovision | Off-box data (Neon/R2) safe; DR runbook = fresh box + restore drill scripts; RPO ≤ 24 h; revisit at scale |
| 4 | ap-southeast-1 latency to Bangladesh users is acceptable | Slower API than ideal | Measure p95 from prod (01 logs); Neon region change is a config-level move if needed |
| 5 | EAS build quota/concurrency limits delay releases | App updates late | Documented local `eas build` fallback path (06 §8); priorities per channel |
| 6 | HestiaCP upgrades regenerate Nginx conf and clobber custom templates | Broken proxy/TLS for kushol vhosts | Templates versioned in repo; post-upgrade diff + re-apply step in the runbook |
| 7 | Restore drills drift from prod schema reality | DR fails when actually needed | Quarterly drill (§3 lifecycle) against the latest prod dump; drill evidence filed (US-009) |
| 8 | Compose/Neon/R2 changes outpace `DEPLOYMENT.md` | Operators follow stale docs | Docs updated in the same commit as behaviour (`prompt.txt` §12 discipline); walkthrough check in Part B exit |
