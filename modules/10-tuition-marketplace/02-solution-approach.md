# Tuition Marketplace — Solution Approach

**Module:** `10-tuition-marketplace` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `tuition_requirements` | A poster's need: subjects (jsonb, catalog keys), class level, budget ৳ min/max, gender pref, area + geo point, schedule note; `status ∈ open\|matched\|closed\|expired`, `expires_at` | Yes |
| `tutor_profiles` | A senior's offer: university, subjects, classes taught, bio bn/en, rate hint, availability, area + geo point; `school_id` nullable (platform-level university tutors, `TODO: Confirm`); `status ∈ draft\|pending_review\|verified\|rejected\|suspended`, `verified_at` | Yes |
| `tutor_verifications` | Review record: evidence media refs (national ID + subject evidence via 05 `media_assets`), reviewer (School Admin of the routed queue / platform ops), `status ∈ pending\|approved\|rejected`, decision note, decided at | Yes |
| `tuition_matches` | The join: requirement × tutor profile, `status ∈ notified\|interested\|accepted\|declined\|expired`, notified/responded timestamps; `UNIQUE(requirement_id, tutor_profile_id)` | Yes |
| User (verified) + role/school claims | Poster and tutor identity; verification gate | No — module 03 (`users`, `auth.RequireVerified`) |
| Hierarchy nodes (school/section/class levels) | Poster tenant context; class-level catalog source | No — module 04 (`hierarchy.ResolveUserNodes`) |
| DM rooms + Message Requests · `media_assets` | Negotiation channel after accept (same-school DM / cross-school request); evidence docs + profile photos (sniffed) | No — module 05 (`chat`, `message_requests`, `media.*`) |
| Push delivery | Match/decision/interest notifications + deep links | No — module 06 (`notify.*`) |

### 1.2 Relationships

```text
user (03) 1───* tuition_requirements (poster)      school (04) 1───* tuition_requirements (tenant)
user (03) 1───1 tutor_profiles ─0..1 school (04)   (NULL = platform-level)
tutor_profiles 1───* tutor_verifications *───* media_assets (05; evidence)
tuition_requirements 1───* tuition_matches *───1 tutor_profiles   UNIQUE(req, tutor)
tuition_matches ──accepted──▶ contact reveal + chat.DM / message_requests (05) + fee DUE fact (12, later)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-1 | Requirement/oversight queries are tenant-scoped by the poster's `school_id`; the tutor browse is deliberately cross-school but exposes only public-safe verified fields — never contact, never evidence | Repository scoping + DTO mapper |
| INV-2 | Requirement transitions are only `open→matched` (accept), `open→closed` (poster/School Admin), `open→expired` (job); closed/expired/matched requirements reject edits and new interest | Service state machine + `CONFLICT` |
| INV-3 | `UNIQUE(requirement_id, tutor_profile_id)` — the matching job is idempotent; one match row per pair | DB unique index |
| INV-4 | Contact fields are `null` in every DTO until a match between the viewer and the counterpart is `accepted`; reveal is computed per-request from the match, never denormalized onto profiles | Service DTO mappers (`TUT-IT-002`) |
| INV-5 | Only `verified` profiles enter matching and browse; the badge is a projection of `status` + `verified_at`, never a stored flag | Job query + repository WHERE |
| INV-6 | Evidence media refs are readable only by the routed reviewer role and the owning tutor; at most one `pending` verification per profile | Partial unique index + service authorization |
| INV-7 | At most one `accepted` match per requirement; accept is a single transaction updating match + requirement (+ audit event); the match-fee DUE fact (BR-012) is emitted exactly once per acceptance — module 12 consumes it (additive seam) | Partial unique index `(requirement_id) WHERE status='accepted'` + tx |

## 2. Module Boundary

**Owns (writes):** `tuition_requirements`, `tutor_profiles`, `tutor_verifications`, `tuition_matches` — and the matching/expiry jobs over them.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | Verified gate (`auth.RequireVerified`), `users` identity/claims | Verification is identity's source of truth (`prd.md` §5.1) |
| 04 | `hierarchy.ResolveUserNodes` (poster school context), section/class-level catalog | Hierarchy is the data model; tenant scope comes from it |
| 05 | `chat` DM open + `message_requests` (cross-school negotiation), `media.PresignUpload`/`ConfirmUpload` (evidence, photos) | Chat/upload infrastructure is module 05's; we only orchestrate |
| 06 | `notify.SendToUser` / `BroadcastTopic` | FCM fan-out and deep links are module 06's job |
| 01 | `jobs.Enqueue` + worker (matching, expiry, SLA reminder), `audit.Record`, error envelope, rate limiter | Foundations own the plumbing |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4
(`tuition:tutors:{area}`, `tuition:tutor:{id}`).

## 3. Lifecycle

Matching pipeline (the module's core flow):

```text
requirement created (POST /tuition/requirements · verified poster)
   └─► jobs.Enqueue("tuition.match", {requirementId})            (module 01 worker)
            │
            ▼
        tuition.NotifyMatches(requirementId)                      (job entry, idempotent)
            │ 1. load requirement (must be open ∧ unexpired)
            │ 2. SELECT tutor_profiles
            │      status = 'verified'
            │      AND subjects ?| requirement.subjects           (GIN index)
            │      AND classes_taught ?  requirement.class_level
            │      AND lat BETWEEN bbox… AND lng BETWEEN bbox…    (5 km box, PostGIS-free)
            │ 3. rank: subject coverage ↓, haversine distance ↑
            │ 4. INSERT tuition_matches(status='notified') top N=10
            │      ON CONFLICT (requirement_id, tutor_profile_id) DO NOTHING
            ▼
       notify.SendToUser(tutorUserId, match push + deep link)     (module 06; queued + retried)
```

State machines:

```text
requirement:   open ──guardian accepts──▶ matched │ open ──poster/admin close──▶ closed │ open ──14d job──▶ expired
match:         notified ──tutor──▶ interested ──guardian──▶ accepted │ tutor──▶ declined │ expiry/close──▶ expired
tutor_profile: draft ──submit──▶ pending_review ──approve──▶ verified │ ──reject──▶ rejected │ verified──suspend──▶ suspended
verification:  pending ──▶ approved │ rejected (note required)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| match notified | tutor interest | interested | tutor verified ∧ requirement open | push to poster "১ জন টিউটর আগ্রহী / 1 tutor interested" |
| match interested | guardian accept | accepted | guardian owns requirement ∧ one-winner tx | requirement → `matched`; contact reveal unlocks; DM/Message Request opened; audit + fee DUE fact |
| match notified/interested | tutor/poster decline | declined | party of the match | counterpart notified (no contact leaked) |
| requirement open | expiry job | expired | `expires_at < now()` | poster + non-terminal matches → `expired`; notice to poster |
| profile draft | submit-for-review | pending_review | evidence complete ∧ no pending review | routed to queue; SLA reminder armed |
| verification pending | reviewer decision | approved / rejected | routed reviewer only; note required on reject | profile status + `verified_at`; badge live; tutor notified; audited |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| Tutor browse (app + any future web read) | TanStack Query paginated list; server cacheable per area+subject (changes rarely, reads often) | Redis, TTL 120 s | `tuition:tutors:{area}` |
| Tutor public profile | Detail query; public-safe DTO only | Redis, TTL 300 s | `tuition:tutor:{id}` |
| My requirements / matches / verification queues | Per-user or admin-fresh — never page-cached | TanStack Query memory / Server Components | none |
| `VerifiedTutorCount(schoolId)` | Landing/dashboard stat (07, later) | Redis, TTL 600 s | `tuition:tutorcount:{schoolId}` |

Invalidation: verification approve/reject busts `tuition:tutors:{area}` for the tutor's area +
`tuition:tutor:{id}`; profile edits bust the same; requirement mutations are per-user and need no
tag busts.

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Match radius (default 5 km), top N (default 10), expiry (14 days), verification SLA reminder (48 h) | Verified-only matching and browse (BR-002/003) |
| Rate-limit buckets (class `default`) | In-app-first negotiation; cross-school only via Message Request |
| Evidence caps per kind (delegated to 05 media caps) | Magic-byte-sniffed evidence (05 owns the sniffer) |
| Subject/class-level catalogs (seed + admin add) | Rule-based ranking (subject coverage, distance) — no model calls |
| Fee-model constants — `TODO: Confirm` (OQ-1) before any value ships | DUE-on-accept fee fact (INV-8); collection belongs to 12 |

## 6. Security

Entry points: 15 REST endpoints under `/api/v1/tuition` and `/api/v1/school` (§ `03` §2); every
entry runs **authenticate → load role claims → tenant-scope**, plus `auth.RequireVerified` on
participatory writes (`NOT_VERIFIED` otherwise).

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| `tuition_requirements` | Verified poster to write; poster owns own rows; School Admin reads/closes within own school | `school_id = caller.schoolId` (poster or admin tenant) |
| `tutor_profiles` (browse/detail) | Any verified user reads public-safe DTO | Cross-school **by design**; public fields only; contact `null` (INV-4) |
| `tutor_profiles` (own) | Owner only (verified) | Row-level: `user_id = caller.userId` |
| `tutor_verifications` | Routed reviewer only: School Admin of the linked school / platform ops (Super Admin) for NULL-school rows; owning tutor reads own outcome (status + note) | Queue scoped via `tutor_profiles.school_id`; platform queue Super-Admin-only (`TUT-IT-003`) |
| `tuition_matches` | Parties only: poster of the requirement, tutor user of the profile | Row-level party check (matches straddle two tenants); requirement-side reads tenant-scoped |

Sanitisation: bios/schedule/area are plain text, length-capped, rendered as text; no phone
numbers, emails or URLs are accepted in bio/availability fields (regex-rejected, BR-007); push
payloads carry ids + subject labels only — never contact. Rate limits: class `default` on every
route, tighter per-user buckets on wizard submit and interest. Audit (`audit.Record`):
approve/reject, admin close, accept (the fee event).

## 7. Accessibility & Motion

Wizard steps announce progress ("ধাপ ২/৪ / Step 2 of 4"); the map pin always has a text-area
alternative so location is never pointer-only; the verified badge pairs an icon with a text label
("ভেরিফাইড টিউটর / Verified Tutor") so trust is never colour-only. Motion is limited to wizard
step slides, chip feedback and the accept-success overlay, each with instant reduced-motion forms
(details in `04` §5, `05` §5). Screen-reader order: status chip → title → primary action.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Module 06 / FCM down | `notify.SendToUser` error | Matches are **created anyway**; pushes missing | Matches remain visible in-app; 06's queue retries delivery on restore — matching never depends on push success |
| 2 | Module 05 down (chat/media) | DM/Message Request/presign errors | Negotiation blocked with retry message; evidence upload blocked | Matches and requirements intact; client offers "চ্যাট এখন অনুপলব্ধ — আবার চেষ্টা করুন / Chat unavailable — try again"; profiles stay `draft` |
| 3 | Module 01 worker down | Job lag alarm | Matching + expiry delayed | Jobs are queued rows — run idempotently when the worker returns; requirement stays `open`, no data loss |
| 4 | R2 down (via 05 media) | Presign/confirm 5xx | Evidence/profile photo upload fails | Tutor setup stays `draft` with resumable uploads; queue shows degraded placeholder for missing evidence |
| 5 | Redis down | Cache/limiter errors | Browse falls through to Postgres (slower); limits fall back to safe defaults | Tags rebuilt on return; no wrong data (DB is source of truth) |
| 6 | Neon (Postgres) degraded | Connection errors | Nothing marketplace-side (Postgres is the source of truth) | 01/15 runbooks: pool alarm, failover path |

## 9. Performance

- Volumes (pilot, 3 schools × ~2,000 users): ~200 requirements/month, ~1,000 tutor profiles, ≤ ~50
  matches per requirement — small tables; indexes still designed for 10× (BRD year-1 target).
- Hot query — matching: `status='verified'` (partial btree) + `subjects ?| array` (GIN) + bbox
  `lat BETWEEN … AND lng BETWEEN …` (Δlat = r/111.32 km ≈ 0.0449°; Δlng = Δlat / cos(lat)), then
  haversine ranking in the service over the ≤ few-hundred candidates — **no PostGIS** until a
  measured need (ADR below). Duplicate matching events are absorbed by `ON CONFLICT DO NOTHING`
  (INV-3).
- Browse: served from the `tuition:tutors:{area}` cache; p95 ≤ 100 ms cached, ≤ 250 ms uncached on
  Neon. Requirement→notification budget: job start ≤ 60 s after post; push delivery is 06's budget.
- Bundle impact: no new heavy dependencies — `expo-location` for the picker; lightest available RN
  map (or static-map pin + manual area text fallback, `05-app-tasks.md` §3).

## 10. Alternatives Considered

### Option A — job-based matching (chosen) · Option B — real-time matching in the request path

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Post returns fast; retries/idempotency natural via the 01 job table; ranking can evolve independently; burst of posts cannot pile up latency | Tutors notified within ~1 s of posting |
| Disadvantages | Up to a worker-cadence delay (≤ 60 s) before notifications | Post latency couples to candidate query; failure semantics muddy (posted but unmatched?); retry storms duplicate pushes |
| Complexity / weight | Low (01 job runner exists) | Medium, and buys seconds nobody asked for |

**Recommendation:** A — matches the stack's in-DB job pattern (`tech-stack.md`); ≤ 60 s delay is fine for tuition lead times. ADR: `07-progress.md`.

### Option A — bbox + haversine in Go (chosen) · Option B — PostGIS geography

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Plain SQL + service math; zero new extensions on Neon; indexes are ordinary btree/GIN | Exact geo queries, radius indexes, distance SQL |
| Disadvantages | Approximate bbox then exact filter in Go (two-step, still trivial at this scale) | Extension management on Neon, migration weight, one more thing to operate for ≤ 1k profiles |
| Complexity / weight | Low | Medium — unjustified until measured need (persona: no over-engineering) |

**Recommendation:** A; revisit with an ADR only if candidate sets exceed ~10k rows.

### Rejected: open DM with a tutor before any match/accept

| | Open pre-match DM (rejected) | Match-gated contact (chosen) |
| --- | --- | --- |
| Advantages | Feels "frictionless" | Guardian/tutor contact is staged and consented; no stranger DMs; fits `brd.md` §6 anti-spam and the persona's trust-first promise |
| Disadvantages | Spam/scam surface aimed at minors and guardians; phone scraping via chat; erodes the school's trust | Interest step adds one tap before contact |
| Complexity / weight | Low | Low — the 05 Message Request seam already exists |

**Recommendation:** Reject — safety is the product (`docs/persona.md`); recorded in `07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Supply-side cold start: few verified tutors at launch; verification SLA (48 h) gates supply | Empty matches frustrate posters; tutors churn while pending | Browse-first marketplace + "be the first verified tutor" empty states; School-Admin-led senior onboarding (US-003); SLA reminder job (OQ-7) |
| 3 | Fee model undecided (`OQ-1`) | Rework of the accept flow | DUE fact is isolated (INV-8); 12 owns collection; constants are config, not code |
| 4 | Location spoofing (pin ≠ reality) | Wrong matches | Bangladesh-bounds validation, area text + pin consistency check, radius is config; report/abuse path via admin close |
| 5 | Contact leakage via free-text fields | BR-007 breach | Regex rejection of phones/emails/URLs in bio/availability; DTO contract tests (`TUT-IT-002`) |
| 6 | Cross-school trust (tutor from school B tutors school A's child) | School discomfort | Verification + badge, staged reveal, in-app chat only; Message Request gives the counterpart explicit consent (BR-007) |
