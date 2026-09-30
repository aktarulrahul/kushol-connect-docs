# Tuition Marketplace — Backend Tasks & Database Design

**Module:** `10-tuition-marketplace`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging · jobs via module 01 worker
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api (School Admin verification queue + requirements oversight)
**Last updated:** 2026-09-30

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `tuition_requirements` (model `TuitionRequirement`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `poster_id` | `uuid` | no | — | FK → 03 `users`; role Guardian or Student (`poster_role` derived from claim, stored for display) |
| `school_id` | `uuid` | no | — | **Tenant column** = poster's school (04 node); every tenant-scoped query filters on it |
| `subjects` | `jsonb` | no | — | Array of shared-catalog keys, 1–5 items (`["math","physics"]`) |
| `class_level` | `text` | no | — | Catalog key (`class_6` … `ssc`, `hsc`) |
| `budget_min` | `int` | no | — | BDT ≥ 0 |
| `budget_max` | `int` | no | — | BDT ≤ 1,000,000; `budget_min ≤ budget_max` (CHECK) |
| `gender_pref` | `text` | no | `any` | `any` \| `male` \| `female` (CHECK) |
| `location_area` | `text` | no | — | 2–80 chars (display) |
| `lat` / `lng` | `double precision` | no | — | Matching point; Bangladesh bounds validated in service |
| `schedule_note` | `text` | yes | — | ≤ 500 chars plain text |
| `status` | `text` | no | `open` | `open` \| `matched` \| `closed` \| `expired` (CHECK) |
| `expires_at` | `timestamptz` | no | `now() + 14 days` | Expiry job cursor |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK `budget_min ≤ budget_max`; CHECK status/gender enums; poster must be
VERIFIED (service, via `auth.RequireVerified`). **Indexes:** `(poster_id, status)` → my-requirements
list; `(school_id, status)` → School Admin oversight; `(status, expires_at) WHERE status='open'`
→ expiry job; GIN `(subjects)` → (defensive) subject lookups from the requirement side.

#### `tutor_profiles` (model `TutorProfile`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → 03 `users`, UNIQUE; must be VERIFIED (service) |
| `school_id` | `uuid` | yes | — | **Tenant column** when set (tutor's own school); **NULL = platform-level** university tutor (`TODO: Confirm` launch policy — OQ-4) |
| `university` | `text` | no | — | 2–120 chars |
| `subjects` | `jsonb` | no | — | Array of catalog keys, 1–5 |
| `classes_taught` | `jsonb` | no | — | Array of class-level keys, ≥ 1 |
| `bio_bn` / `bio_en` | `text` | yes | — | ≤ 1000 chars each; ≥ 1 required (service); contact info regex-rejected |
| `hourly_rate_hint` | `int` | yes | — | BDT 0–5000; display hint only, never a charge |
| `availability` | `text` | yes | — | ≤ 500 chars free text (e.g. "শনি–বৃহস্পতি, বিকাল ৪টা–রাত ৮টা") |
| `location_area` | `text` | yes | — | 2–80 chars |
| `lat` / `lng` | `double precision` | yes | — | Matching point; required before submit-for-review |
| `photo_media_id` | `uuid` | yes | — | FK → 05 `media_assets` (confirmed image) |
| `status` | `text` | no | `draft` | `draft` \| `pending_review` \| `verified` \| `rejected` \| `suspended` (CHECK) |
| `verified_at` | `timestamptz` | yes | — | Set on approval |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(user_id)` — one profile per user; CHECK status enum. **Indexes:**
UNIQUE `(user_id)` → profile lookup; partial `(id) WHERE status='verified'` + GIN `(subjects)` +
`(lat, lng)` → the matching/browse hot query; `(status, updated_at)` → review-queue joins;
`(school_id)` → school stats.

#### `tutor_verifications` (model `TutorVerification`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `tutor_profile_id` | `uuid` | no | — | FK → `tutor_profiles` |
| `national_id_media_id` | `uuid` | no | — | FK → 05 `media_assets` (confirmed image/PDF) |
| `evidence_media_ids` | `jsonb` | no | — | Array of media refs (subject evidence, ≥ 1) |
| `reviewer_id` | `uuid` | yes | — | FK → 03 `users`; set on decision (School Admin / Super Admin) |
| `reviewer_scope` | `text` | yes | — | `school` \| `platform`; matches the routed queue |
| `status` | `text` | no | `pending` | `pending` \| `approved` \| `rejected` |
| `decision_note` | `text` | yes | — | Required on reject (5–500); readable by the tutor (BR-010) |
| `decided_at` | `timestamptz` | yes | — | |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** partial UNIQUE `(tutor_profile_id) WHERE status='pending'` (one open review);
CHECK `status='rejected' ⇒ decision_note IS NOT NULL`. **Indexes:** `(status, created_at)` →
queues; partial pending index → submit-for-review guard. **Tenant rule:** scoped **through
`tutor_profiles.school_id`** — a School Admin's queue is `profiles.school_id = caller.schoolId`;
`school_id IS NULL` rows are the platform queue (Super Admin only); owning tutor reads own
outcome. Routing nuance (poster's school vs linked school) is OQ-2 — the default routes by linked
school, which coincides with the poster's school in the same-school case.

#### `tuition_matches` (model `TuitionMatch`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `requirement_id` | `uuid` | no | — | FK → `tuition_requirements` |
| `tutor_profile_id` | `uuid` | no | — | FK → `tutor_profiles` |
| `status` | `text` | no | `notified` | `notified` \| `interested` \| `accepted` \| `declined` \| `expired` (CHECK) |
| `notified_at` | `timestamptz` | no | `now()` | Push dispatched (06 may retry independently) |
| `responded_at` | `timestamptz` | yes | — | First tutor/poster response (interest/accept/decline) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(requirement_id, tutor_profile_id)` (idempotent matching, INV-3);
partial UNIQUE `(requirement_id) WHERE status='accepted'` (one winner, INV-7). **Indexes:**
`(requirement_id, status)` → poster's match list; `(tutor_profile_id, status)` → tutor's match
list. **Tenant rule:** none — a match straddles two schools by design; row-level party
authorization (poster of the requirement / user of the profile) replaces tenant scope; the
requirement-side join re-applies the tenant filter.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261120090000_tut_requirements` (tuition_requirements + status/budget CHECKs + list/expiry indexes) | ✅ |
| 2 | `20261120091000_tut_tutor_profiles` (tutor_profiles + verified partial + GIN subjects + geo columns) | ✅ |
| 3 | `20261120092000_tut_tutor_verifications` (verifications + partial unique pending + reject-note CHECK) | ✅ |
| 4 | `20261120093000_tut_matches` (matches + UNIQUE pair + single-accepted partial) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| "Demo High School" (fictional, marked): 2 requirements (Dhaka areas, ৳2,000–4,000/mo hints), 3 tutor profiles (1 same-school `verified`, 1 platform-level `pending_review`, 1 `rejected` with note), 1 verification approved + 1 pending, 3 matches (notified/interested/accepted) | `DRAFT` (clearly fictional; universities/areas fictional) | `prd.md` §5.3 shapes; prices are fictional demo values, not fee figures (`prompt.txt` §12) |

---

## 2. Server Contracts

### Endpoint summary (all Go handlers generated from the OpenAPI spec; auth chain on every route: authenticate → load role claims → tenant-scope; participatory writes add `auth.RequireVerified`)

| # | Endpoint | Purpose | Errors (beyond common) | Stories |
| --- | --- | --- | --- | --- |
| 1 | `POST /api/v1/tuition/requirements` | Create requirement (Guardian/Student) → enqueue matching | `NOT_VERIFIED`, `VALIDATION_FAILED` | US-001/002 |
| 2 | `GET /api/v1/tuition/requirements` | Poster: own list. School Admin role: school oversight list (read-only) | — | US-001/007/009 |
| 3 | `PATCH /api/v1/tuition/requirements/{id}` | Edit (open only) / close (poster; School Admin may close abusive) | `CONFLICT`, `FORBIDDEN` | US-009 |
| 4 | `GET /api/v1/tuition/tutors?subject=&area=&cursor=` | Browse verified tutors (public-safe DTO; verified filter locked ON) | — | US-011 |
| 5 | `GET /api/v1/tuition/tutors/{id}` | Verified public profile; contact fields `null` unless an accepted match links the caller | `NOT_FOUND` (unverified profiles invisible) | US-011/007 |
| 6 | `POST /api/v1/tuition/tutor-profile` | Create/update own profile (draft-safe) | `NOT_VERIFIED`, `VALIDATION_FAILED` | US-003 |
| 7 | `POST /api/v1/tuition/tutor-profile/submit-for-review` | draft/rejected → pending_review (evidence complete) | `CONFLICT`, `VALIDATION_FAILED` | US-003/010 |
| 8 | `GET /api/v1/school/tutor-verifications` | Queue: School Admin (own school) / Super Admin (platform, `school_id` NULL) | `FORBIDDEN` | US-004/012 |
| 9 | `POST /api/v1/school/tutor-verifications/{id}/approve` | Approve + optional note → profile verified | `CONFLICT` (non-pending), `FORBIDDEN` | US-004 |
| 10 | `POST /api/v1/school/tutor-verifications/{id}/reject` | Reject; `decision_note` required | `CONFLICT`, `VALIDATION_FAILED`, `FORBIDDEN` | US-004/010 |
| 11 | `GET /api/v1/tuition/requirements/{id}/matches` | Poster's matches (notified count + interested detail) | `FORBIDDEN` | US-006/007 |
| 12 | `POST /api/v1/tuition/requirements/{id}/matches` | **Internal** — matching job write path (`tuition.NotifyMatches`); not routed publicly | — | US-005 |
| 13 | `POST /api/v1/tuition/matches/{id}/interest` | Tutor expresses interest | `CONFLICT` (state), `NOT_VERIFIED` | US-006 |
| 14 | `POST /api/v1/tuition/matches/{id}/accept` | Guardian accept → reveal + chat + fee DUE fact (tx) | `CONFLICT` (races, BR-009) | US-007 |
| 15 | `POST /api/v1/tuition/matches/{id}/decline` | Tutor or poster declines | `CONFLICT` | US-006 |

Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` ·
`TENANT_MISMATCH` · `NOT_FOUND` · `NOT_VERIFIED` · `RATE_LIMITED` · `CONFLICT` · `INTERNAL`
(RFC-7807 `application/problem+json`). **Rate-limit class `default`** on all routes (tighter
per-user buckets on #1/#7/#13).

### Detailed endpoint blocks

### Endpoint `POST /api/v1/tuition/requirements` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope → verified gate |
| **Input** | `{subjects[], classLevel, budgetMin, budgetMax, genderPref, locationArea, lat, lng, scheduleNote?}`; contract-generated validator; request struct from `oapi-codegen` |
| **Result** | `{ "data": { requirement } }` incl. `status:"open"`, `expiresAt`; enqueues `tuition.match` job |
| **Errors** | `NOT_VERIFIED` · `VALIDATION_FAILED` (subjects/catalog/budget/geo) · `RATE_LIMITED` |
| **Rate limit** | class `default`, tight per-user bucket |
| **Audit** | No (creation is routine; admin close and accept are audited) |
| **Stories** | TUT-US-001/002 |

### Endpoint `POST /api/v1/tuition/matches/{id}/accept` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope (requirement side) → verified gate |
| **Input** | path match id; empty body |
| **Result** | `{ "data": { match, contact: {…}, chat: { dmGroupId \| messageRequestId } } }` — contact + chat handle revealed to the tutor via their DTO; poster's view flags the match accepted. Single transaction: match `accepted` + requirement `matched` + audit + fee DUE fact (INV-7/8) |
| **Errors** | `CONFLICT` (already matched/closed/expired, second-accept race) · `FORBIDDEN` (not the requirement's poster) · `NOT_VERIFIED` |
| **Rate limit** | class `default` |
| **Audit** | Yes — the fee event (`audit.Record`), reviewer-free |
| **Stories** | TUT-US-007 · guards TUT-BR-006/009/012 |

### Endpoint `GET /api/v1/tuition/tutors/{id}` + `POST /api/v1/school/tutor-verifications/{id}/approve|reject`

| | |
| --- | --- |
| **Auth** | tutors/{id}: any verified user (public DTO; contact `null` unless an accepted match links caller ↔ tutor). approve/reject: routed reviewer only — School Admin of the linked school or Super Admin (platform rows) |
| **Input** | profile detail: path id (query `intent=match` when opened from a match, adds match-scoped fields). approve: `{note?}`. reject: `{decisionNote}` (5–500) |
| **Result** | detail: public-safe profile DTO (`status` only exposed as `verified`/404). decisions: `{verification}`; profile status + `verified_at` updated; 06 notification; `audit.Record` |
| **Errors** | `NOT_FOUND` (unverified profile) · `FORBIDDEN` (non-reviewer, cross-tenant queue) · `CONFLICT` (non-pending) · `VALIDATION_FAILED` (missing reject note) |
| **Rate limit** | class `default` |
| **Audit** | Yes — both decisions (BR-010) |
| **Stories** | TUT-US-004/010/011/012 |

### Web Server Action / Route Handler (Next.js)

The web build consumes the Go API through the generated `openapi-fetch` client — never the
database directly. Module 07 owns the portal shell/nav; this module owns the screens:

- `/school/tutors` + `/school/tutors/[id]` — verification queue + evidence viewer
  (endpoints #8/#9/#10; media URLs via 05's short-lived R2 downloads).
- `/school/tuitions` — requirements oversight (endpoint #2 with School Admin role + #3 close
  action).

Same auth (web session) + zod input validation mirroring `validation.tuition.*` + RFC-7807 error
mapping.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `TUT-BE-001` | `tuition.CreateRequirement(poster, in)` | Verified gate; catalog + budget + geo-bounds validation; `expires_at = now()+14d`; enqueues `tuition.match` via `jobs.Enqueue` | — | No |
| `TUT-BE-002` | `tuition.ListMyRequirements(poster)` / `ListSchoolRequirements(admin)` | Poster: own rows; School Admin: tenant oversights list (read-only + close) | — | No |
| `TUT-BE-003` | `tuition.UpdateRequirement(actor, id, in)` | Poster edit while `open` only; close by poster (own) or School Admin (tenant, abusive); close notifies interested tutors | — | Yes (admin close) |
| `TUT-BE-004` | `tuition.BrowseTutors(filters)` | `status='verified'` only; public-safe DTO; area/subject filters; cache read-through | `tuition:tutors:{area}` | No |
| `TUT-BE-005` | `tuition.GetTutorProfile(caller, id)` | Public-safe DTO; contact fields `null` unless an `accepted` match links caller ↔ tutor (INV-4) | `tuition:tutor:{id}` | No |
| `TUT-BE-006` | `tuition.UpsertTutorProfile(user, in)` | Verified user; one profile per user; draft-safe; contact-info regex guard on free text | `tuition:tutor:{id}` | No |
| `TUT-BE-007` | `tuition.SubmitForReview(user)` | Evidence complete (national ID + ≥1 subject evidence, media `confirmed`); geo set; no existing `pending` review; status → `pending_review`; SLA reminder armed | — | No |
| `TUT-BE-008` | `tuition.ListVerificationQueue(reviewer)` | School Admin: linked-school rows; Super Admin: platform rows; evidence refs returned as reviewer-only media handles | — | No |
| `TUT-BE-009` | `tuition.ApproveVerification(reviewer, id, note?)` | Pending only; routed reviewer; profile → `verified` + `verified_at`; tutor notified via 06; busts tutor tags | `tuition:tutors:{area}` · `tuition:tutor:{id}` | Yes |
| `TUT-BE-010` | `tuition.RejectVerification(reviewer, id, note)` | Pending only; note required; profile → `rejected`; tutor notified with note | `tuition:tutor:{id}` | Yes |
| `TUT-BE-011` | `tuition.NotifyMatches(requirementId)` — **job entry** | Requirement `open` ∧ unexpired; candidate query (BR-003) + rank (BR-004); insert ≤ 10 `notified` rows `ON CONFLICT DO NOTHING`; `notify.SendToUser` per tutor (deep link) | — | No |
| `TUT-BE-012` | `tuition.ExpressInterest(tutor, matchId)` | Match `notified`; tutor profile `verified` (not suspended); requirement `open`; status → `interested`; poster notified | — | No |
| `TUT-BE-013` | `tuition.AcceptMatch(poster, matchId)` | Poster owns requirement; match `interested`; single tx: match `accepted` + requirement `matched`; opens chat (same-school DM / cross-school Message Request via 05); fee DUE fact + audit; contact unlocked (INV-4/7/8) | — | Yes |
| `TUT-BE-014` | `tuition.DeclineMatch(actor, matchId)` | Party of the match; from `notified`/`interested`; counterpart notified politely | — | No |
| `TUT-BE-015` | `tuition.ExpireRequirements()` — **job entry** | `open ∧ expires_at < now()` → `expired`; non-terminal matches → `expired`; poster notice with re-post hint | — | No |
| `TUT-BE-016` | `tuition.VerifiedTutorCount(schoolId)` — **export** | Count of `verified` profiles linked to school (platform-level excluded per OQ-4 default) | `tuition:tutorcount:{schoolId}` | No |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `TUT-BE-017` | `InsertRequirement / ListRequirementsByPoster / ListRequirementsBySchool / UpdateRequirementStatus` | tenant-scoped SELECT/UPDATE; status-guarded transitions | `(poster_id, status)` · `(school_id, status)` |
| `TUT-BE-018` | `SelectOpenExpired(limit)` | `WHERE status='open' AND expires_at < now()` | partial `(status, expires_at) WHERE status='open'` |
| `TUT-BE-019` | `UpsertTutorProfile / GetTutorProfileByUser / GetTutorProfileByID` | row-level by `user_id`; public DTO assembled in service | UNIQUE `(user_id)` |
| `TUT-BE-020` | `SelectMatchCandidates(req, bbox, limit)` | `WHERE status='verified' AND subjects ?| $1 AND classes_taught ? $2 AND lat BETWEEN … AND lng BETWEEN …` | partial verified + GIN `(subjects)` + `(lat, lng)` |
| `TUT-BE-021` | `BrowseVerifiedTutors(subject?, area?, cursor)` | `WHERE status='verified'` + filters, keyset pagination | partial verified |
| `TUT-BE-022` | `InsertVerification / SelectQueueBySchool / SelectQueueByPlatform / DecideVerification` | status-guarded; queue joined to profiles for routing scope | `(status, created_at)` + partial pending |
| `TUT-BE-023` | `InsertMatch (ON CONFLICT DO NOTHING) / ListMatchesByRequirement / ListMatchesByTutor / UpdateMatchStatus` | party-scoped; status-guarded transitions | `(requirement_id, status)` · `(tutor_profile_id, status)` + UNIQUE pair |
| `TUT-BE-024` | `SelectAcceptedMatch(requirementId)` | single-winner read for contact-reveal decisions | partial `(requirement_id) WHERE status='accepted'` |
| `TUT-BE-025` | `CountVerifiedTutors(schoolId)` | `WHERE status='verified' AND school_id=$1` | partial verified + `(school_id)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `TUT-BE-026` | `tuition.match` — run `NotifyMatches(requirementId)` (§3 `TUT-BE-011`) | `jobs.Enqueue` on requirement create (module 01 worker; cadence ≤ 60 s) | Yes — `ON CONFLICT DO NOTHING` + status re-check | Re-run safe; alerts after 3 failures; requirement stays `open` |
| `TUT-BE-027` | `tuition.expiry` — expire stale requirements + matches (§3 `TUT-BE-015`) | Hourly | Yes — status-checked per row | Batch resumes; poster notices enqueue via 06 (retryable) |
| `TUT-BE-028` | `tuition.verification-reminder` — SLA reminder for `pending` reviews > 48 h | Daily | Yes — reminder-flag on the row | Skips silently when 06 is down (OQ-7 default) |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `TUT-UT-001` | Candidate ranker: subject coverage ↓ then haversine ↑; top-N cut; ties stable | Unit | BR-003/BR-004 |
| `TUT-UT-002` | Bbox math: Δlat/Δlng for 5 km at Dhaka latitude; Bangladesh-bounds rejection | Unit | `02` §9 geo approach |
| `TUT-UT-003` | Requirement/match state machines: every illegal transition → `CONFLICT` | Unit | INV-2, BR-009 |
| `TUT-UT-004` | DTO mapper: contact fields `null` without accepted link; populated only for the accepted pair | Unit | BR-006 / INV-4 |
| `TUT-UT-005` | Validation: subjects catalog, budget `min ≤ max`, geo bounds, reject-note required | Unit | §6 rules |
| `TUT-UT-006` | Contact-info regex guard rejects phones/emails/URLs in bio/availability | Unit | BR-007 |
| `TUT-IT-001` | Match-query correctness: subject + class overlap + radius + `verified`-only filters against seeded fixtures; out-of-radius/out-of-subject/suspended excluded (testcontainers Postgres) | Integration | BR-002/003 |
| `TUT-IT-002` | Contact reveal: browse/detail/requirement payloads carry `null` contact until accept; after accept the accepted pair sees contact in **both** API shapes (poster and tutor DTOs) | Integration | BR-006 / INV-4 |
| `TUT-IT-003` | Cross-tenant queue + oversight access denied (`TENANT_MISMATCH`/404); platform rows invisible to School Admins | Integration | BR-013 / INV-6 |
| `TUT-IT-004` | Unverified poster/tutor blocked (`NOT_VERIFIED`) on create/submit/interest | Integration | BR-001 |
| `TUT-IT-005` | Expiry job: open+stale → `expired`, matches `expired`, poster notice recorded; idempotent re-run | Integration | BR-008 |
| `TUT-IT-006` | Evidence visibility: evidence media handles resolvable only for routed reviewer + owner; absent from browse/detail/browse-cache payloads | Integration | BR-011 / INV-6 |
| `TUT-IT-007` | Matching idempotency: doubled job run → same match rows, no duplicate pushes | Integration | BR-005 / INV-3 |
| `TUT-IT-008` | Accept race: two concurrent accepts → one `accepted`, requirement `matched`, loser `CONFLICT`; fee DUE fact emitted exactly once | Integration | BR-009/012 / INV-7/8 |
| `TUT-IT-009` | Negotiation seam: same-school accept opens DM via 05; cross-school accept creates Message Request via 05 (05 faked) | Integration | BR-007 |
| `TUT-IT-010` | Every protected endpoint unauthenticated → `UNAUTHENTICATED`; validation rejects bad input on every write | Integration | Auth chain |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
`TODO: Confirm` fee values never render in any payload; public reads never return draft/unverified
profiles or evidence.

## 7. Task Checklist

### Schema

- [ ] `TUT-BE-017`–`TUT-BE-019`, `TUT-BE-022`, `TUT-BE-023` migrations 1–4 + sqlc queries + tenant/party-scoped repositories

### Repository · Service · Entry points · Seed · Tests

- [ ] `TUT-BE-001`–`003` requirement services + endpoints #1/#2/#3 + matching-job enqueue
- [ ] `TUT-BE-004`/`005` browse + profile DTO services (cache read-through, contact-null rule) + endpoints #4/#5
- [ ] `TUT-BE-006`/`007` tutor profile + submit-for-review + media evidence wiring (05) + endpoints #6/#7
- [ ] `TUT-BE-008`–`010` verification queue + decisions + audit + 06 notifications + endpoints #8–#10
- [ ] `TUT-BE-011` matching job (`NotifyMatches`) + endpoint #12 internal write path
- [ ] `TUT-BE-012`–`014` match lifecycle services + endpoints #11/#13–#15 (accept tx incl. chat seam + fee fact)
- [ ] `TUT-BE-015`/`TUT-BE-027` expiry job; `TUT-BE-028` SLA reminder
- [ ] `TUT-BE-016`/`TUT-BE-025` `VerifiedTutorCount` export (07 handoff)
- [ ] OpenAPI paths #1–#15 in `contracts/openapi/` + regenerate Go + TS clients
- [ ] Seed: Demo High School dataset (fictional, marked)
- [ ] Tests: `TUT-UT-001`–`006`, `TUT-IT-001`–`010` green in CI
