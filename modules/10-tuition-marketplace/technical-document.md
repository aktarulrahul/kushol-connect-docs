# Tuition Marketplace — Technical Document

**Module:** `10-tuition-marketplace` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Single engineer-facing reference compressing the six spec files in this folder (`01-user-stories.md` … `06-integration-tasks.md`). If this document drifts, the spec files win and this file gets corrected.

---

## 1. Overview

### 1.1 Purpose

Implements `brd.md` **BR-03** and `prd.md` **§5.3**: guardians/students post tuition requirements (subjects, class level, budget ৳, area + pin); the system matches each to **verified** university/senior tutors by subject overlap and geo-radius and notifies the nearest ten; seniors publish evidence-backed profiles approved by the School Admin (or platform ops); negotiation runs in-app (module 05 chat) after a staged contact reveal. Phase 2 (`brd.md` §8) — serves `brd.md` §2 Goal 2 and the §7 tuition-commission stream.

### 1.2 Scope

**In:** requirement posts (wizard create, my list with status chips, edit + manual close, 14-day auto-expiry with poster notice) · tutor profiles (create/update, evidence upload via 05 media, submit-for-review, status tracker, badge only after approval) · verification queue (School Admin approve/reject with note, audited; platform-ops queue for `school_id` NULL) · matching job (verified tutors, subject + class overlap, 5 km bbox → top 10 → push via 06) · match lifecycle (interest / single accept / decline / expiry; **contact reveal only on accept**; same-school DM or cross-school Message Request via 05; fee DUE fact on accept — collection = module 12) · marketplace browse of verified tutors · premium upsell screen (P2, disabled CTA).

**Out:** payment collection/gateways/receipts — module 12 (`TODO: Confirm` fee model) · live video classes (`brd.md` §4) · AI/ML matching (rule-based only) · tutor ratings/reviews (future) · vendor/ads (module 13) · public logged-out pages — every surface requires auth; the web build is the admin surface only.

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations | `jobs.Enqueue` (matching/expiry/SLA-reminder), `audit.Record`, error envelope, rate limiter, test harness |
| consumes | 02 design-system | bn/en catalogs `tuition.*` + `validation.*`, tokens, RN primitives, badge styling |
| consumes | 03 identity-access | `auth.RequireVerified` verified gate; `users` identity/role/school claims |
| consumes | 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (poster school context), section/class-level catalog |
| consumes | 05 communication-engine | `chat` DM + `message_requests` (negotiation), `media.PresignUpload`/`ConfirmUpload` (evidence, photos) |
| consumes | 06 notifications | `notify.SendToUser` / `BroadcastTopic` (match/decision/interest/expiry notices, deep links) |
| consumed by | 07 command-center-web | hosts the `/institution/tutors*` + `/institution/tuitions` nav (module owns the screens); reads `tuition.VerifiedTutorCount` for landing/dashboard stats |
| consumed by | 12 payments (future) | consumes the accepted-match fee DUE fact (INV-8) — additive export when 12 lands (`TODO: Confirm` fee model first, `06` §1 I-7) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go 1.24+ · chi · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (Neon) · Redis · in-DB job table + 01 worker | REST handlers, matching/expiry jobs, cache read-through | `tech-stack.md` api table; no model calls — rule-based matching only (`02` §10) |
| contracts | OpenAPI 3.1 (`applications/api/openapi/`) | single source for Go server types + TS clients | paths #1–#15 regenerated on change |
| web | Next.js App Router · Server Components/Actions · TanStack Table + Query · RHF + zod · shadcn/ui | admin surface only (verification queue + oversight) | fills module 07's portal shell |
| app | Expo · expo-router · TanStack Query · zustand · RHF + zod · expo-location | guardian/student/tutor surfaces (wizard, browse, matches, evidence) | bn-first, 360px-first, offline queue |
| web + app (per app) | each app's `src/i18n` bn/en catalogs + zod schemas | `tuition.*` / `validation.tuition.*` message keys | bn default, en secondary |

---

## 3. Architecture

### 3.1 Component diagram

```text
app (Expo) ──┐                                      ┌─► 03 auth.RequireVerified · users (verified gate)
web (Next.js)┴─► chi REST /api/v1/tuition·school/* ──┼─► 04 hierarchy.ResolveUserNodes (tenant context)
                       │                             ├─► 05 chat DM / message_requests · media (evidence, photo)
                       ▼                             └─► 06 notify.SendToUser (push + deep links; retries owned by 06)
      tuition service (TUT-BE-001–016) ── Redis tags (tuition:tutors:{area} · tutor:{id} · tutorcount)
                       │  sqlc + pgx → PostgreSQL/Neon
 tuition_requirements · tutor_profiles · tutor_verifications · tuition_matches
                       └─► 01 jobs worker: tuition.match · tuition.expiry · tuition.verification-reminder
```

### 3.2 Boundary

**Owns (tables / services):** `tuition_requirements`, `tutor_profiles`, `tutor_verifications`, `tuition_matches` — plus the matching/expiry/reminder jobs over them.

**Reads (via exported service functions only):** 03 verified gate + identity (never re-checks credentials) · 04 poster school context + class catalog (refuse-and-retry, never guess tenant) · 05 chat/media orchestration · 06 push fan-out · 01 job runtime, audit, limiter. Cache-tag contract in `06` §4.

### 3.3 Request / data flows

```text
1 · Requirement → matching (job-based, idempotent — `02` §3)
    POST /tuition/requirements → tuition.CreateRequirement (verified gate; expires_at = now()+14d)
      → jobs.Enqueue("tuition.match") → 01 worker → tuition.NotifyMatches(requirementId):
      load requirement (open ∧ unexpired) → SELECT tutor_profiles: status='verified'
      ∧ subjects ?| req.subjects (GIN) ∧ classes_taught ? class_level ∧ lat/lng in 5 km bbox
      (Δlat = r/111.32 ≈ 0.0449°) → rank subject coverage ↓, haversine ↑ in Go (no PostGIS)
      → INSERT ≤10 matches('notified') ON CONFLICT DO NOTHING → notify.SendToUser per tutor (best-effort)
2 · Interest → accept → contact reveal + negotiation
    tutor interest: match notified→interested; poster push "১ জন টিউটর আগ্রহী"
    guardian accept — single tx: match→accepted + requirement→matched + audit.Record + fee DUE fact (INV-7/8)
      + chat opened (same-school 05 DM │ cross-school 05 Message Request; accept still commits if 05 is down)
      contact fields revealed ONLY in the accepted pair's DTOs — computed per request, never denormalized (INV-4)
3 · Verification queue → decision
    submit-for-review (national ID + ≥1 subject evidence confirmed; one pending per profile) → routed queue
      (School Admin = linked school rows; Super Admin = school_id NULL platform rows)
    approve (note optional) / reject (note 5–500 required) → profile status + verified_at, badge live,
      06 notification, audit.Record, tags busted (`tuition:tutors:{area}` · `tuition:tutor:{id}`)
4 · Expiry & reminders (01 worker)
    tuition.expiry hourly: open ∧ expires_at < now() → expired; non-terminal matches → expired; poster notice
    tuition.verification-reminder daily: pending reviews > 48 h → SLA reminder (skips silently when 06 down)
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| requirement | open · matched · closed · expired | open→matched (guardian accept, one-winner tx) · open→closed (poster own, or School Admin close abusive) · open→expired (expiry job, `expires_at` past); matched/closed/expired reject edits + new interest → `CONFLICT` |
| match | notified · interested · accepted · declined · expired | notified→interested (tutor verified ∧ requirement open) · interested→accepted (poster owns requirement ∧ single winner, INV-7) · notified/interested→declined (party of the match) · non-terminal→expired (expiry/close) |
| tutor_profile | draft · pending_review · verified · rejected · suspended | draft→pending_review (evidence complete ∧ geo set ∧ no pending review) · pending_review→verified (routed reviewer approves; `verified_at` set) · pending_review→rejected (note required) · verified→suspended |
| verification | pending · approved · rejected | pending→approved / rejected (routed reviewer only; reject ⇒ `decision_note`); partial UNIQUE keeps one pending per profile |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 — column detail stays there.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `tuition_requirements` | Poster's need: subjects jsonb, class level, budget ৳ min/max, gender pref, area + geo point, schedule, status, `expires_at` | `school_id` = poster's school (04 node) | `(poster_id,status)` · `(school_id,status)` · partial `(status,expires_at) WHERE open` · GIN `(subjects)` | CHECK `budget_min ≤ budget_max`, status/gender enums; poster must be VERIFIED |
| `tutor_profiles` | Senior's offer: university, subjects, classes_taught, bio bn/en, rate hint, availability, geo, photo, status, `verified_at` | `school_id` nullable — NULL = platform-level university tutor (OQ-4 `TODO: Confirm`) | UNIQUE `(user_id)` · partial verified + GIN `(subjects)` + `(lat,lng)` (matching/browse hot query) · `(status,updated_at)` · `(school_id)` | badge is a projection of `status`+`verified_at`; contact info regex-rejected in bio/availability |
| `tutor_verifications` | Review record: evidence media refs (05 `media_assets`), reviewer + scope, decision note, decided at | scoped through `tutor_profiles.school_id`; NULL rows = platform queue (Super Admin only) | `(status,created_at)` · partial UNIQUE pending per profile | CHECK `status='rejected' ⇒ decision_note`; evidence readable by routed reviewer + owner only |
| `tuition_matches` | Requirement × tutor join: status + notified/responded timestamps | none — straddles two schools by design; row-level party authorization | UNIQUE `(requirement_id,tutor_profile_id)` · partial `(requirement_id) WHERE status='accepted'` · `(requirement_id,status)` · `(tutor_profile_id,status)` | idempotent matching (INV-3); at most one accepted winner (INV-7) |

---

## 5. Contracts

### 5.1 REST endpoints

Summary of `03-backend-tasks.md` §2 (15 endpoints; auth chain + tenant-scope on every route, `auth.RequireVerified` on participatory writes; rate class `default`, tighter buckets on #1/#7/#13).

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST `/api/v1/tuition/requirements` | Guardian/Student (verified) | Create requirement → enqueue matching | `NOT_VERIFIED`, `VALIDATION_FAILED` | TUT-US-001/002 |
| 2 | GET `/api/v1/tuition/requirements` | Poster / School Admin | Own list · school oversight list | — | TUT-US-001/007/009 |
| 3 | PATCH `/api/v1/tuition/requirements/{id}` | Poster / School Admin | Edit while `open` · close (incl. abusive by admin) | `CONFLICT`, `FORBIDDEN` | TUT-US-009 |
| 4 | GET `/api/v1/tuition/tutors` | Any verified user | Browse verified tutors (public-safe; verified filter locked ON) | — | TUT-US-011 |
| 5 | GET `/api/v1/tuition/tutors/{id}` | Any verified user | Public profile; contact `null` unless accepted match links caller | `NOT_FOUND` (unverified invisible) | TUT-US-011/007 |
| 6 | POST `/api/v1/tuition/tutor-profile` | Verified user | Create/update own profile (draft-safe) | `NOT_VERIFIED`, `VALIDATION_FAILED` | TUT-US-003 |
| 7 | POST `/api/v1/tuition/tutor-profile/submit-for-review` | Profile owner | draft/rejected → pending_review | `CONFLICT`, `VALIDATION_FAILED` | TUT-US-003/010 |
| 8 | GET `/api/v1/school/tutor-verifications` | School Admin / Super Admin | Verification queue (own school / platform NULL rows) | `FORBIDDEN` | TUT-US-004/012 |
| 9 | POST `/api/v1/school/tutor-verifications/{id}/approve` | Routed reviewer | Approve (+ optional note) → profile verified | `CONFLICT`, `FORBIDDEN` | TUT-US-004 |
| 10 | POST `/api/v1/school/tutor-verifications/{id}/reject` | Routed reviewer | Reject; `decision_note` required | `CONFLICT`, `VALIDATION_FAILED`, `FORBIDDEN` | TUT-US-004/010 |
| 11 | GET `/api/v1/tuition/requirements/{id}/matches` | Poster | Matches list (notified count + interested detail) | `FORBIDDEN` | TUT-US-006/007 |
| 12 | POST `/api/v1/tuition/requirements/{id}/matches` | Internal (job only) | Matching write path for `NotifyMatches` — not routed publicly | — | TUT-US-005 |
| 13 | POST `/api/v1/tuition/matches/{id}/interest` | Tutor | Express interest | `CONFLICT`, `NOT_VERIFIED` | TUT-US-006 |
| 14 | POST `/api/v1/tuition/matches/{id}/accept` | Poster | Accept → reveal + chat + fee DUE fact (one tx) | `CONFLICT` (races), `FORBIDDEN`, `NOT_VERIFIED` | TUT-US-007 |
| 15 | POST `/api/v1/tuition/matches/{id}/decline` | Match party | Decline (counterpart notified, no contact leaked) | `CONFLICT` | TUT-US-006 |

### 5.2 Realtime / jobs

No realtime channel of its own — push delivery is module 06's (retried there); in-app lists are the source of truth. Jobs (`03` §5):

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `tuition.match` (TUT-BE-026) | `jobs.Enqueue` on requirement create (01 worker, cadence ≤ 60 s) | `NotifyMatches(requirementId)`: candidate query + rank + ≤10 inserts + pushes | matched tutors, poster | idempotent (UNIQUE pair + `ON CONFLICT DO NOTHING` + status re-check); alert after 3 failures; requirement stays `open` |
| `tuition.expiry` (TUT-BE-027) | Hourly | Expire stale open requirements + non-terminal matches; poster notice with re-post hint | poster, tutors | status-checked per row; re-run safe; notices retryable via 06 |
| `tuition.verification-reminder` (TUT-BE-028) | Daily | SLA reminder for `pending` reviews > 48 h (OQ-7 default) | reviewers | reminder-flag per row; skips silently when 06 down |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — DTOs only, domain errors, additive-first signatures.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `tuition.CreateRequirement(poster, in)` | REST #1 handler (app/web) | `RequirementDTO` (`open`, `expiresAt`); enqueues `tuition.match` | `NOT_VERIFIED`, `VALIDATION_FAILED` |
| `tuition.NotifyMatches(requirementID)` | 01 job worker (`tuition.match`); future re-match admin tool | `MatchResultDTO{notified, skipped}` (idempotent; pushes best-effort) | `NOT_FOUND`, `CONFLICT` (requirement not open) |
| `tuition.VerifiedTutorCount(schoolID)` | 07 landing/dashboard stats (later) | `int` — cached 600 s under `tuition:tutorcount:{schoolId}`; platform-level excluded per OQ-4 default | `NOT_FOUND` |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

Admin surface only; portal nav lives in module 07's shell.

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/institution/tutors` | Tutor-verification queue (tutor, university, subjects bn, SLA chip; Super Admin sees the প্ল্যাটফর্ম tab for NULL-school rows) | Server Component + Server Actions | School Admin / Super Admin |
| `/institution/tutors/[id]` | Verification detail + evidence viewer (05 media, short-lived R2 URLs; degraded placeholder) + approve/reject forms | Server Component + Client | School Admin (own school) / Super Admin (platform) |
| `/institution/tuitions` | Requirements oversight — read-only table; guarded close action with audit note | Server Component + Server Actions | School Admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/marketplace` | Marketplace home — Find-a-tutor card, requirement/match entries, `VerifiedGate` | none (tab root) | cached counts + offline banner |
| `/(tabs)/marketplace/find` · `/tutors/[id]` | Tutor browse (verified chip locked ON) + public profile with "Request as tutor" CTA (pre-filled wizard) | browse/profile tap | cache reads; refetch on reconnect |
| `/(tabs)/marketplace/requirements/new` | Post-requirement wizard (4 steps, shared zod, summary review) | profile CTA | **queued once** with banner; replayed once on reconnect |
| `/(tabs)/marketplace/requirements` · `/requirements/[id]` | My requirements (status chips, interested counts, expiry countdown) + detail with accept dialog, matched/expired states | push `type=tuition_interest` (detail) | accept/decline require connectivity (refused offline); lists cached |
| `/(tabs)/marketplace/matches` | Tutor-side matches + status tracker + interest CTA | push `type=tuition_match` | interest refused offline (list stays honest) |
| `/(tabs)/marketplace/tutor-setup` · `/tutor-setup/evidence` | Tutor profile editor (draft-safe, contact-regex guard) + evidence upload (05 media flow) + status tracker | push `type=tuition_verification` | draft saved locally; uploads resumable; submit needs connectivity |
| `/(tabs)/marketplace/premium` | Premium upsell (P2, disabled CTA, `TODO: Confirm` benefits) | none | n/a |
| `/(modals)/location-picker` | Area + map pin picker (`expo-location`, text fallback) | in-app | n/a |

---

## 7. External Integrations

From `06-integration-tasks.md` §5 — this module owns **no direct external system**; all externals are reached through module owners.

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| (none directly) | — | — | — | — | All externals via module owners: R2 via 05 media, FCM via 06 push, Redis limiter via 01 base |
| Cloudflare R2 (indirect via 05) | Evidence documents + profile photo storage | S3 presigned PUT/GET (05-owned) | 05-owned `R2_*` env | 05-owned | Evidence/photo upload blocked; profile stays `draft`; queue shows degraded placeholder |
| FCM (indirect via 06) | Match/interest/decision/expiry pushes + deep links | HTTPS Admin SDK (06-owned) | 06-owned `FCM_SERVER_KEY` | 06-owned retry queue | No push — matches + in-app lists unaffected (DB-first, never depends on push success) |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None module-specific | — | — | This module reads only the base 01 config (database/Redis/worker); R2 credentials live in 05, `FCM_SERVER_KEY` in 06 — never duplicated here |

### 8.2 Runtime config — the two lists

From `02-solution-approach.md` §5.

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Match radius (default 5 km) · top N (default 10) · expiry (14 days) · verification SLA reminder (48 h) | Verified-only matching and browse (BR-002/003) |
| Rate-limit buckets (class `default`) | In-app-first negotiation; cross-school only via Message Request (BR-007) |
| Evidence caps per kind (delegated to 05 media caps) | Magic-byte-sniffed evidence (05 owns the sniffer) |
| Subject/class-level catalogs (seed + admin add) | Rule-based ranking (subject coverage, haversine distance) — no model calls |
| Fee-model constants — `TODO: Confirm` (OQ-1) before any value ships | DUE-on-accept fee fact (INV-8); collection belongs to module 12 |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope on every entry (`02` §6); participatory writes add `auth.RequireVerified` (`NOT_VERIFIED` otherwise) |
| Role matrix | Guardian/Student: post/edit/close own requirements, browse, accept/decline own matches · verified user with a profile: tutor setup/evidence/interest/decline · School Admin: own-school verification queue + read-only oversight (+ close abusive) · Super Admin: platform queue for `school_id` NULL rows · everyone else: no marketplace surface |
| Tenant scope | Requirements/oversight scoped `school_id = caller.schoolId`; own profile row-level `user_id`; verification queues scoped via `tutor_profiles.school_id` (platform rows invisible to School Admins); matches straddle tenants by design — row-level party check; cross-tenant attempts → `TENANT_MISMATCH`/404 (TUT-IT-003/013) |
| Rate limits | Class `default` on every route (BR-014); tighter per-user buckets on wizard submit, submit-for-review and interest |
| Audit events | `audit.Record`: verification approve/reject (note with decision, BR-010), School Admin close, accept (the fee event, BR-012) — ids only |
| Privacy / minors | Contact reveal staged: contact fields `null` in every DTO until the guardian accepts that tutor's interest (INV-4, computed per request); evidence visible only to the routed reviewer + owning tutor (INV-6, TUT-IT-006/016); push/browse payloads carry ids + subject labels only — never contact; phones/emails/URLs regex-rejected in bio/availability (BR-007); browse exposes only public-safe verified fields |

---

## 10. Error Handling

All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via each app's `src/i18n` catalogs — every message key ships in **bn + en** (Bengali default), e.g. `validation.tuition.*`.

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `NOT_VERIFIED` | Account pending verification | Any participatory write: post, tutor setup, submit-for-review, interest | `VerifiedGate` screen with module 03 how-to-get-verified copy |
| `CONFLICT` | Illegal transition or lost race | Interest on closed/expired/matched, second accept, resubmit while review pending, edit closed requirement | Polite toast + refetch ("already matched" / "status changed"); list refreshes |
| `TENANT_MISMATCH` / `NOT_FOUND` | Cross-tenant probe / invisible or unknown row | Foreign queue/oversight rows; unverified tutor profile detail (hidden) | Branded 404 — no data leak; empty state or polite back-redirect |
| `VALIDATION_FAILED` | Bad input | Subjects catalog, budget `min ≤ max`, geo bounds, reject-note missing, bio contact-info | Field messages from `validation.tuition.*`, bn-first |
| `FORBIDDEN` | Wrong role/party | Non-reviewer decision, foreign match, non-poster accept | Refusal + support path |
| `UNAUTHENTICATED` / `RATE_LIMITED` / `INTERNAL` | Standard envelope | Every route / limiter / infra | Re-auth; retry later; error boundary with request id |

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog JSON (01 base); module payloads carry ids + labels only — never contact fields, evidence refs or free-text bios (BR-007; asserted by TUT-UT-011) |
| Metrics / counters | Verification queue depth, matches per requirement, zero-match rate, job lag (`tuition.match` ≤ 60 s, `tuition.expiry` hourly) |
| Health contribution | No dedicated check — Postgres/Redis/worker health flows through the 01 base `/readyz` |
| Jobs & retries | 3 jobs (match, expiry, reminder) — all idempotent, queued as rows; alerts after 3 failures; push delivery retried by 06's queue |
| Runbook pointers | 01/15 runbooks: Neon pool alarm + failover path, worker-lag alarm (matching/expiry delay, no data loss), Redis cache/limiter fallback (DB is source of truth) |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Candidate ranker, bbox math + Bangladesh bounds, requirement/match state machines, DTO contact-null mapper, validation rules, contact-info regex, tag invalidation set, push payload builder (ids + labels only) | `TUT-UT-001`–`011` | `go test` green |
| Integration | Match-query correctness (verified/subject/radius filters), **contact reveal across both DTO shapes until accept** (TUT-IT-002/012), cross-tenant denial, `NOT_VERIFIED` seams, expiry idempotency, evidence visibility, matching idempotency, accept race + fee fact exactly once, chat seam (DM vs Message Request), auth chain, 06-down degradation | `TUT-IT-001`–`017` | testcontainers Postgres green in CI |
| E2E | Maestro golden path: guardian posts → tutor receives match → interest → accept → chat opens with contact revealed | `TUT-E2E-001` | CI smoke (app) |
| CI | — | — | `go test/vet/lint` (api) + `pnpm lint/typecheck/test/build` (web/app). Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; cross-tenant attempts → `TENANT_MISMATCH`/404; `TODO: Confirm` fee values never render in any payload; public reads never return draft/unverified profiles or evidence |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot (3 schools × ~2,000 users): ~200 requirements/month, ~1,000 tutor profiles, ≤ ~50 matches per requirement — small tables, indexes designed for 10× (BRD year-1 target) |
| Hot paths + indexes | Matching: partial btree `status='verified'` + GIN `(subjects) ?|` + bbox `lat/lng BETWEEN` (Δlat ≈ 0.0449° at 5 km, Δlng = Δlat/cos(lat)), haversine ranking in Go — **no PostGIS** until candidate sets exceed ~10k rows (ADR, `02` §10) |
| Latency targets | Browse p95 ≤ 100 ms cached / ≤ 250 ms uncached (Neon); requirement→notification job start ≤ 60 s after post; push delivery is 06's budget |
| Bundle / payload impact | No new heavy dependencies — `expo-location` + lightest map (or static-map pin + manual area text fallback) |
| Caching | Redis: `tuition:tutors:{area}` 120 s · `tuition:tutor:{id}` 300 s · `tuition:tutorcount:{schoolId}` 600 s; requirements/matches/queues are per-user and never cached; invalidations per `06` §4 |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 and `02` §11 — the table to review in module readiness checks; unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Fee model: 50% of first month per match vs BDT 300/month premium vs both (`brd.md` §7) | Rework of the accept flow | Rahul | Open (`TODO: Confirm`) | DUE fact on acceptance citing the §7 proposals; collection in module 12; no invented figures |
| 2 | Verification routing: poster's vs tutor's linked school; platform ops for NULL | Queue misrouting | Rahul | Open | Linked-school admin when `school_id` set; platform ops for NULL |
| 3 | Match defaults: 5 km radius, top N = 10, 14-day expiry | Tuning | Rahul | Open | As stated; owner-tunable config, not code |
| 4 | Platform-level (`school_id` NULL) university tutors in Phase 2? | Supply shape | Rahul | Open | Yes, platform-ops-reviewed |
| 5 | Premium subscription benefits + purchase flow (module 12) | Upsell copy | Rahul | Open | §7 proposal shown, `TODO: Confirm` benefits, disabled CTA |
| 6 | Do post-approval profile edits re-trigger review? | Reviewer workload | Rahul | Open | Evidence-backed fields re-submit; bio/availability/photo do not |
| 7 | Supply-side cold start + verification review SLA (48 h) | Empty matches; tutor churn while pending | Rahul | Open | Browse-first empty states ("be the first verified tutor"), admin-led onboarding, SLA reminder job |
| 8 | Location spoofing (pin ≠ reality) | Wrong matches | Rahul | Open | Bangladesh-bounds validation, area+pin consistency check, radius is config, admin close abuse path |
| 9 | Contact leakage via free-text fields | BR-007 breach | — | Mitigated in spec | Regex rejection + DTO contract tests (TUT-IT-002/012) |
| 10 | Cross-school trust (tutor from school B tutors school A's child) | School discomfort | Rahul | Open | Verification + badge, staged reveal, in-app chat only; Message Request gives explicit consent |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-03 | §5.3 (matching, profiles, verification) · §4B (Marketplace tab) | TUT-US-001–013 | TUT-BE-001–033 · TUT-FE-001–008 · TUT-AP-001–016 · TUT-INT-001–012 | TUT-UT-001–011 · TUT-IT-001–017 · TUT-E2E-001 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-04 | SCOPE: tuitions are independent of institutions (owner). Public marketplace `/tuition` (+post, +register): guardians/students post requirements; any Kushol user registers as a tutor, auto-match (subject+class+area) notifies them; Kushol arranges interviews — physical meet or online (venue/link); tutors rated 1–5 (running average). Institution-side verification/oversight unchanged (`/institution/tuitions`). Additive contracts listed in 07-progress | Kilo |
| 2026-10-03 | Build executed contract-first: 15 REST paths (14 routed + tracker GET) + 26 `Tuition*` schemas landed in the api spec before any UI; INV-4 contact/chat nullability encoded in the contract; additive push types `tuition_match`/`tuition_interest`/`tuition_verification` in 06's frozen builder (bn/en copy api-side); matching = bbox+haversine ranker (subject coverage ↓, distance ↑, stable ties) with idempotent `ON CONFLICT DO NOTHING` inserts; accept tx emits the fee-DUE audit fact (INV-7/8) and opens 05's DM/Message-Request seam with a degraded `{pending}` handle; cache invalidation via the shared tag cache (`tuition:tutors:{area}` / `tuition:tutor:{id}` / `tuition:tutorcount:{schoolId}`); migrations `20261120090000–093000`. App: live client behind the session-token selector; web: fixture seam until 07's console session glue (G-8). Seed deferred (G-7). | Kilo |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migrations re-versioned `20261120…` (were colliding with 08's `20261101…`) | Claude |
