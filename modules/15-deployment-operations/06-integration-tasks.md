# Deployment & Operations — Integration Tasks

**Module:** `15-deployment-operations` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

This module's boundary crossings are infrastructure surfaces (registry, host, cloud services, CI), not
service calls. Every script, registry and external dependency is declared here — nothing may exist in
`ops/`, `deploy/` or CI unless it is in this file (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `01-foundations` | we call them | `GET /healthz` (uptime + container healthcheck) and `GET /readyz` (deploy gate) — the 01 contract verbatim | fatal to a deploy (gate red); degraded to users (503 envelope, bn/en) |
| I-2 | `01-foundations` | they call us | we host Redis: their `REDIS_URL` points at the Compose redis (loopback); golang-migrate entrypoint invoked by `ops/deploy.sh` | degraded — 01 fallbacks apply; readyz red |
| I-3 | `06-notifications` | they call us | production FCM credentials wired into host env (`FCM_SERVER_KEY`); 06 runs the post-cutover test push | degraded — pushes silent in prod until cutover signed |
| I-4 | `12-payments` | they call us | sandbox→production key cutover: `BKASH_*`/`NAGAD_*`/`SSLCOMMERZ_*` env swap + webhook URL registration (12 shipped on sandbox per its default) | degraded — payments disabled in pilot until cutover |
| I-5 | `02-design-system` · `03-identity-access` | they call us | EAS Build/Submit consumes 02 icon/splash assets + 03 credentials/wiring patterns; `EXPO_TOKEN` in CI | degraded — app releases blocked until wired |
| I-6 | GHCR (external) | we call | CI `docker push` (`GITHUB_TOKEN`); VPS `docker pull` (read-only token in host `.env`) | fatal to deploys; running services unaffected (INV-001: never built on VPS) |
| I-7 | VPS SSH + HestiaCP | we manage | key-only SSH, non-root deploy user, custom proxy templates (`api.`/`web.`), firewall/fail2ban, LE certs | fatal — full stack down; DR path via restore runbook |
| I-8 | Neon (external) | we call | console (DB/branch provisioning, operator) + `pg_dump` wire via `DATABASE_URL`; api's runtime path stays owned by 01 | degraded — api 503 envelope (01); backup job fails + alarm |
| I-9 | R2 (external) | we call | S3 API: backup upload + off-site `rclone` copy with `R2_BACKUP_*` ops creds; app media creds (`R2_*`) are wired env-only | degraded — media/receipts degraded (05/08/12); backups fail + alarm |
| I-10 | EAS (expo.dev, external) | we call | CLI build/submit/update in CI with `EXPO_TOKEN` | degraded — documented local `eas build` fallback |
| I-11 | External uptime checker | it calls us | HTTPS `GET /healthz` (60 s) + `/readyz` (5 min) from off-box | degraded — alerting lost only (provider `TODO: Confirm`) |

## 2. Exported Contract

```text
ops/deploy.sh   <env> [tag]     # lock → pull exact tags → migrate up → compose up -d → /readyz gate ≤120s → smoke → release-log line
ops/rollback.sh <env>           # previous tag from release log → redeploy + gate, < 5 min
ops/backup.sh                   # pg_dump -Fc → .sha256 → R2 (versioned) → off-site rclone → prune
ops/restore.sh  <artifact> <target>   # checksum verify → restore → row-count sanity → api smoke (drill/DR)
make deploy|rollback|backup|restore-drill|smoke|images    # thin wrappers
DEPLOYMENT.md + runbooks        # deploy · rollback · backup · restore · secret rotation · incident log template
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `ops/deploy.sh <env> [tag]` | operator; documented for CI rescue | exit 0 + release-log line on SERVING | lock held / pull fail / gate red / smoke red | the only sanctioned deploy path (BR-003); cron-safe, non-interactive |
| `ops/rollback.sh <env>` | operator | previous tag SERVING < 5 min | unknown/absent previous tag | tags immutable (BR-005); drill-timed |
| `ops/backup.sh` | cron + operator | artifact + `.sha256` in R2 + off-site copy + backup-log line | lock/low-disk skip; upload failure alarm | BR-006/007; retention per 15 §9 Q2/Q3 |
| `ops/restore.sh <artifact> <target>` | operator (drill/DR) | restored target + verification report | checksum mismatch aborts | target is always explicit — never implicitly prod |
| `DEPLOYMENT.md` + runbooks | whole team, new operators | English procedures (US-010/012) | — | the module's deliverable doc; updated with behaviour in the same commit |
| Health-endpoint usage doc | uptime checker; gate | — | — | contracts owned by 01; 15 only documents/uses them |

Rules: script CLIs are additive-first (new flags optional, defaults stable); documented exit codes;
machine output on stdout, human progress on stderr; no prompts; every script safe to re-run.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `/healthz` + `/readyz` | 01 | gate blocks deploy (BR-003); uptime alarms; never reimplemented or proxied |
| Config-module env names (api/web `.env.example` parity) | 01 | deploy refuses incomplete env (OPS-UT-002) |
| golang-migrate entrypoint + expand/contract discipline | 01 | migrate failure aborts deploy before swap |
| `jobs` queue depth/DEAD metrics (01 metrics/readyz detail) | 01 | incident-log note only — no auto-action in pilot |
| FCM prod credential shape + test push | 06 | cutover stays unsigned; pushes degraded (I-3) |
| Gateway prod key list + webhook URLs | 12 | cutover step open; payments disabled (I-4) |
| App icon/splash + EAS wiring patterns | 02 · 03 | build profiles incomplete; releases blocked (I-5) |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| None — infrastructure module: no cached reads and no revalidation surface. Maintenance flag = Nginx file + build-time env; health endpoints are `no-store` (01) | — |

| Read | Tagged with |
| --- | --- |
| None — no cached reads | — |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| GHCR | OCI registry (push/pull) | `GITHUB_TOKEN` (CI push) · RO pull token in host `.env` | pull 120 s | 3× backoff, then abort | deploys blocked; running stack unaffected |
| Neon | PostgreSQL wire (TLS) + console | `DATABASE_URL` (host env only) · console creds (operator) | dump cap 30 min | 1 retry, then skip + alarm | api 503 envelope (01); backup failure alarm; incident path |
| R2 | S3-compatible API (TLS) | `R2_*` (apps, env-only) · `R2_BACKUP_*` (ops, 15-held) | 60 s/op | 3× backoff; off-site copy independent | media/receipts degraded (05/08/12); backups fail + alarm |
| EAS | HTTPS CLI (build/submit/update) | `EXPO_TOKEN` (CI secret) | async queue | re-run; local build fallback | releases delayed; documented manual path |
| Uptime checker | HTTPS GET (off-box) | none (public health endpoints) | 10 s | continuous | alerting lost only; secondary check `TODO: Confirm` |
| Let's Encrypt (via HestiaCP) | ACME | panel-managed | n/a | auto-retry + manual runbook | old cert serves until expiry |
| bKash/Nagad/SSLCommerz prod | owned by 12 at runtime; 15 wires env + webhook URLs only | gateway dashboards (operator-held) | n/a | n/a | payments disabled until cutover (I-4) |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Maintenance page (Nginx static, 04 §2.1) | none — fully static | bn/en copy baked from `packages/shared` `ops.maintenance.*`; served on flag, `no-store` |
| Maintenance banner (web, 04 §2.2) | none — build-time env `NEXT_PUBLIC_MAINTENANCE_MODE` | `ops.maintenance.banner` bn/en; build-time catalog check |
| App build channels (05 §4) | `EXPO_PUBLIC_API_URL` baked per EAS profile | dev / preview / prod API URLs; no runtime ops calls |
| Status communication | no product UI — operator notifies school admins per the incident runbook template | incident log entry (English) + user-facing message in bn/en if shipped via notices (06/07 own the channel) |

## 7. Contract Stability

- Script CLIs: additive-first — new flags optional, existing defaults never change silently; exit codes
  documented in `DEPLOYMENT.md`; breaking CLI changes require a runbook version bump in the same commit.
- Image tag scheme `main-<sha7>` (+ `latest`) is stable; tags immutable once pushed (BR-005).
- `.env.example` keys change only together with the 01 config modules (same commit) — parity is
  CI-enforced (OPS-UT-002).
- Health endpoint contracts are owned by 01 and consumed read-only here; 15 never wraps or reshapes them.
- `DEPLOYMENT.md` and runbooks are versioned in-repo and updated in the same commit as the behaviour
  they describe (`prompt.txt` §12 discipline).
- EAS profile renames are breaking: add the new profile, migrate consumers, deprecate the old one with
  a window — never rename in place.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| GHCR unreachable | Running stack unaffected; local dev continues | Nothing (deploys blocked, operator-facing) | Retry/backoff; publish + pull when registry returns |
| Neon down (hard) | Nginx/TLS; web static landing; maintenance page; uptime detection | api 503 `problem+json` (bn/en) via 01; banner optional via flag | Incident runbook; restore from nightly dump if data loss (RPO ≤ 24 h; PITR on paid Neon); QUEUED jobs resume |
| R2 down | api core, chat text, in-app notices | Media upload/view, PDF receipts degraded (05/08/12); backup job fails + alarm | Retry with backoff; re-run backup; auto-recovers on R2 return |
| EAS quota/outage | Local development; web deploys | Store/OTA app releases delayed | Documented local `eas build` path (never the VPS — BR-001); re-run when quota resets |
| Redis container down | REST + auth paths; web | Degraded presence/rate-limits (01 fallbacks); `/readyz` red | `restart` policy + go-redis reconnect; alarm if flapping |
| VPS down | All off-box data safe (Neon/R2) | Full kushol outage | DR runbook: fresh box → HestiaCP → restore scripts → DNS; pilot accepts single-VPS SPOF (02 §11 risk 3) |
| Uptime checker down | Everything | No alerts only | Secondary check `TODO: Confirm` (15 §9 Q1); weekly manual review backstop |
| Let's Encrypt renewal fails | HTTP may work; TLS warns | Browser certificate warning | Manual renew runbook (02 §8 #9); re-apply template after panel upgrades |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `OPS-UT-001` | Backup script: artifact naming, checksum generation, exit codes, prune selection, dry-run | Unit | 03 §6 artifact contract; 15 §6 validation rows |
| `OPS-UT-002` | `.env.example` parity with 01 config modules per deployable | Unit (CI) | US-005; FND-BR-002 seam |
| `OPS-IT-001` | Deploy dry-run on a fresh Compose stack (testcontainers/local docker): pull → migrate → healthy → `/readyz` 200 → smoke green | Integration | US-001/003; INV-003/004/007; I-1/I-6 |
| `OPS-IT-002` | Restore drill on scratch DB: checksum match → restore → row-count sanity → api green on scratch | Integration | US-009; BR-007; I-8/I-9 |
| `OPS-IT-003` | Secret hygiene: gitleaks clean; CI logs sampled contain no unmasked secrets; host `.env` perms `600` | Integration (CI + host) | US-005; BR-002 |
| `OPS-E2E-001` | Post-deploy smoke, automated through the real front door: `/healthz` 200 + landing 200 + login round-trip | E2E (Playwright; APK smoke = OPS-AP-005) | US-003; the deploy is "done" only when green |

## 10. Task Checklist

- [ ] `OPS-INT-001` — GHCR publish workflow live + pull path proven on the VPS (OPS-IT-001 green)
- [ ] `OPS-INT-002` — deploy gate consuming `/readyz` + smoke scripted and drill-timed (OPS-E2E-001)
- [ ] `OPS-INT-003` — backup → R2 → off-site chain + alarms wired; drill evidence filed (OPS-IT-002)
- [ ] `OPS-INT-004` — FCM prod + gateway prod cutover executed and logged with 06/12 sign-off (I-3/I-4)
- [ ] `OPS-INT-005` — EAS pipelines + OTA channels wired in CI (`EXPO_TOKEN` secret; OPS-AP-001…006)
- [ ] `OPS-INT-006` — `DEPLOYMENT.md` + runbooks published; pilot checklist signed for 2–3 schools
