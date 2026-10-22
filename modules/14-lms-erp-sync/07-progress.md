# 14-lms-erp-sync — Build Progress

Module: lms-erp-sync · Surfaces: **api + web** (app = N/A by design, `05` empty) ·
**Last updated:** 2026-10-15

> Owner instruction: "complete 14 lms-erp-sync" (08/09 deferred to phase 2). Same through-stages
> precedent (06/10/11/12/13); gates 1–3 stay owner-manual.

## Stage / gate status

| Stage | Status | Evidence |
| --- | --- | --- |
| 1 Plan | ✅ 2026-10-04 | OQ-1…10 defaults accepted (10k rows/20 MB · phone-only match · exact template · HMAC ±5 min + 24 h overlap · event-id duplicates 200 · 60/min + Retry-After · licence ON for pilots via 07 · pull default for partners · `/institution/lms/connections*` routes · FCM rename deferred) |
| 2 UI (web, mock-driven) | ✅ 2026-10-04 | contract-first: 22 operations + 28 `Lms*` schemas landed FIRST; both clients generated (105 `Lms` refs in the web schema); web: roster home, upload wizard, import detail, integrations (endpoints + LMS pull panel), reconciliation — on `fixtures/lms.ts` |
| Gate 1 | ✅ owner 2026-10-15 | owner approved in session ("complete all from Gate 1"); review hand-off below |
| 3 Docs sync | ✅ 2026-10-04 | this file, 08-gaps, README → 🚧, registry row, checklist ticks, change log |
| 4 Backend | ✅ code-complete 2026-10-04 | 3 migrations, 3 sqlc files, `internal/sync` (roster pipeline, endpoint lifecycle, webhook core, pull connector, reconciliation) + cmd/httpapi wiring + `ERP_SECRET_KEY` config |
| Gate 2 (SQL on Neon) | ✅ owner | 2026-10-09 — all migrations applied to Neon via 15 first deploy (`v0 → 20270302090001 dirty=false`), covers `20270301090001–090003` |
| 5 Integration | ✅ code-complete 2026-10-04 | web fixture seam until 07's console glue (G-3, 10/11/12/13 precedent); ITs specified — runs pending owner (G-1/G-2) |
| Gate 3 | ⏳ pending | — |

## Decisions (ADR)

1. **ADR-1 (webhook security — BR-009/INV-005):** the documented unauthenticated-but-HMAC-signed
   exception (module 12 pattern): constant-time HMAC-SHA256 over `{timestamp}.{rawBody}`,
   ±5-min window, UUID event-id dedupe per endpoint; secrets are 32-byte random, AES-256-GCM
   sealed (`NewGCMWithRandomNonce` — nonce inside Seal) under `ERP_SECRET_KEY` (base64, required
   env), raw shown exactly once in create/rotate responses, versioned rotation with previous
   secret valid until `overlap_until` (default 24 h, max 72).
2. **ADR-2 (migrations — registry deviation):** spec §1.2's four migrations consolidated to
   **three** (`…090001` roster imports+rows, `…090002` ERP endpoints+events, `…090003` pull
   tables) — registry row updated to `20270301090001–090003`. `…090003` also adds the sync
   licence flag `schools.sync_licence_enabled` (additive column on 04's tenant table; Super
   Admin UI lands with 07 — G-4) and extends the `media_assets` kind CHECK with `roster`
   (server-put roster files through 05).
3. **ADR-3 (pull connector — plan §2–§6):** `VendorClient` port (production `HTTPVendorClient`
   with Bearer/API-key auth, path overrides, 10 s budget, HTTPS-only SSRF guard; fakes in UTs —
   no invented third-party behaviour). Schedule presets are interval-based (hourly +1 h, daily
   +24 h, weekly +7 d from last run). One running sync per connection (partial unique index →
   409 on second Sync-now). Section upsert via the **additive 04 export**
   `hierarchy.EnsureExternalSection` (resolve by class+name+session, create with FCM topic
   binding when missing); people via 03 `users.UpsertRosterUser` (PENDING creates only);
   membership via 04 `CreateEnrollments(batch, "ROSTER")`; the `(school, entity, external_id)`
   map lives in `lms_external_ids`.
4. **ADR-4 (ingestion semantics — BR-005/006/INV-007):** phone is the identity key (matched →
   update, unmatched → PENDING create — never auto-verified, `verification_requests` never
   written). Webhook `enrollment.changed` resolves sections only via the external-id map;
   unknown section keeps the user upsert and records the event `error` (redrive-able, edge 7).
   Withdrawal (`active=false`) is recorded `error` until 04 exports an end-enrollment path (G-5).
5. **ADR-5 (formats & dry-run — 02 §10):** CSV P0 (streaming parse); XLSX rejected at upload
   with `sync.import.format_invalid` (Option B — the `format` column models xlsx for P1). Every
   upload is stored as a dry-run (`dry_run=true`); commit only from `ready` (INV-004) — the
   wizard's dry-run toggle is UX intent, the guard is server-side.
6. **ADR-6 (cache contract):** all admin reads are fresh/no-store (02 §4 — stale totals would
   mislead commits), so no tag consumers exist yet; the `school:{id}:roster` tag is registered
   for the reconciliation 5-min Redis memo, which is deferred (G-6).

## Evidence (2026-10-04)

| Repo | Check | Result |
| --- | --- | --- |
| api | build/vet repo-wide · fmt-check | clean |
| api | `make lint` (golangci-lint) | **0 issues** (incl. pre-existing findings in 04/07/leads/partners files fixed) |
| api | `make contracts-check` | `contracts: no drift` |
| api | `go test -race ./internal/sync/...` | LMS-UT-001 (row taxonomy), UT-002 (fixed headers), UT-003 (HMAC versions + overlap), UT-004 (±5-min window), UT-005 (schedule presets + secret seal), UT-006 (per-type payloads) — green |
| api | wiring | jobs `roster.import.process`, `roster.import.commit`, `erp.test.dispatch`, `lms.pull.sync`, `lms.pull.tick` registered; adapters `rosterUserAdapter` (direct), `rosterHierarchyAdapter`, `rosterMediaAdapter` (05 `PutObject`/R2 `GetObject`); `Sync` embedded in httpapi |
| web | typecheck ✓ · scoped lint ✓ · **189/189 tests** (23 files) | fixture state machine (BR-002/003/004, show-once secret, redrive-only-errors, HTTPS-only connections) + i18n catalog parity |
| both clients | sync + generate | spec copies match the api |
| web | `e2e/lms.spec.ts` | golden-path specs written — **pending owner run** (G-1) |

## Gate 2 SQL hand-off (owner)

```text
db/migrations/20270301090001_create_roster_imports.up.sql   -- roster_imports + roster_import_rows + schools.sync_licence_enabled
db/migrations/20270301090002_create_erp_endpoints.up.sql    -- erp_endpoints + erp_sync_events
db/migrations/20270301090003_create_lms_connections.up.sql  -- lms_connections + lms_sync_runs + lms_external_ids + media kind 'roster'
```
Run in order against Neon; each has a `.down` reverse. `ERP_SECRET_KEY` must be set
(`openssl rand -base64 32`) before the api boots — it is a required env like
`PAYMENTS_WEBHOOK_SECRET`.

## Gate 1 review hand-off

Web (`pnpm dev`, fixtures): `/institution/roster` (cards + history) → `/institution/roster/new`
(template download → CSV upload → dry-run report → commit; errors block commit) →
`/institution/roster/imports/[id]` (totals + error rows) → `/institution/integrations` (endpoint create
with show-once secret modal + ack, test/rotate/revoke, event log + redrive; LMS connection
form + test + Sync now + run history) → `/institution/roster/reconciliation` (baseline vs platform,
drift flags). Desktop 1280 + 768; bn default, en toggle.

## Web admin LMS pages — 2026-10-09 (owner request; implements the partner pull contract client-side)

`/admin/lms` + `/admin/lms/[id]` now follow **partner-lms-api-spec.md** / **partner-lms-api-response-examples.md**
exactly (fixture seam `fixtures/lms.ts` admin section; swap point = `internal/sync` endpoints):

- **Partner surface simulated per contract**: `GET /teachers` · `/students` · `/sections` (classes with
  nested `sections[]`) · `/sections/{external_id}` (`teacher_ids`/`student_ids`/`class_teacher_id`) ·
  `/notices` — cursor pagination (`next_cursor`, limit 1–200), 401 on disabled/revoked credentials
  (the college demo connector is intentionally revoked to exercise the `sync.run.auth_failed` path),
  soft-delete via `active:false` skipped rows. Sample payload = the doc's উদাহরণ উচ্চ বিদ্যালয় rows.
- **Pull flow per lms-pull-integration-plan §3**: teachers → students → classes/sections →
  per-section membership (unknown ids warn + skip, spec §5.4) → notices when `syncNotices` →
  upsert counts → chat groups ensured (official section groups; **class_teacher = group admin**,
  lex-smallest fallback + warning; plus the institution's teachers group). New people are created
  **PENDING — never auto-verified** (spec §11); re-sync with the same `external_id`s updates in
  place (idempotent, `lms_external_ids` semantics).
- **UI**: per-row + details **Test connection** (probes `/teachers?limit=1` per plan §2.1, shows
  latency or 401), **Sync now / Sync all**, and a per-connection pull **report** — classes,
  sections, teachers/students created vs updated, enrollments changed, groups ensured, notices
  upserted, and the warnings list (missing membership ids, class-teacher fallback, membership-doc
  gaps). Configure dialog: institution, name, HTTPS base URL, bearer/api-key + header, credential
  (write-only, masked), schedule preset, notice-sync flag; one connection per institution.
- Gates: eslint · `tsc` · vitest 220/220 (admin connector tests incl. one-per-institution,
  HTTPS-only, group-ensure, idempotent re-sync) · Next build — all green. API-side notes: the real
  engine lives in `internal/sync` (pull.go); the admin platform-level endpoints (list ALL
  connections + trigger across institutions) remain 14 backend work (§6 sketch) — the web seam is
  the documented swap point.
