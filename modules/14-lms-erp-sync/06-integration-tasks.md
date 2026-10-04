# LMS/ERP Sync — Integration Tasks

**Module:** `14-lms-erp-sync` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

`02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
**contract**. No cross-module call, cache key or external dependency may exist in code unless it is
declared here (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `03 identity-access` | we call them | exported user-upsert path — see 06-integration §3 there; consumed here as `users.UpsertRosterUser` (declared in 03 `06` §2, 2026-09-30) | per-row `error` in the import/event report; import completes; redrive recovers |
| I-2 | `04 organization-hierarchy` | we call them | exported `hierarchy.CreateEnrollments(batch, source="ROSTER")` + `hierarchy.GetSection` | fatal per row (row-level error reported); never fatal to the import/job |
| I-3 | `05 media` | we call them | presigned upload + confirm (`media_assets`) for roster files | import `failed` with reason; re-upload |
| I-4 | `01 foundations` | we call them | `jobs.Enqueue`/`jobs.Register` (process/commit workers) · `audit.Record` · rate-limit middleware | jobs degraded (QUEUED + retry); audit failure aborts the wrapped destructive action |
| I-5 | `07 command-center-web` | they host us | `/school/roster` + `/school/integrations` nav stubs — 14 fills them (wizard, history, `/school/integrations`) | portal shell down = screens unreachable; api unaffected |
| I-6 | Schools' LMS/ERP systems (external) | they call us | inbound HTTPS `POST /api/v1/webhooks/erp/{schoolId}` (HMAC-signed, unauthenticated-by-design exception) | rejected per event (`INVALID_SIGNATURE`/`STALE_TIMESTAMP`/`RATE_LIMITED`); ERP retries; never fatal to the platform |
| I-7 | `04/05/06` verified-user chain (indirect) | we trigger | enrollment upserts for VERIFIED users propagate groups/topics via the existing chain | degraded — import completes, groups/topics converge via chain retries (06 §8) |

## 2. Exported Contract

```text
sync.IngestRosterBatch(rows []RosterRow, schoolId uuid) (BatchResult, error)
      // programmatic path for future bulk features; same per-row semantics as the CSV pipeline:
      // phone-match → update / no-match → PENDING create (never auto-verify); enrollments via 04
sync.ApplyErpEvent(event ErpEvent) (ApplyResult, error)
      // webhook core: idempotency probe (endpoint_id, event_id) → 03 upsert + 04 enrollments;
      // returns applied|duplicate|error — the HTTP layer only adds signature/timestamp/rate checks
sync.VerifyEndpointSecret(endpoint ErpEndpoint, timestamp string, rawBody []byte, signature string) (SecretCheckResult, error)
      // constant-time HMAC-SHA256 verify against current + overlap secret version; exposes
      // INVALID_SIGNATURE vs STALE_TIMESTAMP as domain errors
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `IngestRosterBatch` | future bulk features (none at launch) | per-row results + totals DTO | `VALIDATION_FAILED` (batch shape) | same rules as `LMS-BE-005`; tenant from the caller's claims context |
| `ApplyErpEvent` | webhook handler (this module); redrive | `ApplyResult{status, appliedAt}` | domain errors (`VALIDATION_FAILED`, `NOT_FOUND`) | per-event transaction; duplicate returns the original outcome without re-application |
| `VerifyEndpointSecret` | this module's webhook middleware; reusable by module 12-pattern audits | `SecretCheckResult{ok, versionUsed, stale}` | `INVALID_SIGNATURE` / `STALE_TIMESTAMP` | constant-time compare; overlap window honoured |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `users.UpsertRosterUser` — user upsert (03-identity-access exported user upsert; see 06-integration §3 there) | 03 | row-level `error` (row + event survive for redrive); declared in 03 `06` §2 (2026-09-30) |
| `hierarchy.CreateEnrollments(batch, "ROSTER")` | 04 | per-row `created/exists/error` from 04's contract (`ORG-IT-008`); error rows reported, never silently dropped |
| `hierarchy.GetSection(sectionID)` | 04 | row error `sync.row.section_unknown`; redrive after the section exists |
| 05 media presign/confirm (`media_assets`) | 05 | import `failed` + `sync.import.file_missing`; re-upload path |
| `jobs.Enqueue` / worker runtime | 01 | 503-style enqueue failure → request retried by client; queued jobs survive restarts (01 reaper) |
| `audit.Record` | 01 | aborts the destructive action (no un-audited commit/rotate/revoke) per 01's contract |
| 07 portal shell + nav | 07 | screens unreachable; api contract unchanged |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| import uploaded / validated / committed | `school:{id}:roster` |
| endpoint created / rotated / revoked; test result | `school:{id}:roster` |
| event applied / redriven | `school:{id}:roster` |
| — (enrollment/group/topic effects belong to the 04/05/06 chain's own tags) | — |

| Read | Tagged with |
| --- | --- |
| `GET /school/roster/imports*` | `school:{id}:roster` (admin reads fresh; no-store) |
| `GET /school/erp/endpoints*` | `school:{id}:roster` (no-store) |
| `GET /school/roster/reconciliation` | `school:{id}:roster` + 5-min Redis memo of computed counts (drift tolerance) |
| template / error CSV streams | none (`no-store`) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Schools' LMS/ERP (inbound) | HTTPS POST → `/api/v1/webhooks/erp/{schoolId}` | per-school HMAC-SHA256 (`X-Kushol-Signature`, `X-Kushol-Timestamp`, `X-Kushol-Event-Id`) | 10 s server budget | caller's duty (event-id makes retries safe) | rejected events logged with reason; redrive; rate 60 events/min/school (429 + `Retry-After`), body ≤ 1 MB |
| Schools' ERP (outbound test events only) | HTTPS POST from us to the registered URL | the endpoint's HMAC secret signs the test payload | 5 s | ×1 (outcome shown to admin) | failure is feedback, never state change |
| R2 (via 05) | indirect — presign/confirm only | 05-owned credentials | 05's | 05's | import `failed` → re-upload |
| (none other at launch) | — | Outbound live sync to schools' systems is explicitly out of scope; FCM/DeepSeek/gateways/SMS belong to 06/08/12/03 | — | — | — |

**Inbound rate limits documented for operators:** 60 events/min/school (`RATE_LIMITED` +
`Retry-After`), 10 uploads/hour/school, template downloads on the default class, webhook body cap
1 MB, upload cap 20 MB / 10,000 rows (`TODO: Confirm`, OQ-1).

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Wizard step 1 (template) | `GET /api/v1/school/roster/template` | CSV stream + bn/en instruction sheet; `sync.import.headers_invalid` never possible from it |
| Wizard step 2 (upload) | 05 presign/confirm + `POST /api/v1/school/roster/imports` | 201 import or 200 hash no-op (`sync.import.hash_noop` panel) |
| Wizard step 3 (report) | `GET /api/v1/school/roster/imports/{id}`, `…/rows?result=error` (+`?as=csv`) | row-level `errorKey` messages bn/en; commit disabled unless `ready` |
| Commit button | `POST /api/v1/school/roster/imports/{id}/commit` | 202 `committing` → poll to terminal; `CONFLICT` → state hint |
| Endpoints table + modals | `POST/GET /api/v1/school/erp/endpoints`, `…/rotate-secret`, `…/test` | raw secret only in create/rotate responses (`sync.secret.warning` modal) |
| Event log drawer + redrive | `GET /api/v1/school/erp/endpoints/{id}/events`; redrive via `POST /api/v1/school/erp/endpoints/{id}/events/{eventId}/redrive` | paged log; redrive result toast |
| Reconciliation screen | `GET /api/v1/school/roster/reconciliation` | baseline/platform/drift DTO; no-baseline state handled |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. The webhook envelope (headers + body shape)
is versioned by `X-Kushol-Signature` scheme string; a future `sha512=` or v2 header scheme must
accept both during a documented overlap (same policy as secret rotation). New event `type` values
are additive; unknown types are rejected `VALIDATION_FAILED` (ERP upgrades after the platform).
`sync.IngestRosterBatch` is frozen at v0 semantics until its first external caller.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 03 upsert export | validation, reports, endpoint management | affected rows/events `error` with reason | redrive after 03 recovers; imports stay `committed` with true totals |
| 04 `CreateEnrollments`/`GetSection` | user upserts (03 part), enrollment rows flagged | report shows `sync.row.section_unknown`/enrollment errors | redrive; verified users' groups converge via the 04/05/06 chain's own retries — never double-applied |
| 05 media / R2 | endpoints, events, reconciliation (existing imports) | upload fails with `sync.import.file_missing` on process | re-upload |
| 01 jobs worker | uploads accepted (status `uploaded`), reads, webhook apply (synchronous path) | validation/commit delayed; progress badges explain | 01 reaper requeues; resume by cursor — nothing half-applied |
| Redis | full ingestion; DB-backed limiter fallback (stricter) | slightly tighter webhook limits | auto |
| Schools' ERP misconfigured (bad secret/URL) | platform unaffected | test-event failure + event log reasons (`sync.webhook.test_failed`) | admin fixes ERP or re-rotates with overlap |
| Replay/tamper attempt | everything else | `INVALID_SIGNATURE`/`STALE_TIMESTAMP` + security log (module 15 alerts) | incident path; endpoint stays usable |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `LMS-IT-001` | HMAC IT: valid → `applied`; tampered → 403 `INVALID_SIGNATURE` + security log; wrong version post-overlap → rejected | Integration | I-6 security chain (`LMS-US-007`, `LMS-US-009`) |
| `LMS-IT-002` | Event-id idempotency IT: replay → 200 `duplicate`, applied exactly once | Integration | `LMS-BR-011` |
| `LMS-IT-003` | Stale timestamp IT (>±5 min) → `STALE_TIMESTAMP` | Integration | `LMS-BR-010` |
| `LMS-IT-004` | Content-hash re-upload no-op IT (incl. per-school hash scope) | Integration | `LMS-BR-002` |
| `LMS-IT-005` | Commit resumability IT (crash mid-chunk → resume, no double-apply) | Integration | `LMS-BE-021` |
| `LMS-IT-006` | Phone-match vs create-PENDING IT (matched updated, unmatched PENDING, `verification_requests` untouched) | Integration | `LMS-BR-005`/`006` |
| `LMS-IT-007` | Cross-tenant endpoint/import/event access denied; webhook to unknown/revoked endpoint rejected | Integration | `LMS-BR-001`/`013` |
| `LMS-IT-008` | 04 batch contract: created/exists/error rows land in the report (pairs `ORG-IT-008`) | Integration | I-2 |
| `LMS-UT-001` | Row-level error taxonomy UT (bad phone, unknown section, duplicate-in-file, bad role) | Unit | §6 rules of `01-user-stories.md` |
| `LMS-UT-002` | Template headers fixed-set UT (exact columns/order, deterministic pre-fill) | Unit | `LMS-BR-008` |
| `LMS-UT-003` | Secret verifier UT: constant-time compare, version selection, overlap window | Unit | `sync.VerifyEndpointSecret` |
| `LMS-IT-010` | Rate-limit IT: 61st event/min → 429 + `Retry-After` | Integration | `LMS-BR-012` |
| `LMS-E2E-001` | Playwright **WEB-LMS golden path**: login → `/school/roster/new` → download template → upload CSV → dry-run report → fix-free commit → summary counts → import visible in history; axe-clean | Playwright | end-to-end admin journey + bilingual UI |

## 10. Task Checklist

- [x] `LMS-INT-001` `sync` service package exports (`IngestRosterBatch`, `ApplyErpEvent`, `VerifyEndpointSecret`) + DTOs — ____
- [x] `LMS-INT-002` 03 upsert client interface + fake; additive `users.UpsertRosterUser` signature agreed with 03 and recorded in `07-progress.md` — ____
- [x] `LMS-INT-003` 04 client wiring (`CreateEnrollments`/`GetSection`) against frozen ORG exports — ____
- [x] `LMS-INT-004` 05 presign/confirm integration for roster files — ____
- [x] `LMS-INT-005` jobs registered on the 01 worker (`roster.import.process`, `roster.import.commit`, `erp.test.dispatch`) — ____
- [x] `LMS-INT-006` `audit.Record` on upload/commit/endpoint create-rotate-revoke + every webhook rejection — ____
- [x] `LMS-INT-007` webhook route middleware (HMAC + timestamp + rate + body cap) with the unauthenticated exception documented in the OpenAPI spec — ____
- [x] `LMS-INT-008` cache tag `school:{id}:roster` + invalidation on all §4 mutations — ____
- [x] `LMS-INT-009` 07 stub replacement: nav entries for `/school/roster` + `/school/integrations` — ____
- [x] `LMS-INT-010` tests: `LMS-UT-001`–`006` green `-race`; ITs + `LMS-E2E-001` specs ready — runs pending owner (G-1/G-2) — 2026-10-04
