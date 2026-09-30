# LMS/ERP Sync — Backend Tasks & Database Design

**Module:** `14-lms-erp-sync`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below is designed until the schema is settled. Every table states its
tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `roster_imports` (model `RosterImport`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK → 04 `schools`; **tenant column** |
| `uploaded_by` | `uuid` | no | — | FK → 03 `users` (School Admin) |
| `file_media_id` | `uuid` | no | — | FK → 05 `media_assets` (file bytes in R2) |
| `format` | `text` | no | — | `csv` \| `xlsx` (xlsx parsing P1) |
| `status` | `text` | no | `'uploaded'` | `uploaded\|validating\|validated_with_errors\|ready\|committing\|committed\|failed\|cancelled` |
| `dry_run` | `boolean` | no | `true` | Dry-run first (`LMS-BR-003`); commit allowed from `ready` |
| `total_rows` / `created_count` / `updated_count` / `skipped_count` / `errored_count` | `int` | no | `0` | Totals shown in the reconciliation summary (`LMS-US-004`) |
| `content_sha256` | `text` | no | — | SHA-256 of the file bytes; **unique per school** (`LMS-INV-001`) |
| `fail_reason_key` | `text` | yes | — | i18n key when status `failed` (e.g. headers invalid, file missing) |
| `committed_at` | `timestamptz` | yes | — | Set when the commit job finishes |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FKs; `CHECK` on `format`/`status`; UNIQUE `(school_id, content_sha256)`.
**Tenant scope:** all queries `WHERE school_id = claim.schoolId`.
**Indexes:** `(school_id, content_sha256)` UNIQUE → idempotency probe (`LMS-BR-002`); `(school_id, created_at DESC)` → history list; `(school_id, status)` → dashboard counters.

#### `roster_import_rows` (model `RosterImportRow`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `import_id` | `uuid` | no | — | FK → `roster_imports`; tenant via import |
| `row_no` | `int` | no | — | 1-based data-row number (stable reference in reports) |
| `payload` | `jsonb` | no | — | Parsed source row (name, phone, role, classLevel, sectionName, sessionYear) |
| `result` | `text` | yes | — | `created\|updated\|skipped\|error`; NULL until processed (commit cursor) |
| `error_key` | `text` | yes | — | i18n key (`sync.row.*`) when result `error` |
| `message` | `text` | yes | — | Human detail (locale-independent facts: section id, conflicting row no) |
| `processed_at` | `timestamptz` | yes | — | Commit-cursor checkpoint (resume after crash) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(import_id, row_no)`; `CHECK` on `result`.
**Tenant scope:** always joined to `roster_imports.school_id`.
**Indexes:** `(import_id, row_no)` → ordered report; partial `(import_id) WHERE result='error'` → error report; partial `(import_id) WHERE processed_at IS NULL` → commit resume scan.

#### `erp_endpoints` (model `ErpEndpoint`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK → 04 `schools`; **tenant column** |
| `name` | `text` | no | — | Display name, e.g. "Leading EDU ERP" |
| `url` | `text` | no | — | HTTPS callback for test events (`LMS-US-006`) |
| `secret_version` | `int` | no | `1` | Increments on rotate |
| `secret_ciphertext` | `bytea` | no | — | AES-256-GCM(nonce‖ciphertext) of the current HMAC secret under `ERP_SECRET_KEY`; decrypted in memory only to verify signatures (`LMS-INV-005`) |
| `previous_secret_ciphertext` | `bytea` | yes | — | Valid until `overlap_until` (graceful rotation) |
| `overlap_until` | `timestamptz` | yes | — | Expiry of the previous secret version |
| `status` | `text` | no | `'active'` | `active\|revoked` (`LMS-BR-013`) |
| `last_success_at` | `timestamptz` | yes | — | Bumped on each `applied` event |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FK; `CHECK` on `status`.
**Tenant scope:** admin routes by claim; webhook route resolves rows by `school_id` from the URL **and** `status='active'` (fail closed).
**Indexes:** `(school_id, status)` → webhook resolution + list; PK → event writes.

#### `erp_sync_events` (model `ErpSyncEvent`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `endpoint_id` | `uuid` | no | — | FK → `erp_endpoints`; tenant via endpoint |
| `event_id` | `uuid` | no | — | `X-Kushol-Event-Id` header (UUID); UNIQUE per endpoint (`LMS-INV-002`) |
| `type` | `text` | no | — | `student.upserted\|enrollment.changed\|staff.upserted` |
| `payload` | `jsonb` | no | — | Verified request body (redacted of secrets); re-drive input |
| `signature_valid` | `boolean` | no | `false` | Recorded even on rejection (security evidence) |
| `status` | `text` | no | — | `applied\|rejected\|duplicate\|error` |
| `reject_reason_key` | `text` | yes | — | `INVALID_SIGNATURE` / `STALE_TIMESTAMP` / `RATE_LIMITED` / `sync.row.*` |
| `received_at` | `timestamptz` | no | `now()` | Log ordering |

**Constraints:** UNIQUE `(endpoint_id, event_id)`; FK; `CHECK` on `type`/`status`.
**Tenant scope:** joined to `erp_endpoints.school_id`.
**Indexes:** `(endpoint_id, event_id)` UNIQUE → idempotency; `(endpoint_id, received_at DESC)` → event log paging; `(endpoint_id, status)` → redrive queue + health counters.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20270301090001_create_roster_imports` | ✅ |
| 2 | `20270301090002_create_roster_import_rows` | ✅ |
| 3 | `20270301090003_create_erp_endpoints` | ✅ |
| 4 | `20270301090004_create_erp_sync_events` | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| None — no seed rows. Tests use clearly fictional fixtures ("Demo High School", fictional ERP `https://erp.demo-high-school.example`) | `DRAFT` (fictional, test-only) | `prompt.txt` §12 |

---

## 2. Server Contracts

All routes live under `/api/v1`; errors use the shared RFC-7807 envelope. Admin routes:
authenticate → load role claims (`SCHOOL_ADMIN`) → tenant-scope. The webhook route is the
**documented exception**: unauthenticated-but-HMAC-signed (same pattern as module 12 payment
webhooks) — no session/JWT exists for ERP systems; the tenant comes from the verified ACTIVE
endpoint row, never from client-claimable data alone.

### `GET /api/v1/school/roster/template`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | none (school from claim); optional `?format=csv` |
| **Result** | `text/csv` stream — fixed English header row + pre-filled section rows (04 sections, current session) + instruction sheet rows (bn + en); `no-store` |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (licence off, `LMS-BR-014`) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | no |
| **Stories** | `LMS-US-001` |

### `POST /api/v1/school/roster/imports` (multipart upload; `dry_run=true|false`)

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | multipart: `file` (csv/xlsx ≤ 20 MB, magic-byte sniffed), `dry_run` bool (default true) |
| **Result** | 201 `{ "data": { import: { id, status: "uploaded", totals } } }`; identical-content re-upload → 200 with the existing import (no new job, `LMS-BR-002`); file stored via 05 presign/confirm, then `jobs.Enqueue("roster.import.process")` |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` (format/size/rows, `LMS-BR-007`) · `RATE_LIMITED` · `INTERNAL` |
| **Rate limit** | 10 uploads/hour/school |
| **Audit** | yes — import uploaded (dry_run flag recorded) |
| **Stories** | `LMS-US-002` |

### `GET /api/v1/school/roster/imports` · `GET /api/v1/school/roster/imports/{id}` · `GET /api/v1/school/roster/imports/{id}/rows?result=error`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope (import joined to claim) |
| **Input** | list: `page`, `pageSize` (≤ 100), `status?` · detail: path id · rows: `result?` filter (`error` default for the report), `page`, `pageSize` |
| **Result** | list `{ "data": [ { id, format, status, dryRun, totals, contentSha256?, createdAt } ], "page" }` · detail adds `failReasonKey`, `committedAt` · rows `{ "data": [ { rowNo, payload, result, errorKey, message } ] }` — error CSV variant served with `text/csv` content negotiation (`?as=csv`) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `TENANT_MISMATCH`/`NOT_FOUND` · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | no |
| **Stories** | `LMS-US-003`, `LMS-US-012` |

### `POST /api/v1/school/roster/imports/{id}/commit`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | no body; import must be `status=ready` (`LMS-INV-004`) |
| **Result** | 202 `{ "data": { import } }` — status `committing`; `jobs.Enqueue("roster.import.commit")` applies chunks of 500; final status/totals via the detail endpoint |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (licence) · `NOT_FOUND`/`TENANT_MISMATCH` · `CONFLICT` (status not `ready`, already committing/committed) · `INTERNAL` |
| **Rate limit** | 5/hour/school |
| **Audit** | yes — commit requested + commit completed (totals) |
| **Stories** | `LMS-US-004` |

### `POST /api/v1/school/erp/endpoints` · `GET /api/v1/school/erp/endpoints`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | POST `{ name, url }` — HTTPS-only URL; GET `page`, `pageSize` |
| **Result** | POST 201 `{ "data": { endpoint, secret, secretVersion: 1 } }` — **raw secret in this one response only** (ciphertext stored, `LMS-INV-005`) · GET `{ "data": [ { id, name, url, status, secretVersion, overlapUntil?, lastSuccessAt } ] }` — never the secret |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (licence) · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | POST 5/hour/school · GET default |
| **Audit** | yes — endpoint registered / (GET none) |
| **Stories** | `LMS-US-005` |

### `POST /api/v1/school/erp/endpoints/{id}/rotate-secret` · `POST /api/v1/school/erp/endpoints/{id}/test`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope (endpoint joined to claim) |
| **Input** | no bodies (rotate may accept `{ overlapHours? }` ≤ 72, default 24) |
| **Result** | rotate: `{ "data": { endpoint, secret, secretVersion: n+1, overlapUntil } }` — previous secret valid until `overlapUntil` (`LMS-US-010`) · test: `{ "data": { ok, httpStatus?, latencyMs?, errorKey? } }` — signed test payload POSTed to the endpoint URL, outcome returned (`LMS-US-006`) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND`/`TENANT_MISMATCH` · `CONFLICT` (revoked endpoint) · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | test 10/hour/school · rotate 5/hour/school |
| **Audit** | yes — both (secret version recorded, never secret material) |
| **Stories** | `LMS-US-006`, `LMS-US-010` |

### `GET /api/v1/school/erp/endpoints/{id}/events`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | `status?` (`applied\|rejected\|duplicate\|error`), `page`, `pageSize` |
| **Result** | `{ "data": [ { eventId, type, status, signatureValid, rejectReasonKey?, receivedAt } ], "page" }`; redrive is `POST` (see 06 §6) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND`/`TENANT_MISMATCH` · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | no (the log itself is the record) |
| **Stories** | `LMS-US-011` |

### `POST /api/v1/webhooks/erp/{schoolId}` — **unauthenticated, HMAC-signed (documented exception)**

| | |
| --- | --- |
| **Auth** | **No authenticate step — exception to the standard chain** (module 12 payment-webhook pattern): identity = valid HMAC over `{timestamp}.{rawBody}` with the school's versioned secret. Tenant = `{schoolId}` path param, which must resolve to an ACTIVE endpoint row; mismatch → reject before any parsing of the body |
| **Input** | headers `X-Kushol-Signature` (`sha256=<hex>`), `X-Kushol-Timestamp` (unix seconds, ±5 min), `X-Kushol-Event-Id` (UUID); body ≤ 1 MB: `{ type, data }` with `type ∈ student.upserted\|enrollment.changed\|staff.upserted` |
| **Result** | 200 `{ "data": { status: "applied"\|"duplicate", eventId } }` — applied runs `sync.ApplyErpEvent` (03 upsert + 04 enrollments) in one per-event transaction; duplicates return the original outcome, nothing re-applied (`LMS-BR-011`) |
| **Errors** | 403 `INVALID_SIGNATURE` (bad/missing signature, unknown/revoked endpoint — indistinguishable on the wire, security-logged with the real cause) · 400 `STALE_TIMESTAMP` (`LMS-BR-010`) · 400 `VALIDATION_FAILED` (bad event id/unknown type) · 429 `RATE_LIMITED` + `Retry-After` (60/min/school, `LMS-BR-012`) · 200 `applied` with per-part `error` recorded in the event row if 03/04 rejects the payload (never lost — redrive) |
| **Rate limit** | webhook class — 60/min/school |
| **Audit** | yes — every rejection (`audit.Record`, security log); `erp_sync_events` row always written |
| **Stories** | `LMS-US-007`–`LMS-US-009` |

### `GET /api/v1/school/roster/reconciliation`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | none (latest committed import is the baseline) |
| **Result** | `{ "data": { baseline: { importId, committedAt, totals }, platform: { perSection: [ { sectionId, classLevel, name, activeStudents } ], totalActive }, drift: [ { sectionId, kind: "extra"\|"missing"\|"mismatch", delta } ] } }` — counts only, no PII beyond section labels |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `INTERNAL` (no-import state returns `baseline: null` + platform counts) |
| **Rate limit** | default class |
| **Audit** | no |
| **Stories** | `LMS-US-012` |

### Web Server Action / Route Handler (Next.js)

All School Admin screens (04-frontend) call the endpoints above through the generated
`openapi-fetch` client via Route Handlers — never the database directly. Same auth + zod input
(mirrors `validation.*` / `sync.*` keys) + result rows apply there. The webhook endpoint is
api-only (ERP systems POST to `api.` directly; web is never in that path).

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `LMS-BE-001` | `GenerateTemplate(schoolId)` | Live 04 sections (current session) → fixed header set + bn/en instruction rows; English machine headers (`LMS-BR-008`) | — | no |
| `LMS-BE-002` | `CreateImport(schoolId, uploadedBy, mediaId, format, dryRun)` | sha256 probe first (`LMS-BR-002` — return existing); licence guard (`LMS-BR-014`); row ceiling ≤ 10,000 (`LMS-BR-007`); enqueue process job | `school:{id}:roster` | yes |
| `LMS-BE-003` | `ProcessImport(importId)` (job body) | Stream parse → per-row validation (phone, section via 04, duplicates-in-file) → row rows written; totals set; status `ready`/`validated_with_errors`/`failed` | `school:{id}:roster` | no |
| `LMS-BE-004` | `CommitImport(importId, actor)` | Status guard `ready` (`LMS-BR-003`); enqueue commit job; idempotent on re-click via status `committing` | `school:{id}:roster` | yes |
| `LMS-BE-005` | `runImportCommit(importId)` (job body) | Chunks of 500; per-row tx: `users.UpsertRosterUser` (03) + `hierarchy.CreateEnrollments` (04, `source=ROSTER`); per-row result immutable (`LMS-BR-004`); created users PENDING (`LMS-BR-005`); phone match (`LMS-BR-006`); resume by `processed_at` cursor | `school:{id}:roster` | yes (final totals) |
| `LMS-BE-006` | `ListImports` / `GetImport` / `ListImportRows` | Claim-scoped; error-report projection (`result=error`); CSV rendering of the error report | — | no |
| `LMS-BE-007` | `CreateEndpoint(schoolId, actor, name, url)` | Licence guard; HTTPS-only URL; generate 32-byte secret → return raw once, store encrypted v1 (`LMS-INV-005`) | `school:{id}:roster` | yes |
| `LMS-BE-008` | `RotateSecret(endpointId, actor, overlapHours)` | ACTIVE only; v+1 encrypted secret stored, previous kept until `overlapUntil`; raw returned once | `school:{id}:roster` | yes |
| `LMS-BE-009` | `RevokeEndpoint(endpointId, actor)` | ACTIVE → REVOKED (terminal); events thereafter rejected | `school:{id}:roster` | yes |
| `LMS-BE-010` | `SendTestEvent(endpointId, actor)` | ACTIVE only; sign `test` payload with current secret; POST to `endpoint.url` (5 s timeout); return outcome | — | yes |
| `LMS-BE-011` | `VerifyWebhookRequest(schoolId, headers, rawBody)` | Resolve ACTIVE endpoint by schoolId (fail closed); constant-time HMAC compare (current, then previous within overlap) — `INVALID_SIGNATURE`; ±5 min window — `STALE_TIMESTAMP`; 60/min/school limiter — `RATE_LIMITED` | — | yes (rejections) |
| `LMS-BE-012` | `ApplyErpEvent(endpoint, event)` | `(endpoint_id, event_id)` probe → `duplicate` (return original outcome, no re-apply, `LMS-BR-011`); per-type apply: upserts via 03, `enrollment.changed` resolves section via 04 then `CreateEnrollments`; failure → `error` row (redrive-able); success → `applied` + `last_success_at` | `school:{id}:roster` | no (event row is the record) |
| `LMS-BE-013` | `RedriveEvent(endpointId, eventId, actor)` | `error` rows only; re-run `ApplyErpEvent` with stored payload; result transitions to `applied`/`error` (fresh reason) | `school:{id}:roster` | yes |
| `LMS-BE-014` | `ListEndpointEvents` / `ListEndpoints` | Claim-scoped paging; health counters (status GROUP BY) | — | no |
| `LMS-BE-015` | `ReconciliationReport(schoolId)` | Baseline = latest `committed` import; platform counts from 04 (ACTIVE STUDENT enrollments per section); drift = per-section deltas; 5-min cache of the computed payload | — | no |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `LMS-BE-016` | `InsertImport` / `GetImportByContentHash` / `GetImport` / `ListImports` / `UpdateImportStatus` / `UpdateImportTotals` | `WHERE school_id=$claim`; hash probe `WHERE school_id=$1 AND content_sha256=$2`; status transitions guarded in `UPDATE … WHERE status=$expected` | `(school_id, content_sha256)` UNIQUE · `(school_id, created_at DESC)` |
| `LMS-BE-017` | `BulkInsertRows` / `ListRows` / `ListErrorRows` / `MarkRowProcessed` / `ListUnprocessedRows(limit)` | `WHERE import_id=$1` (join enforces tenant); cursor `WHERE import_id=$1 AND processed_at IS NULL ORDER BY row_no LIMIT $2` | `(import_id, row_no)` · partial `result='error'` · partial `processed_at IS NULL` |
| `LMS-BE-018` | `InsertEndpoint` / `ListEndpoints` / `GetEndpoint` / `GetActiveEndpointBySchool` / `UpdateEndpointSecrets` / `RevokeEndpoint` / `TouchLastSuccess` | resolution `WHERE school_id=$1 AND status='active'`; secret UPDATE rotates hash columns only | `(school_id, status)` |
| `LMS-BE-019` | `InsertEvent` (ON CONFLICT `(endpoint_id, event_id) DO NOTHING` + RETURN) / `GetEvent` / `ListEvents` / `UpdateEventStatus` / `CountEventsByStatus` | idempotent insert probe; log `ORDER BY received_at DESC`; redrive scan `WHERE endpoint_id=$1 AND status='error'` | `(endpoint_id, event_id)` UNIQUE · `(endpoint_id, received_at DESC)` · `(endpoint_id, status)` |

Every query is tenant-scoped at the repository layer (`LMS-BR-001`, `LMS-INV-006`) — no method
accepts a caller-supplied `school_id`; the webhook path resolves the school from the ACTIVE
endpoint row only.

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `LMS-BE-020` | `roster.import.process` worker | `POST /school/roster/imports` via 01 `jobs.Enqueue` | Yes — rows re-parsed into the same `(import_id, row_no)` keys; totals recomputed | Retry ×5 backoff → import `failed` + `fail_reason_key`; School Admin re-uploads |
| `LMS-BE-021` | `roster.import.commit` worker | `POST …/commit` via 01 `jobs.Enqueue` | Yes — `processed_at` cursor + immutable row results; chunks of 500 | Crash → reaper requeues → resume at first unprocessed row; row-level failures recorded, never retried silently (`LMS-BR-004`) |
| `LMS-BE-022` | `erp.test.dispatch` | `POST …/test` (inline await, job for retry evidence) | Yes — outcome logged per attempt | Timeout/5xx surfaced to the admin; no state change |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `LMS-UT-001` | Row-level error taxonomy: bad phone, unknown section, duplicate-in-file, bad role, over-long name → exact `sync.row.*` keys | Unit | §6 validation rules (`LMS-US-003`) |
| `LMS-UT-002` | CSV header validator: exact set + order; extra/missing/reordered columns rejected | Unit | `LMS-BR-008`, template fixed set |
| `LMS-UT-003` | HMAC signer/verifier: signature shape, constant-time compare, versioned secrets, overlap acceptance/expiry | Unit | `LMS-BR-009`, `LMS-US-010` |
| `LMS-UT-004` | Timestamp window: ±5 min boundary values → accept/stale | Unit | `LMS-BR-010` |
| `LMS-UT-005` | Import state guard: only `ready` commits; illegal transitions `CONFLICT` | Unit | `LMS-INV-004` |
| `LMS-UT-006` | Payload validation per event type (required fields, UUID event id) | Unit | webhook contract |
| `LMS-IT-001` | Webhook HMAC: valid → `applied`; tampered → 403 `INVALID_SIGNATURE` + security log; wrong-secret (post-overlap v1) → rejected | Integration (testcontainers Postgres) | `LMS-US-007`, `LMS-US-009` |
| `LMS-IT-002` | Replayed event id → 200 `duplicate`, applied exactly once (DB state unchanged on replay) | Integration | `LMS-BR-011`, `LMS-INV-002` |
| `LMS-IT-003` | Stale timestamp → 400 `STALE_TIMESTAMP`; future-beyond-skew likewise | Integration | `LMS-US-009` |
| `LMS-IT-004` | Content-hash re-upload → 200 original import; no new job/rows; per-school hash scope (same file, other school = new import) | Integration | `LMS-US-002`, `LMS-INV-001` |
| `LMS-IT-005` | Commit resumability: kill worker mid-chunk → requeue → unprocessed rows applied, processed skipped; totals accurate | Integration | `LMS-BR-004`, `LMS-BE-021` |
| `LMS-IT-006` | Phone-match vs create-PENDING: matched user updated (status untouched), unmatched created PENDING; `verification_requests` untouched | Integration | `LMS-BR-005`, `LMS-BR-006` |
| `LMS-IT-007` | Cross-tenant: School Admin A → school B's imports/endpoints/events/reconciliation → `TENANT_MISMATCH`; webhook for school without ACTIVE endpoint → rejected | Integration | `LMS-BR-001`, `LMS-BR-013` |
| `LMS-IT-008` | Enrollment application via 04: `CreateEnrollments` created/exists/error rows land in the report; verified user's group chain untouched by 14 | Integration | 04 contract (`ORG-IT-008` pair) |
| `LMS-IT-009` | Rate limit: 61st event in a minute → 429 + `Retry-After`; not logged `applied` | Integration | `LMS-BR-012` |
| `LMS-IT-010` | Redrive: `error` event re-applied after section created → `applied`; double-redrive cannot double-apply (event id idempotency) | Integration | `LMS-US-011` |
| `LMS-IT-011` | Auth chain on every admin route: unauthenticated → `UNAUTHENTICATED`; wrong role → `FORBIDDEN`; licence off → `FORBIDDEN` | Integration | 02 §6, `LMS-BR-014` |
| `LMS-IT-012` | Reconciliation: drift flagged for extra/missing/mismatch vs baseline; no-import baseline state | Integration | `LMS-US-012` |

Always included: unauthenticated call denied for every protected entry point; validation rejects
bad input; cross-tenant read/write returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
raw secrets never appear in logs, audit entries, or any GET response.

## 7. Task Checklist

### Schema

- [ ] Migrations 1–4 (§1.2) — prerequisite for every `LMS-BE-*` task below — ____

### Repository · Service · Entry points · Seed · Tests

- [ ] `LMS-BE-016`–`017` sqlc: roster imports + rows (hash probe, error report, commit cursor) — ____
- [ ] `LMS-BE-018`–`LMS-BE-019` sqlc: endpoints + sync events (idempotent insert, log paging) — ____
- [ ] `LMS-BE-001`–`002` services: template generator + upload/idempotency — ____
- [ ] `LMS-BE-003`, `LMS-BE-005`, `LMS-BE-020`–`021` process + commit jobs (chunks of 500, cursor resume) — ____
- [ ] `LMS-BE-004`, `LMS-BE-006` commit entry + import reads/CSV error report — ____
- [ ] `LMS-BE-007`–`010`, `LMS-BE-022` endpoint lifecycle (create/rotate/revoke/test, show-once secret) — ____
- [ ] `LMS-BE-011`–`013` webhook core: verify (HMAC/timestamp/rate) + apply + redrive — ____
- [ ] `LMS-BE-014`–`015` event log + reconciliation report — ____
- [ ] Entry points: 12 route groups per §2 + OpenAPI spec entries + contract regen — ____
- [ ] i18n keys `sync.*` (+ `validation.*` reuse) added to `packages/shared` bn/en catalogs — ____
- [ ] Tests: `LMS-UT-001`–`006` · `LMS-IT-001`–`012` green in CI — ____
