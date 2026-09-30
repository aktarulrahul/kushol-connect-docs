# LMS/ERP Sync — Solution Approach

**Module:** `14-lms-erp-sync` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `roster_imports` | One uploaded roster file (CSV/XLSX) per school: format, dry-run flag, lifecycle status, totals, `content_sha256` for idempotency, file reference into 05 `media_assets` | Yes |
| `roster_import_rows` | Per-row record of every imported row: source payload (jsonb), result (`created\|updated\|skipped\|error`), i18n `error_key` + message; immutable once written | Yes |
| `erp_endpoints` | A school's registered LMS/ERP webhook identity: URL, versioned HMAC secret (hashed), overlap window, `active\|revoked`, `last_success_at` | Yes |
| `erp_sync_events` | Every received webhook event: endpoint ref, `X-Kushol-Event-Id`, type, payload, signature validity, `applied\|rejected\|duplicate\|error`, reject reason | Yes |
| `users` | Read/written ONLY via 03's exported user upsert (PENDING on create; verification untouched) | No — module 03 |
| `sections` / `enrollments` | Resolved/upserted only via 04 exports (`GetSection`, `CreateEnrollments`) | No — module 04 |
| `media_assets` | Uploaded roster file bytes live in R2 via 05's presign/confirm flow | No — module 05 |
| School Admin portal surfaces | `/school/roster` + `/school/integrations` screens fill 07's nav stubs | No — module 07 shell |

### 1.2 Relationships

```text
schools (04) 1 ──── * roster_imports 1 ──── * roster_import_rows
                    │ file_media_id → media_assets (05)
schools (04) 1 ──── * erp_endpoints 1 ──── * erp_sync_events
                                              │ payload → applied via
                                              │   03 users (auth.UpsertRosterUser)
                                              │   04 sections/enrollments (CreateEnrollments)
roster rows / events ── produce ──▶ users (03, PENDING|VERIFIED) ─▶ enrollments (04)
                                                   └ VERIFIED chain: 04→05 groups, 06 topics (existing)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `LMS-INV-001` | `(school_id, content_sha256)` is UNIQUE — one import per identical file per school | DB unique index + service |
| `LMS-INV-002` | `(endpoint_id, event_id)` is UNIQUE — one application per event per endpoint | DB unique index |
| `LMS-INV-003` | `roster_import_rows.result` values are immutable after write (append-only outcomes) | Repository (no UPDATE path) |
| `LMS-INV-004` | An import reaches `committed` only from `ready`; `ready` only from a dry-run with zero error rows | Service state guard |
| `LMS-INV-005` | A raw webhook secret never persists — only its hash; raw exists solely in the one-time create/rotate response | Service (create/rotate path) |
| `LMS-INV-006` | Every import/endpoint/event query carries the tenant scope — school from claim (admin routes) or from the verified ACTIVE endpoint row (webhook route) | Repository layer |
| `LMS-INV-007` | Users created by ingestion are PENDING; `verification_requests` is never written here | Service (03 export contract) |

## 2. Module Boundary

**Owns (writes):** `roster_imports`, `roster_import_rows`, `erp_endpoints`, `erp_sync_events`; the
template generator (built from live 04 sections); the HMAC verification + apply pipeline; the
reconciliation report query.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 identity-access | user upsert — see 06-integration §3 there (consumed as `auth.UpsertRosterUser`; **additive export needed** — 03 §2 does not yet name it, flagged in 06 §3) | Identity, PENDING/VERIFIED semantics and the verification flow are 03's; 14 must never fork them |
| 04 organization-hierarchy | `hierarchy.CreateEnrollments(batch, source)` · `hierarchy.GetSection` | Enrollment rules, idempotency and the verified-user group/topic chain live in 04/05/06 |
| 05 media | presigned upload + confirm (`media_assets`) for roster files | R2 handling exists once for all modules |
| 01 foundations | `jobs.Enqueue`/`jobs.Register`, `audit.Record`, rate-limit middleware | No new queue infra (`tech-stack.md`: in-DB jobs, no Kafka) |
| 07 command-center-web | shell + nav stubs (`/school/roster`, `/school/webhooks` → filled as `/school/integrations`) | Portal chrome is 07's; 14 ships screens into it |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4 (`school:{id}:roster`).

## 3. Lifecycle

```text
roster_imports:  uploaded ──validate──▶ validating ──┬─ zero errors ─▶ ready ──commit──▶ committing ──▶ committed
                                                     └─ errors ─────▶ validated_with_errors (fix + re-upload; commit blocked)
                 uploaded/validating/ready ──failure──▶ failed        committing ──cancel──▶ cancelled

erp_endpoints:   (create, secret v1) ──▶ ACTIVE ──rotate──▶ ACTIVE (v2, v1 valid until overlap_until)
                 ACTIVE ──revoke──▶ REVOKED (terminal; events rejected)

erp_sync_events: received ──verify──▶ applied | rejected (signature/timestamp/endpoint) | duplicate | error ──redrive──▶ applied
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| uploaded | validation job starts | validating | file object confirmed in 05 | — |
| validating | job finishes | ready / validated_with_errors | totals + per-row results written | totals cached for the detail view |
| ready | School Admin commits | committing | `LMS-INV-004`; licence flag | commit job enqueued; `audit.Record` |
| committing | chunks of 500 applied | committed | per-row tx; cursor resume | users (03) + enrollments (04); audit entry |
| ACTIVE | rotate-secret | ACTIVE (v+1) | overlap window default 24 h | new hash row version; old hash kept until expiry |
| ACTIVE | revoke | REVOKED | — | subsequent events rejected + logged |
| received | HMAC + timestamp + event-id pass | applied / duplicate | `LMS-INV-002`; ±5 min window | 03/04 writes; `last_success_at` bumped |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `/school/roster` (history + totals) | Dynamic, Server Component first paint + TanStack Query polling while `validating`/`committing` | None — import lists/totals always fresh (stale results would mislead commits) | `school:{id}:roster` invalidated on every mutation |
| `/school/roster/new` wizard | Client steps; upload via presigned PUT + multipart confirm | None | — |
| `/school/integrations` + event log | Dynamic; log paged, fresh | None (fresh by design) | `school:{id}:roster` |
| Template + error CSV downloads | Streamed responses, `no-store` | None | — |
| Reconciliation report | Dynamic on request | 5-min Redis cache of computed counts (cheap re-read, drift tolerance) | `school:{id}:roster` |

Nothing about this module is publicly cacheable; every response is tenant-scoped and `no-store` on admin reads.

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| ERP endpoint name + URL; revoke; rotate secret | HMAC scheme (SHA-256), header names `X-Kushol-*`, replay window 5 min |
| Per-school sync licence flag (Super Admin, via 07) | Commit chunk size 500; async threshold > 500 rows |
| (Future) import row ceiling per licence tier `TODO: Confirm` | Max 10,000 rows / 20 MB per file; CSV header set + order |
| — | Rate limit 60 events/min/school; overlap window 24 h; body cap 1 MB |

## 6. Security

| Entry point | Auth chain | Tenant scope | Rate limit | Notes |
| --- | --- | --- | --- | --- |
| `/api/v1/school/roster/*`, `/school/erp/*`, `/school/reconciliation` | authenticate → role claim `SCHOOL_ADMIN` → tenant-scope | school from JWT/session claim only; path ids joined to claim | default class | `FORBIDDEN` without licence (`LMS-BR-014`) |
| `POST /api/v1/webhooks/erp/{schoolId}` | **Exception (documented): unauthenticated-but-HMAC-signed**, same pattern as module 12 payment webhooks — no session/JWT exists for ERP systems | `schoolId` from the URL must match an ACTIVE `erp_endpoints` row (`LMS-BR-001`); cross-references fail closed | 60/min/school (`RATE_LIMITED` + `Retry-After`) | constant-time HMAC compare (`LMS-BR-009`); ±5 min timestamp (`STALE_TIMESTAMP`); body cap 1 MB; `audit.Record` on every rejection |
| Validation/sanitisation | OpenAPI validators on every handler; CSV/XLSX parsed as data only (formulas never evaluated); payload jsonb size-capped | — | — | secrets redacted in slog; raw secret returned exactly once (`LMS-INV-005`) |

## 7. Accessibility & Motion

Web-only surfaces (04): wizard step changes animate 200 ms translate/fade (instant under reduced
motion), validating/committing use poll-driven skeletons — no looping spinners; secret-reveal modal
is focus-trapped with the warning announced (`aria-live="assertive"`); error tables are real tables
with `scope`d headers and row numbers as the stable reference. Keyboard path complete (upload,
commit, test, rotate, redrive all reachable); all strings bn/en from `sync.*`.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Validation/commit job crashes mid-commit | 01 worker reaper requeues; row cursor (`processed_at IS NULL`) | Import stuck `committing` | Job resumes at first unprocessed row; processed rows skipped (`LMS-INV-003`) |
| 2 | 03/04 export rejects rows at commit | Per-row error captured | Those rows `error`; siblings unaffected | Import completes `committed` with true totals; School Admin fixes + re-uploads or redrives events |
| 3 | R2 object missing at process time | 05 confirm/GET failure | Import `failed` with reason | Re-upload required |
| 4 | Webhook arrives while 03 or 04 is degraded | Export error | Event `error` (not lost) | Redrive from the event log; ERP may also retry (same event id → `duplicate` only after success — until then the id is reserved as `error`, re-delivery re-attempts apply) |
| 5 | Redis down | Rate limiter fallback | Stricter in-process limiter | Default 01 fallback; no ingestion loss |
| 6 | Replay attack (old captured request) | Timestamp outside ±5 min | `STALE_TIMESTAMP` 400 + security log | ERP re-signs with fresh timestamp + new event id |
| 7 | Secret rotated while ERP still on v1 past overlap | Signature fails after `overlap_until` | Events rejected | School Admin re-rotates or fixes ERP config; log names the version mismatch |
| 8 | Duplicate upload race (two tabs) | Unique index loses second insert | Second request returns the first import | 200 no-op (by design) |

## 9. Performance

- Volumes: ≤ 10,000 rows/file, one bulk import per school per term, hot path is webhooks (≤ 60/min/school at launch — trivial).
- Hot queries + indexes: import lookup `(school_id, content_sha256)` UNIQUE → idempotency probe; `(import_id, row_no)` + partial `(import_id) WHERE result='error'` → report pages; `(endpoint_id, event_id)` UNIQUE → idempotency probe; `(school_id, status)` on endpoints → webhook resolution; `(received_at)` on events → log paging.
- Parsing: CSV streamed row-by-row (no full-file load); XLSX via a streaming sheet reader; chunks of 500 rows per transaction keep Neon round-trips and memory flat.
- Web deps: none beyond existing table/polling stack — no new bundle-heavy libraries (CSV parse server-side; XLSX generation happens in Go).
- Per-row 03/04 exports dominate commit time; batches + resume make 10k rows a background concern, never a request-time one.

## 10. Alternatives Considered

### Option A — synchronous parse/commit in the request · Option B — async jobs (chosen)

| | A | B |
| --- | --- | --- |
| Advantages | Simplest code; instant feedback | No request timeouts on 10k rows; retries/resume; worker isolation |
| Disadvantages | 10k-row commits blow request budgets on a 2-vCPU VPS; crash = retry the whole file | Progress polling UX; job table growth |
| Complexity / weight | Low | Low — module 01 `jobs` already exists (no Kafka, per `tech-stack.md`) |

**Recommendation:** B for > 500 rows (README seam: `jobs.Enqueue`), synchronous path retained for small files' dry-run feel (still via the same job, awaited).

### Option A — XLSX+CSV day one · Option B — CSV first (P0), XLSX P1 (chosen)

| | A | B |
| --- | --- | --- |
| Advantages | Schools love Excel | CSV covers the machine contract; smaller parser surface; template download is already CSV |
| Disadvantages | Heavy Go XLSX lib + formula/merge edge cases at P0 | Office staff may need XLSX initially |
| Complexity / weight | High (streaming reader, cell coercion) | CSV P0; XLSX read added behind the same `format` column in P1 |

**Recommendation:** B — `format ∈ csv|xlsx` is modelled now; XLSX parsing ships P1 (`LMS-BR-007` ceiling unchanged).

### Option A — mTLS per school · Option B — HMAC-SHA256 (chosen)

| | A | B |
| --- | --- | --- |
| Advantages | Strongest transport identity | Self-serve in one modal; no CA/cert lifecycle; matches module 12's webhook pattern |
| Disadvantages | Cert issuance/renewal is not self-serve for Bangladeshi school IT; heavy ops | Secret mishandling risk mitigated by show-once + rotation + replay window |
| Complexity / weight | High (per-tenant certs, proxy TLS routing) | Low — two headers + a hash |

**Recommendation:** B per README default (`erp_endpoints.secret_hash`, rotating, versioned). ADR in `07-progress.md` at build; revisiting to mTLS later affects only this module's middleware.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | 03 will export the roster user-upsert path (`auth.UpsertRosterUser`) additively | Ingestion cannot create/update users without forking identity logic | Flagged as additive need (06 §3); contract agreed before build; fallback = blocking dependency |
| 2 | Phone numbers are reliably present and normalized in school rosters | Match rate collapses; duplicate PENDING users | Strict `01[3-9]\d{8}` validation with row errors; OQ-2 secondary key (`TODO: Confirm`) |
| 3 | Schools' ERPs can implement HMAC headers correctly | Rejected-event churn | Test-event button, bn+en integration guide, per-endpoint event log with reject reasons |
| 4 | 10k-row ceiling suffices per term | Large schools need splits | Config ceiling per licence tier (`TODO: Confirm`, OQ-1) |
| 5 | Verified-user group/topic updates lag behind imports (04/05/06 chain) | Admins expect instant groups after commit | Documented degradation (06 §8); import completes, chain retries — never double-applied |
| 6 | Licence flag exists before Phase 3 schools onboard | Module unusable or ungated | Default ON for pilots (OQ-8); flag check is a single service guard, trivially togglable |
