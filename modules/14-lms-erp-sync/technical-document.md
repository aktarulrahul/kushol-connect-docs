# LMS/ERP Sync — Technical Document

**Module:** `14-lms-erp-sync`
**Version:** 0.1
**Status:** 📝 Draft 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-10-03

Single engineer-facing reference compressing this module's spec set (`01`–`06`). When this file
drifts, the spec files win. LMS pull + Institution terminology: `vendor-lms-api-spec.md`,
`vendor-lms-api-response-examples.md` (shareable GET samples), `lms-pull-integration-plan.md`,
`terminology-institution.md`.

---

## 1. Overview

### 1.1 Purpose

Gives **Institution Admins** ways to keep the platform roster in step with an **educational
institution’s** systems (`brd.md` §4, PRD §3): CSV/Excel upload, inbound HMAC webhooks, and
**(planned)** LMS **pull** connector (base URL + token/key, schedule / Sync now → teachers,
students, classes-with-sections, section membership ids, optional notices → section groups with
teacher admin). Idempotent; licence-gated
(`brd.md` §7). Org noun + `institution_type` enum: `terminology-institution.md` (binding 2026-10-03).

### 1.2 Scope

**In:** portal-generated roster template (fixed English machine headers + bn/en instruction sheet,
sections pre-filled); self-serve CSV/Excel upload (`dry_run=true|false`, async > 500 rows via 01
jobs); dry-run report (row-level errors + error CSV); commit in chunks of 500 (users via 03 —
created users PENDING, never auto-verified; enrollments via 04) with totals + reconciliation
summary; content-hash + event-id idempotency; ERP webhook endpoints (register with show-once
secret, test event, versioned rotation with overlap, revoke, delivery log, redrive P1); inbound
webhook ingestion — unauthenticated-but-HMAC-signed (documented exception, module 12 pattern):
HMAC-SHA256, ±5-min window, 60 events/min/school; monthly reconciliation report; bn/en i18n
(`sync.*`, `validation.*`).

**Out:** verification decisions (03 owns; `verification_requests` never written here);
enrollment/group/topic application internals (the 04/05/06 chain — 14 calls 04 exports only);
pushing Kushol chat data **into** the institution LMS (roster **pull** is planned — see
`lms-pull-integration-plan.md`); fee/payment/ads/marketplace sync (modules 12/13/10/11);
mTLS/OAuth webhook auth (HMAC chosen); interactive OAuth for LMS; mobile app screens (web-only).
Full path/DB/role/`school-*` FCM topic renames to Institution wording are **deferred** (terminology §5).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 03 identity-access | exported user upsert consumed as `users.UpsertRosterUser` (declared in 03 `06` §2); PENDING/VERIFIED semantics |
| consumes | 04 organization-hierarchy | `hierarchy.CreateEnrollments(batch, source="ROSTER")` + `hierarchy.GetSection`; verified-user group/topic chain (04/05/06) untouched by 14 |
| consumes | 05 media | presigned upload + confirm (`media_assets`) for roster files |
| consumes | 01 foundations | `jobs.Enqueue`/`jobs.Register` (in-DB jobs, no Kafka), `audit.Record`, RFC-7807 envelope, rate-limit middleware |
| consumes | 07 command-center-web + shared | `/school/roster` + `/school/integrations` nav stubs (14 fills both); `sync.*`/`validation.*` bn + en catalogs |
| consumed by | None at launch — inbound-only: schools' LMS/ERP systems POST HMAC-signed events to `POST /api/v1/webhooks/erp/{schoolId}` (external counterparty I-6) |
| consumed by (future) | bulk features via `sync.IngestRosterBatch` (none at launch; frozen at v0 semantics) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go · chi handlers · services · tenant-scoped repos · sqlc + pgx · PostgreSQL | Import pipeline, endpoint lifecycle, webhook core | Stack per `docs/tech-stack.md` api table; contracts generated from `applications/api/openapi/openapi.yaml`; testcontainers-go IT |
| api (webhook auth) | Go stdlib crypto — HMAC-SHA256, constant-time compare (`hmac.Equal`) | Per-school versioned secrets, `X-Kushol-*` headers, ±5-min replay window | `tech-stack.md` (custom Go auth / webhook signature verification pattern of module 12) |
| api (parse) | Streaming CSV parse (row-by-row, no full-file load); XLSX via streaming sheet reader (P1) | 10k-row files must never load whole into memory on the 2-vCPU VPS | CSV P0, XLSX behind the same `format` column (02 §10) |
| api (jobs) | In-DB job table + 01 Go worker | `roster.import.process`, `roster.import.commit`, `erp.test.dispatch` | `tech-stack.md`: no Kafka/RabbitMQ |
| web | Next.js App Router · Server Components + TanStack Query (poll 3 s) · RHF + zod | Roster wizard, integrations screens, reconciliation report | `tech-stack.md` web table; CSV parse server-side, XLSX generation in Go — no bundle-heavy libs |
| web + app (per app) | each app's `src/i18n` `sync.*` + `validation.*` catalogs | bn (default) + en UI; CSV headers stay English-only machine format | Parity gate from module 02 |
| app | None — README scopes module 14 to `api` + `web` | School Admin surfaces are portal web-only; students experience only the effects via the 04/05/06 chain | `05-app-tasks.md`: `LMS-AP-*` empty by design |

---

## 3. Architecture

### 3.1 Component diagram

```text
web (Next.js: /school/roster, /school/roster/new, /school/roster/imports/[id],
     /school/integrations, /school/roster/reconciliation)
        │  generated openapi-fetch client
        ▼
api (chi handlers) ── sync services ── tenant-scoped repos ── sqlc ── PostgreSQL
        │                               (roster_imports, roster_import_rows,
        │                                erp_endpoints, erp_sync_events)
        ├─ calls 03: users.UpsertRosterUser (additive; create PENDING, never auto-verify)
        ├─ calls 04: hierarchy.GetSection · CreateEnrollments(batch, "ROSTER")
        ├─ calls 05: media_assets presign/confirm (file bytes in R2)
        ├─ uses 01: jobs (process/commit/test) · audit.Record · RFC-7807 · rate limits
 schools' LMS/ERP ──HTTPS POST /api/v1/webhooks/erp/{schoolId}──► webhook middleware
        (X-Kushol-Signature / -Timestamp / -Event-Id; HMAC + ±5 min + 60/min/school + 1 MB cap)
```

### 3.2 Boundary

**Owns (tables / services):** `roster_imports`, `roster_import_rows`, `erp_endpoints`,
`erp_sync_events`; the template generator (built from live 04 sections); the HMAC verification +
apply pipeline; the reconciliation report query.

**Reads (via exported service functions only):** 03 user upsert (`users.UpsertRosterUser`);
04 `GetSection`/`CreateEnrollments`; 05 media presign/confirm; 01 jobs/audit/limiter; 07 shell +
nav stubs. Cache contract: see `06` §4 — tag `school:{id}:roster` invalidated on every mutation;
all admin reads fresh/no-store; nothing publicly cacheable.

### 3.3 Request / data flows

```text
1. Roster upload: School Admin downloads GET /school/roster/template (live 04 sections
   pre-filled, bn/en instructions, English headers) → wizard upload via 05 presign/confirm →
   POST /school/roster/imports (sha256 probe first: identical re-upload → 200 original import,
   no-op) → jobs.Enqueue(roster.import.process) → stream-parse + per-row validation (phone,
   section via 04, duplicates-in-file) → status ready (zero errors) / validated_with_errors
   (commit blocked) + row report (+ error CSV ?as=csv).
2. Commit: POST …/{id}/commit (status must be ready) → jobs.Enqueue(roster.import.commit) →
   chunks of 500, per-row tx: users.UpsertRosterUser (phone match → update; no match → create
   PENDING) + hierarchy.CreateEnrollments → per-row result immutable, resume by processed_at
   cursor → totals created/updated/skipped/errored → audit; verified users' group/topic updates
   run via the existing 04/05/06 chain.
3. Inbound webhook: POST /webhooks/erp/{schoolId} → resolve ACTIVE endpoint by schoolId (fail
   closed; no ACTIVE row → INVALID_SIGNATURE-class rejection + security log) → constant-time
   HMAC compare (current, then previous within overlap) → ±5-min timestamp → event-id
   idempotency probe (endpoint_id, event_id) → duplicate returns original outcome →
   sync.ApplyErpEvent: 03 upsert + 04 enrollments in one per-event tx → log
   applied|rejected|duplicate|error (row always written; every rejection audit.Record-ed).
4. Reconcile: GET /school/roster/reconciliation → baseline = latest committed import vs platform ACTIVE
   counts per section (04) → drift flagged (extra|missing| mismatch); 5-min Redis memo of
   computed counts; no-import state returns baseline: null, not an error.
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `roster_imports` | uploaded, validating, ready, validated_with_errors, committing, committed, failed, cancelled | uploaded → validating (validation job starts; file confirmed in 05) · validating → ready (zero error rows) / validated_with_errors (any error; commit blocked, BR-003) · ready → committing (commit; licence flag; INV-004) · committing → committed (chunks done; totals) · uploaded/validating/ready → failed (bad headers, missing object, job retry exhaustion) · committing → cancelled (admin) |
| `erp_endpoints` | active, revoked | create → active (secret v1) · active → active (rotate: v+1 raw shown once, previous secret valid until `overlap_until`, default 24 h) · active → revoked (terminal; events thereafter rejected, BR-013) |
| `erp_sync_events` | received → applied, rejected, duplicate, error | received → applied / duplicate (HMAC + timestamp + event-id pass; duplicate = same id re-delivered) · received → rejected (signature/timestamp/endpoint) · applied path failure → error · error → applied (redrive re-runs `ApplyErpEvent` on stored payload; never applied twice) |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 (column detail stays there). Migrations 1–4, all reversible.
Seed: none — tests use clearly fictional fixtures ("Demo High School",
`https://erp.demo-high-school.example`).

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `roster_imports` | One uploaded file per school: format (csv\|xlsx), dry_run flag, lifecycle status, totals, `content_sha256` | `school_id` (FK → 04; tenant column) | `(school_id, content_sha256)` UNIQUE (idempotency probe), `(school_id, created_at DESC)`, `(school_id, status)` | `fail_reason_key` i18n key when failed |
| `roster_import_rows` | Per-row record: source payload (jsonb), result (`created\|updated\|skipped\|error`), `error_key`, `message` | via `import_id` → import's `school_id` | `(import_id, row_no)` UNIQUE, partial `(import_id) WHERE result='error'`, partial `WHERE processed_at IS NULL` (commit cursor) | results immutable once written (INV-003) |
| `erp_endpoints` | School's webhook identity: name, HTTPS url, `secret_version`, `secret_ciphertext` (never plaintext at rest), `previous_secret_ciphertext` + `overlap_until`, `last_success_at` | `school_id` (tenant column); webhook route resolves by `school_id` + `status='active'` (fail closed) | `(school_id, status)` | INV-005: raw secret persists nowhere but the one-time response |
| `erp_sync_events` | Every received event: endpoint ref, `event_id` (`X-Kushol-Event-Id`), type, payload, `signature_valid`, status, reject reason | via `endpoint_id` → endpoint's `school_id` | `(endpoint_id, event_id)` UNIQUE, `(endpoint_id, received_at DESC)`, `(endpoint_id, status)` | row always written — even rejections are security evidence |

---

## 5. Contracts

### 5.1 REST endpoints

All under `/api/v1`; RFC-7807 errors. Admin routes: authenticate → `SCHOOL_ADMIN` → tenant-scope.
Full shapes: `03` §2.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /school/roster/template` | School Admin (licence-gated) | CSV stream: fixed English headers + pre-filled sections + bn/en instruction rows | `FORBIDDEN` (licence off, BR-014) | LMS-US-001 |
| 2 | `POST /school/roster/imports` (multipart, `dry_run` default true) | School Admin | Store via 05, sha256 idempotency probe, enqueue process job; re-upload → 200 original | `VALIDATION_FAILED` (format/20 MB/10k rows) · 10 uploads/h/school | LMS-US-002 |
| 3 | `GET /school/roster/imports` · `GET …/imports/{id}` · `GET …/imports/{id}/rows?result=error` (+`?as=csv`) | School Admin | History, detail (totals, `fail_reason_key`), row-level report + error CSV | `TENANT_MISMATCH`/`NOT_FOUND` | LMS-US-003/012 |
| 4 | `POST /school/roster/imports/{id}/commit` | School Admin | 202 `committing`; enqueue commit job (chunks of 500) | `CONFLICT` (not `ready`) · 5/h/school | LMS-US-004 |
| 5 | `POST/GET /school/erp/endpoints` | School Admin | Register (raw secret in this one response only — ciphertext stored) / list (never the secret) | `FORBIDDEN` (licence) · POST 5/h/school | LMS-US-005 |
| 6 | `POST /school/erp/endpoints/{id}/rotate-secret` · `POST …/test` | School Admin | Versioned rotation (overlap ≤ 72 h, default 24) / signed test event with outcome | `CONFLICT` (revoked) · test 10/h, rotate 5/h | LMS-US-006/010 |
| 7 | `GET /school/erp/endpoints/{id}/events` (+ redrive `POST …/events/{eventId}/redrive`) | School Admin | Paged event log (type, status, time, reason) + one-click redrive of `error` rows | `TENANT_MISMATCH` | LMS-US-011 |
| 8 | `POST /webhooks/erp/{schoolId}` — **unauthenticated-but-HMAC-signed (documented exception, module 12 payment-webhook pattern)** | Schools' LMS/ERP (external; no session/JWT exists) | Verify (HMAC-SHA256 over `{timestamp}.{rawBody}`, ±5 min, UUID event id, body ≤ 1 MB) → apply via 03/04 in one tx; tenant = ACTIVE endpoint row resolved from `{schoolId}`, never client-claimable data | 403 `INVALID_SIGNATURE` (bad sig / unknown / revoked — indistinguishable on the wire, security-logged) · 400 `STALE_TIMESTAMP` · 400 `VALIDATION_FAILED` · 429 `RATE_LIMITED` + `Retry-After` (60/min/school) | LMS-US-007–009 |
| 9 | `GET /school/roster/reconciliation` | School Admin | Baseline vs platform counts per section, drift flagged; no-PII beyond section labels | `INTERNAL` (no-baseline state is 200 `baseline: null`) | LMS-US-012 |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `roster.import.process` (LMS-BE-020) | upload via `jobs.Enqueue` | Stream parse → per-row validation → row rows + totals → `ready`/`validated_with_errors`/`failed` | import detail + report UI | Idempotent (same `(import_id, row_no)` keys); retry ×5 backoff → `failed` + `fail_reason_key`; re-upload |
| `roster.import.commit` (LMS-BE-021) | commit via `jobs.Enqueue` | Chunks of 500, per-row tx (03 upsert + 04 enrollments); `processed_at` cursor | roster totals, 04/05/06 chain | Crash → 01 reaper requeues → resume at first unprocessed row; row failures recorded, never retried silently |
| `erp.test.dispatch` (LMS-BE-022) | test button (inline await, job for retry evidence) | Signed `test` payload POSTed to endpoint URL (5 s timeout) | School Admin feedback | Timeout/5xx surfaced; no state change |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `sync.IngestRosterBatch(rows []RosterRow, schoolId)` | future bulk features (none at launch; frozen at v0 semantics) | per-row results + totals DTO; same semantics as the CSV pipeline (phone-match → update / no-match → PENDING create, never auto-verify) | `VALIDATION_FAILED` (batch shape) |
| `sync.ApplyErpEvent(event ErpEvent)` | this module's webhook handler; redrive | `ApplyResult{status: applied\|duplicate\|error, appliedAt}`; per-event tx; `(endpoint_id, event_id)` probe first | `VALIDATION_FAILED`, `NOT_FOUND` |
| `sync.VerifyEndpointSecret(endpoint, timestamp, rawBody, signature)` | webhook middleware; reusable by module 12-pattern audits | `SecretCheckResult{ok, versionUsed, stale}` — constant-time HMAC-SHA256 vs current + overlap version | `INVALID_SIGNATURE` / `STALE_TIMESTAMP` |

Exports return DTOs (never sqlc rows); domain errors mapped to the problem envelope at the
handler; additive-first signature changes (`06` §2/§7).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/school/roster` | Roster home: summary cards (last import, active students, drift) + imports history table, polls 3 s while `validating`/`committing` (fills 07 stub §2.13 row 21) | Dynamic, fresh (no-store) | School Admin |
| `/school/roster/new` | Upload wizard: template → upload (05 presign flow, `dry_run` toggle default on) → dry-run report (error table + error CSV, hash no-op panel) → commit + summary | Dynamic | School Admin |
| `/school/roster/imports/[id]` | Import status + totals + error rows + error-CSV download + commit button (iff `ready`) | Dynamic | School Admin |
| `/school/integrations` | ERP webhook endpoints table (name · url · status · version · last success) + `SecretRevealModal` (show-once, bn+en warning, ack required) + test button + rotate dialog (overlap shown) + event-log drawer with redrive (replaces 07's `/school/integrations` stub; nav "ইন্টিগ্রেশন / Integrations") | Dynamic | School Admin |
| `/school/roster/reconciliation` | Baseline card (or explicit "no baseline") + platform counts + drift table (flags only, no auto-correction, no PII) | Dynamic, 5-min memo | School Admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| N/A — README scopes module 14 to `api` + `web`; no routes, no push topics, no app forms. Students/guardians/teachers experience the module only through its effects (enrollments, groups, topics applied by the 04/05/06 chain) | — | none produced by this module | none — the app neither uploads rosters nor manages endpoints |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Schools' LMS/ERP (inbound) | Live roster sync events (`student.upserted`, `enrollment.changed`, `staff.upserted`) | HTTPS POST → `/api/v1/webhooks/erp/{schoolId}`; HMAC-SHA256 headers `X-Kushol-Signature`/`-Timestamp`/`-Event-Id` | per-school versioned secret (AES-256-GCM encrypted in DB under `ERP_SECRET_KEY`) | 10 s server budget; caller retries are safe (event-id idempotency) | rejected per event (`INVALID_SIGNATURE`/`STALE_TIMESTAMP`/`RATE_LIMITED`); redrive; rate **60 events/min/school** (429 + `Retry-After`), body ≤ 1 MB |
| Schools' ERP (outbound test events only) | Prove the integration before live reliance | HTTPS POST from us to the registered URL, signed with the endpoint's secret | endpoint HMAC secret | 5 s, ×1 (outcome shown to admin) | failure is feedback, never a state change |
| R2 (via 05) | Roster file storage | indirect — presign/confirm only | 05-owned credentials | 05's | import `failed` (`sync.import.file_missing`) → re-upload |
| (none other at launch) | Outbound live sync is explicitly out of scope; FCM/DeepSeek/gateways/SMS belong to 06/08/12/03 (`06` §5) | — | — | — | — |

Operator-documented inbound limits: 60 events/min/school, 10 uploads/hour/school, template
downloads on the default class, webhook body cap 1 MB, upload cap 20 MB / 10,000 rows
(`TODO: Confirm`, OQ-1).

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `ERP_SECRET_KEY` | Yes (when 14 ships) | 32-byte key, base64 (generate with `openssl rand -base64 32`; never committed) | Encrypt/decrypt ERP webhook secrets (`LMS-INV-005`); parsed only by 01's config module. Other platform vars (DATABASE_URL, REDIS_URL, …) are inventoried in `15-deployment-operations` |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| ERP endpoint name + URL; revoke; rotate secret | HMAC scheme (SHA-256), header names `X-Kushol-*`, **replay window 5 min** |
| Per-school sync licence flag (Super Admin, via 07) | **Commit chunk size 500**; async threshold > 500 rows |
| (Future) import row ceiling per licence tier `TODO: Confirm` | **Max 10,000 rows / 20 MB** per file; CSV header set + order (`full_name,phone,role,class_level,section_name,session_year`) |
| — | Rate limit 60 events/min/school; rotation overlap window 24 h; webhook body cap 1 MB |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | Admin routes: authenticate → role claim `SCHOOL_ADMIN` → tenant-scope (`02` §6). Webhook route is the **documented exception**: unauthenticated-but-HMAC-signed — identity = valid HMAC over `{timestamp}.{rawBody}`; no session/JWT exists for ERP systems |
| Role matrix | School Admin: all `/school/roster/*`, `/school/erp/*`, `/school/roster/reconciliation` (licence-gated, BR-014) · Student/Guardian/Teacher/Vendor: no surface · Super Admin: owns the licence flag via 07, reads audit trails · Schools' LMS/ERP: the webhook route only |
| Tenant scope | Admin routes: school from JWT/session claim only, path ids joined to the claim; repository never accepts a caller-supplied `school_id` (INV-006). Webhook route: `{schoolId}` must resolve to an ACTIVE `erp_endpoints` row (BR-001/013); cross-references fail closed; foreign access → `TENANT_MISMATCH` |
| Rate limits | Webhook class 60 events/min/school (`RATE_LIMITED` + `Retry-After`); 10 uploads/h, 5 commits/h, 5 rotates/h, 10 tests/h per school; default class elsewhere |
| Audit events | Import uploaded + commit requested/completed (totals); endpoint registered/rotated/revoked; test dispatched; **every webhook rejection** (`audit.Record`, security log with `signature_valid=false` evidence) |
| Privacy / secrets | **Security-critical:** constant-time HMAC compare (BR-009); raw secret shown exactly once, stored AES-256-GCM encrypted under `ERP_SECRET_KEY` (INV-005; key rotation = re-encrypt job, ADR); versioned rotation with 24 h overlap; ±5-min replay window (BR-010); CSV/XLSX parsed as data only — formulas never executed; payload jsonb size-capped; secrets redacted in slog; ingestion never auto-verifies — created users PENDING, `verification_requests` never written (BR-005/INV-007) |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `INVALID_SIGNATURE` (403) | HMAC mismatch, missing signature, or unknown/revoked endpoint — indistinguishable on the wire | Webhook route; security-logged with the real cause | ERP fixes its secret/URL; endpoint row still usable; redrive/log shows reason |
| `STALE_TIMESTAMP` (400) | `X-Kushol-Timestamp` outside ±5 min (signature otherwise valid) | Webhook middleware (BR-010) | ERP re-signs with a fresh timestamp + new event id |
| `RATE_LIMITED` (429) | 61st event in a minute (or upload/commit/test ceilings) | Webhook + admin write routes (BR-012) | Honour `Retry-After`; event not logged `applied` |
| `VALIDATION_FAILED` | Bad headers/format/size/rows; bad event id or unknown event type; endpoint name/url rules | Upload + webhook + endpoint routes | Field errors mapped to `sync.import.*` / `sync.row.*` / `sync.endpoint.*` keys (bn default) |
| `CONFLICT` | Commit when not `ready` / already committing; test or rotate on revoked endpoint | Commit + endpoint routes | State hint in UI; refresh import status |
| `TENANT_MISMATCH` / `NOT_FOUND` | Cross-school access; unknown path ids | All admin routes | Branded 404, nothing leaked |

All errors surface as RFC-7807 `application/problem+json`; user-visible messages resolve via
each app's `src/i18n` — every `sync.*` key ships in **bn + en** (Bengali default; e.g.
`sync.secret.warning` show-once modal, `sync.import.hash_noop` panel). CSV headers and the webhook
wire contract stay English/machine-format by design (BR-008).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog via 01; secrets redacted; `erp_sync_events` is the per-endpoint delivery log (type, status, time, reject reason) — the log itself is the record, no separate audit on reads |
| Metrics / counters | Endpoint health (`last_success_at`, applied/duplicate/rejected/error GROUP BY) feeds 07's integrations table + module 15 alerting; import totals per school for 07 dashboard cards; security counters (rejected signatures, stale timestamps) — never cross-tenant visible |
| Health contribution | None new — DB/Redis coverage is 01's `/readyz`; no dedicated module dependency |
| Jobs & retries | 3 jobs (§5.2); commit resume by `processed_at` cursor + immutable row results — nothing half-applied; queued jobs survive restarts (01 reaper) |
| Runbook pointers | **Failed-event redrive**: School Admin re-drives `error` events from the event log after fixing the cause (e.g. section created later); ERP-side misconfiguration → test-event failure copy + rotate-with-overlap; degraded 03/04 → events survive as `error`, redrive recovers (`06` §8) |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Row error taxonomy (`sync.row.*` keys), fixed CSV header set + order, HMAC signer/verifier (constant-time, versions, overlap), ±5-min boundary values, import state guard, per-type payload validation | `LMS-UT-001`–`006` | `go test` green in CI |
| Integration | **HMAC valid / tampered (403 + security log) / replayed (`duplicate`, applied exactly once) / stale (±5 min)**; content-hash re-upload no-op (per-school hash scope); commit resumability (kill mid-chunk → resume, no double-apply); phone-match vs create-PENDING (`verification_requests` untouched); cross-tenant denial; 04 batch contract (pairs `ORG-IT-008`); rate-limit 61st event; redrive; auth chain + licence; reconciliation drift | `LMS-IT-001`–`012` | testcontainers Postgres; mandatory set in `03` §6 |
| E2E | WEB-LMS golden path: login → wizard → template → upload → dry-run report → commit → summary → history; axe-clean, bilingual | `LMS-E2E-001` | Playwright |
| CI | Always-include set: unauthenticated denial per protected entry point; validation rejects bad input; cross-tenant → `TENANT_MISMATCH`/404; **raw secrets never in logs, audit entries, or any GET response** | — | quality gate on `api` + `web` |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | ≤ 10,000 rows/file, one bulk import per school per term; hot path is webhooks (≤ 60/min/school at launch — trivial) |
| Hot paths + indexes | `(school_id, content_sha256)` UNIQUE idempotency probe; `(import_id, row_no)` + partial error/resume indexes; `(endpoint_id, event_id)` UNIQUE probe; `(school_id, status)` webhook resolution; `(endpoint_id, received_at DESC)` log paging |
| Latency targets | **Streaming parse** (CSV row-by-row; XLSX via streaming sheet reader — no full-file load); **chunked commits of 500** keep Neon round-trips and memory flat; per-row 03/04 exports dominate commit time — batches + resume make 10k rows a background concern, never request-time |
| Bundle / payload impact | No new web bundle-heavy libraries (CSV parsed server-side; XLSX generated in Go); existing table/polling stack only |
| Caching | Nothing publicly cacheable; admin reads no-store; reconciliation computed counts memoized 5 min in Redis (drift tolerance) |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the table to review in module readiness checks.
Unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Max rows (10,000?) and file size (20 MB?) per upload | Large schools need splits | Rahul | Open — `TODO: Confirm` | 10,000 rows / 20 MB (LMS-BR-007); future per-licence-tier ceiling |
| 2 | Secondary match key besides phone (email? student ID?) | Duplicate PENDING users if phones dirty | Rahul | Open — `TODO: Confirm` | Phone only (`01[3-9]\d{8}` normalized), strict row validation (LMS-BR-006) |
| 3 | CSV template shape; webhook auth scheme; event-id idempotency; 60/min rate ceiling | — | Rahul | Open (defaults accepted) | Exactly the spec defaults: portal-generated template with strict headers; per-school HMAC-SHA256 rotating secret + 5-min window + 24 h overlap; duplicates 200 `duplicate`; 429 + `Retry-After` |
| 4 | 03 must export `users.UpsertRosterUser` additively | Ingestion cannot create/update users without forking identity logic | Rahul | Resolved 2026-09-30 — declared in 03 `06` §2 | Additive signature agreed before build; fallback = blocking dependency |
| 5 | Phone numbers reliably present/normalized in rosters; schools' ERPs implement HMAC headers correctly | Match rate collapse; rejected-event churn | Rahul | Risk | Strict validation with row errors; test-event button + bn/en integration guide + event log with reject reasons |
| 6 | Verified-user group/topic updates lag imports (04/05/06 chain); licence-flag provisioning UX (07 tenants screen) | Admins expect instant groups; module unusable or ungated | Rahul | Risk / Open | Documented degradation — import completes, chain retries, never double-applied; licence flag ON for pilot schools, managed via 07 |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| `brd.md` §4 in-scope LMS/ERP sync (+ §6 security, §7 B2B licence hook; module rules LMS-BR-001–014) | §3 (Phase 2 basic migration · Phase 3 advanced sync) | `LMS-US-001`–`012` | `LMS-BE-001`–`022` · `LMS-FE-001`–`016` · `LMS-INT-001`–`010` (`LMS-AP-*` empty by design) | `LMS-UT-001`–`006` · `LMS-IT-001`–`012` · `LMS-E2E-001` |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: webhook secrets encrypted (AES-256-GCM, `ERP_SECRET_KEY`) instead of hashed — HMAC verification needs the raw secret; migrations re-versioned `20270301…`; routes `/school/roster/reconciliation` (was colliding with 12) and `/school/integrations`; consumes 03 `users.UpsertRosterUser` + `guardians.*` | Claude |
| 2026-10-03 | LMS pull plan + vendor API; binding Institution terminology (`institution_type`); FCM `school-*` rename deferred to 06 | Agent |
| 2026-10-04 | Built contract-first: 22 operations + 28 `Lms*` schemas; webhook route is the documented unauthenticated-but-HMAC exception (BR-009/INV-005: constant-time HMAC, ±5-min window, versioned AES-256-GCM secrets under `ERP_SECRET_KEY`, show-once raw); imports are always dry-run-first with content-hash no-op and chunked commits (03 upsert = PENDING creates only, 04 enrollments with ROSTER source); 3 migrations consolidate §1.2's four (registry `20270301090001–090003`) + licence flag + pull tables; pull connector = `VendorClient` port, interval schedule presets, single running sync per institution, `lms_external_ids` map, additive 04 export `EnsureExternalSection`; CSV P0 (xlsx rejected at upload); reconciliation = baseline vs ACTIVE counts with drift flags, no-store reads. App surface: N/A by design. Gaps: G-1…G-9 (IT harness, licence UI, withdrawal export, notices pull, xlsx, SSRF allowlist, Redis memo, e2e runs) | Kilo |
