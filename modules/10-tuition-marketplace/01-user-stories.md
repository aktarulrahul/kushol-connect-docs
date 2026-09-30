# Tuition Marketplace — User Stories

**Module:** `10-tuition-marketplace`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Implements `brd.md` **BR-03** and `prd.md` **§5.3**: guardians/students post tuition requirements (subjects, class level, budget ৳, area + pin); the system matches each to **verified** university/senior tutors by subject overlap and geo-radius and notifies the nearest ten; seniors publish evidence-backed profiles approved by the School Admin (or platform ops); negotiation runs in-app (module 05 chat) after a staged contact reveal. Phase 2 (`brd.md` §8); serves `brd.md` §2 Goal 2 and the §7 tuition-commission stream.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Opens the Marketplace tab but hits the `NOT_VERIFIED` gate — cannot post, interest or tutor (module 03) |
| Guardian | Posts requirements (wizard); reviews interested tutors with badges; accepts one → contact reveal + chat |
| Student | Posts requirements for themselves; a verified senior may also become a tutor |
| Teacher | N/A — no marketplace surface; governance flows through the School Admin |
| School Admin | Reviews their school's verification queue (evidence viewer, approve/reject + note); requirements oversight (read-only, close abusive) |
| Super Admin | Platform-ops reviewer for `school_id` NULL tutor verifications — same queue endpoints, role-scoped |
| Vendor / EdTech brand | N/A — vendors reach students only via module 13 |
| System (jobs, webhooks) | Matching job (on create), expiry job (14 days), verification-SLA reminder, fee DUE fact on accept (collection = module 12) |

## 3. Scope

**In scope**

- Requirement posts: wizard create (subjects/class/budget ৳/area+pin/gender pref/schedule), my list with status chips, edit + manual close, 14-day auto-expiry with poster notice.
- Tutor profiles: create/update, evidence upload (national ID + subject evidence via 05 media), submit-for-review, status tracker; "ভেরিফাইড টিউটর / Verified Tutor" badge only after approval.
- Verification queue: School Admin approve (with note) / reject (with required reason), audited.
- Matching job: verified tutors, subject + class overlap, 5 km bbox → top 10 → `tuition_matches(notified)` → push via 06 with deep link.
- Match lifecycle: interest / single accept / decline / expiry; contact reveal **only on accept**; same-school DM or cross-school Message Request (05).
- Marketplace browse of verified tutors; fee DUE fact on accept (`brd.md` §7 proposal, collection = 12); premium upsell screen (P2).

**Out of scope** (explicit — prevents scope drift)

- Payment collection/gateways/receipts — module 12 (`TODO: Confirm` final fee model with Rahul).
- Live video classes — `brd.md` §4; AI/ML matching — rule-based only ("never call a model when a rule will do"); tutor ratings/reviews — future; vendor/ads — module 13.
- Public logged-out pages — every surface requires auth; the web build is the admin surface only (guardians/students/tutors use the app).

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | `jobs.Enqueue`, `audit.Record`, error envelope, rate limiter, test harness |
| 02 design-system | bn/en catalogs `tuition.*` + `validation.*`, tokens, RN primitives, badge styling |
| 03 identity-access | `auth.RequireVerified`, `users` (identity, role, school claims) |
| 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (poster school context), section/class-level catalog |
| 05 communication-engine | `chat` DM + `message_requests` (negotiation), `media.PresignUpload`/`ConfirmUpload` (evidence, photos) |
| 06 notifications | `notify.SendToUser` / `BroadcastTopic` (match/decision notices, deep links) |

---

## 4. User Stories

### `TUT-US-001` — Guardian posts a tuition requirement

**Priority:** P0 · **Traces:** BR-03 (`brd.md` §5) / PRD §5.3 · **Depends on:** 03, 04

**Story** — As a **verified guardian**, I want **to post my child's tuition need through a short wizard (subjects, class, budget, area)**, so that **verified tutors nearby are found without Facebook groups or guesswork**.

**Acceptance criteria**

- **Given** I am a verified guardian, **when** I complete the wizard (bn-first subject chips e.g. গণিত/Mathematics, পদার্থবিজ্ঞান/Physics; class; ৳ budget; area + pin; gender pref; schedule) and confirm the summary, **then** the requirement is created `open` with `expires_at = now + 14 days` and I see "রিকোয়ারমেন্ট পোস্ট হয়েছে — ম্যাচ হলে আমরা জানাবো / Requirement posted — we'll notify you when tutors match".
- **Given** my account is pending verification, **when** I open the wizard, **then** the `NOT_VERIFIED` gate explains how to get verified and nothing posts.
- **Given** I am offline, **when** I submit, **then** the post queues with the offline banner and confirms on delivery — never silently lost.

**Notes** — subjects/class levels ship bn+en from the shared catalog; budgets show ৳ with bn numerals.

---

### `TUT-US-002` — Student posts a requirement for themselves

**Priority:** P1 · **Traces:** PRD §5.3 · **Depends on:** TUT-US-001

**Story** — As a **verified student**, I want **to post a requirement for myself with the same wizard**, so that **I can find a senior tutor without a guardian intermediary**.

**Acceptance criteria**

- **Given** I am a verified student, **when** I submit the wizard, **then** the requirement is created with `poster_role = student` and behaves identically (matching, interest, accept).
- **Given** any unverified role, **when** I attempt to post, **then** `NOT_VERIFIED` with the verification how-to.

---

### `TUT-US-003` — Verified senior creates a tutor profile and submits evidence

**Priority:** P0 · **Traces:** BR-03 / PRD §5.3 · **Depends on:** 05 (media)

**Story** — As a **verified senior/university student**, I want **to publish a tutor profile with proof (national ID + subject evidence)**, so that **guardians can trust me before any contact**.

**Acceptance criteria**

- **Given** I am a verified user, **when** I fill the profile (university, subjects, classes taught, bio bn/en, rate hint ৳, availability, area + pin), **then** it saves as a private `draft` — nothing appears in browse or matching.
- **Given** I upload a national-ID document + ≥ 1 subject evidence via the 05 media flow, **when** I submit for review, **then** the profile becomes `pending_review` and my tracker shows "জমা দেওয়া হয়েছে → রিভিউ চলছে… / Submitted → Under review…".
- **Given** an unverified user, **when** they open tutor setup, **then** the `NOT_VERIFIED` gate blocks them.

**Notes** — profile photo uses the same media flow; after approval, evidence-backed field edits re-submit to review by default (OQ-6).

---

### `TUT-US-004` — School Admin reviews the tutor-verification queue

**Priority:** P0 · **Traces:** persona trust signals (verified badges) · **Depends on:** TUT-US-003

**Story** — As a **School Admin**, I want **to approve or reject tutor verifications with the evidence in front of me**, so that **only trustworthy seniors carry the verified badge in my school's marketplace**.

**Acceptance criteria**

- **Given** pending verifications routed to my school, **when** I open `/school/tutors`, **then** each row shows tutor identity, university, subjects + an evidence viewer (05 media viewer, short-lived R2 URLs) — evidence visible to reviewers + owning tutor only.
- **Given** I approve (optional note), **when** the decision lands, **then** the profile becomes `verified` (`verified_at` set), the badge activates, the tutor is notified via 06, and `audit.Record` captures reviewer, decision and note.
- **Given** I reject, **when** I submit a reason (required, ≥ 5 chars), **then** the profile becomes `rejected` and the tutor sees the reason in their tracker.
- **Given** a queue item of another school, **when** I open it directly, **then** `TENANT_MISMATCH`/404 — no data leaks.

**Notes** — `school_id` NULL profiles route to the platform-ops queue (`TUT-US-012`).

---

### `TUT-US-005` — Matching job notifies the top-10 verified tutors nearby

**Priority:** P0 · **Traces:** BR-03 / PRD §5.3 (smart matching) · **Depends on:** TUT-US-001, TUT-US-004

**Story** — As the **system**, I want **to notify the nearest verified subject-matched tutors the moment a requirement is posted**, so that **posters get candidates fast and tutors only see relevant work**.

**Acceptance criteria**

- **Given** a requirement is created `open`, **when** the matching job runs, **then** it selects `tutor_profiles` with `status = verified`, subject overlap, `classes_taught ∩ class_level ≠ ∅`, inside the 5 km bbox; ranks by subject coverage then haversine distance; creates ≤ **10** `tuition_matches(notified)` rows; pushes each tutor via 06 ("নতুন টিউশন রিকোয়ারমেন্ট আপনার সাথে মিলেছে / New tuition requirement matches your profile") with a deep link.
- **Given** fewer than 10 qualify, **when** it runs, **then** all are notified; **given** zero qualify, **then** the requirement stays `open` and the poster sees "এখনো কোনো ভেরিফাইড টিউটর ম্যাচ হয়নি / No verified tutors matched yet".
- **Given** the job re-runs after a crash, **when** inserts replay, **then** `UNIQUE(requirement_id, tutor_profile_id)` makes it a no-op — no duplicate matches or pushes.

**Notes** — job entry `tuition.NotifyMatches(requirementId)` via `jobs.Enqueue` (module 01).

---

### `TUT-US-006` — Tutor views a matched requirement and expresses interest

**Priority:** P0 · **Traces:** BR-03 / safety default (in-app negotiation first) · **Depends on:** TUT-US-005

**Story** — As a **verified tutor**, I want **to see matched requirements and signal interest in one tap**, so that **I get tuition work without my phone number being exposed**.

**Acceptance criteria**

- **Given** I have notified matches, **when** I open the matches list, **then** each card shows the requirement summary (subjects, class, area, budget band, schedule) with guardian contact **hidden**.
- **Given** I tap "আগ্রহী / I'm interested", **when** the server confirms, **then** the match becomes `interested` and the guardian is notified ("১ জন টিউটর আগ্রহী হয়েছে / 1 tutor is interested").
- **Given** the match is `declined`/`expired` or the requirement is `matched`/`closed`/`expired`, **when** I tap, **then** `CONFLICT` with a polite message — no state change.

---

### `TUT-US-007` — Guardian reviews interested tutors and accepts one

**Priority:** P0 · **Traces:** persona trust signals + staged contact reveal · **Depends on:** TUT-US-006

**Story** — As a **guardian**, I want **to compare interested tutors by badge and profile, then accept one to unlock contact and chat**, so that **first contact happens only with someone I chose, inside the app**.

**Acceptance criteria**

- **Given** ≥ 1 interested match, **when** I open my requirement detail, **then** interested tutors show name, photo, university, subjects, rate hint + the "ভেরিফাইড টিউটর / Verified Tutor" badge — never contact info.
- **Given** I accept a tutor, **when** the acceptance commits, **then** the match becomes `accepted` (the only one), the requirement `matched`, the tutor sees my contact, and negotiation chat opens — same-school DM direct via 05, cross-school via a 05 Message Request; the acceptance is audited (it is the fee event, `brd.md` §7).
- **Given** a second accept races the first (stale UI), **when** it commits later, **then** `CONFLICT` — the requirement is already matched.

---

### `TUT-US-008` — Requirement auto-expires after 14 days

**Priority:** P0 · **Traces:** freshness/supply-quality default · **Depends on:** TUT-US-001

**Story** — As a **guardian**, I want **stale requirements to expire automatically with a notice**, so that **tutors never chase dead posts and my list stays honest**.

**Acceptance criteria**

- **Given** an `open` requirement past `expires_at`, **when** the hourly expiry job runs, **then** status → `expired`, non-terminal matches → `expired`, and I am notified with a one-tap re-post hint.
- **Given** I edit an open requirement before expiry, **when** the edit saves, **then** `expires_at` is unchanged (a fresh post gets fresh 14 days).

**Notes** — expiry is job-driven and idempotent (re-run safe).

---

### `TUT-US-009` — Poster closes a requirement manually

**Priority:** P1 · **Traces:** PRD §5.3 · **Depends on:** TUT-US-001

**Story** — As a **poster**, I want **to close my requirement once I found a tutor elsewhere**, so that **tutors stop being notified about it**.

**Acceptance criteria**

- **Given** my `open` requirement, **when** I close it, **then** status → `closed`, interested tutors are politely notified, and further interest is refused with `CONFLICT`.
- **Given** a closed/expired requirement, **when** I try to edit it, **then** `CONFLICT` (only re-posting is possible).

**Notes** — a School Admin may close an abusive post via the same endpoint (role-guarded).

---

### `TUT-US-010` — Rejected tutor sees the reason and can resubmit

**Priority:** P1 · **Traces:** persona ("how do I get unblocked") · **Depends on:** TUT-US-004

**Story** — As a **tutor whose verification was rejected**, I want **to see why**, so that **I can fix the evidence and try again**.

**Acceptance criteria**

- **Given** a `rejected` verification, **when** I open my status tracker, **then** I see the status and the reviewer's reason (e.g. "জাতীয় পরিচয়পত্রের ছবি অস্পষ্ট / National ID photo unclear").
- **Given** corrected evidence, **when** I resubmit, **then** a new `pending` review is created (one pending per profile); the badge stays absent until approval.

---

### `TUT-US-011` — Browse verified tutors

**Priority:** P1 · **Traces:** PRD §5.3 / marketplace tab (`prd.md` §4B) · **Depends on:** TUT-US-004

**Story** — As a **guardian or student**, I want **to browse verified tutors by subject and area**, so that **I can see real supply before posting**.

**Acceptance criteria**

- **Given** the browse screen, **when** it loads, **then** the "ভেরিফাইড / Verified" filter is ON and locked for non-admins (unverified profiles are never public — BR-002); subject and area filters narrow the list.
- **Given** a tutor card/profile, **when** I open it, **then** only public-safe fields render (photo, university, subjects, classes taught, rate hint, bio, badge); contact is hidden.
- **Given** no verified tutors exist in the area, **when** the list empties, **then** "এখনো কোনো ভেরিফাইড টিউটর নেই — প্রথম ভেরিফাইড টিউটর হোন / No verified tutors yet — be the first verified tutor".

**Notes** — the CTA "টিউটর হিসেবে অনুরোধ করুন / Request as tutor" opens the wizard pre-filled with that tutor's subjects/area (contact/accept always flows through a requirement + match).

---

### `TUT-US-012` — Platform ops reviews platform-level tutor verifications

**Priority:** P1 · **Traces:** verification standard default · **Depends on:** TUT-US-004

**Story** — As a **Super Admin (platform ops)**, I want **to review verifications for tutors without a school (university seniors)**, so that **platform-level supply meets the same standard**.

**Acceptance criteria**

- **Given** a tutor profile with `school_id` NULL, **when** it is submitted, **then** it appears in the platform-ops queue (same endpoints, Super Admin role) — other tenants never see it.
- **Given** I approve/reject, **when** the decision lands, **then** behaviour is identical to `TUT-US-004` including audit and tutor notification.

**Notes** — `TODO: Confirm` (OQ-4): platform-level profiles in Phase 2 or later.

---

### `TUT-US-013` — Premium tutor subscription upsell

**Priority:** P2 · **Traces:** `brd.md` §7 (BDT 300/month premium tutor proposal) · **Depends on:** TUT-US-004

**Story** — As a **verified tutor**, I want **to see what a premium subscription would give me**, so that **I am ready to subscribe when payments arrive**.

**Acceptance criteria**

- **Given** the premium screen, **when** I open it, **then** it presents the `brd.md` §7 proposal — ৳৩০০/মাস (BDT 300/month) premium tutor subscription — with benefits marked `TODO: Confirm` and a disabled "শীঘ্রই আসছে / Coming soon" CTA (purchase via module 12 later); no invented prices, no paywall on matching.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `TUT-BR-001` | Only `VERIFIED` users (module 03) may post requirements or hold a tutor profile; others get `NOT_VERIFIED` | `auth.RequireVerified` + service |
| `TUT-BR-002` | Only `verified` profiles enter matching/public browse; the badge derives from `status`, never exposed for unverified profiles | Service guards + repository WHERE |
| `TUT-BR-003` | Matching candidates: subject overlap ∧ `class_level ∈ classes_taught` ∧ distance ≤ radius ∧ `status = verified` | Matching job query (GIN + bbox) |
| `TUT-BR-004` | Notify the top **N = 10** nearest ranked (subject coverage ↓, distance ↑); N and radius are config (default 5 km) | Matching job |
| `TUT-BR-005` | `UNIQUE(requirement_id, tutor_profile_id)` — matching idempotent; replays never duplicate matches/pushes | DB unique index + `ON CONFLICT DO NOTHING` |
| `TUT-BR-006` | Contact reveal **staged**: contact fields `null` in every DTO until the guardian accepts that tutor's interest; derived per-request, never denormalized | DTO mappers (`TUT-IT-002`) |
| `TUT-BR-007` | Negotiation starts in-app: same-school via 05 DM, cross-school only via an accepted 05 Message Request; no phone scraping; no contact in push/browse payloads | Service + payload builder |
| `TUT-BR-008` | Requirements auto-expire 14 days after creation (config): `open → expired`, non-terminal matches → `expired`, poster notified | Expiry job |
| `TUT-BR-009` | At most one `accepted` match per requirement; accept atomically sets `requirement.status = matched`; later accepts → `CONFLICT` | Partial unique index + tx |
| `TUT-BR-010` | Rejection requires a decision note (≥ 5 chars) readable by the tutor; both decisions audited (`audit.Record`) | Service + audit |
| `TUT-BR-011` | Evidence docs visible only to the routed reviewer role + owning tutor — never in browse/public payloads/logs | Authorization + `TUT-IT-006` |
| `TUT-BR-012` | On acceptance a match-fee **DUE** fact is recorded per `brd.md` §7 (proposals: 50% of first month, or BDT 300/month premium — `TODO: Confirm`); collection = module 12; no invented prices | Accept tx + audit event |
| `TUT-BR-013` | Tenant isolation: requirements/matches scoped by the poster's school for tenant roles; tutors may be cross-school by design — cross-school contact only via the accepted-match Message Request path | Repository scoping + `TUT-IT-003` |
| `TUT-BR-014` | All tuition routes rate-limit under class `default`; no custom class in this module | Redis limiter (01 base) |

> Content-accuracy (`prompt.txt` §12): seeded demo requirements/tutors are clearly fictional ("Demo High School", fictional universities); monetization figures cite `brd.md` §7 only and stay behind `TODO: Confirm` until confirmed.

## 6. Validation Rules

| Field | Rule | Message key (`packages/shared` i18n catalog) |
| --- | --- | --- |
| `subjects` (requirement & tutor) | 1–5 keys of the shared catalog (গণিত/Mathematics, পদার্থবিজ্ঞান/Physics, রসায়ন/Chemistry, জীববিজ্ঞান/Biology, ইংরেজি/English, বাংলা/Bangla, উচ্চতর গণিত/Higher Mathematics, আইসিটি/ICT) | `validation.tuition.subjects_required` · `subject_unknown` |
| `class_level` | Catalog key (class_6 … ssc, hsc) | `validation.tuition.class_level_invalid` |
| `budget_min` / `budget_max` | Integers 0–1,000,000 BDT; `min ≤ max` | `validation.tuition.budget_range` |
| `gender_pref` | `any` \| `male` \| `female` | `validation.tuition.gender_pref_invalid` |
| `location_area` | 2–80 chars after trim | `validation.tuition.area_length` |
| `lat` / `lng` | Bangladesh bounds (lat 20.5–26.7, lng 88.0–92.7) | `validation.tuition.geo_bounds` |
| `schedule_note` | ≤ 500 chars plain text | `validation.tuition.schedule_length` |
| `university` | 2–120 chars | `validation.tuition.university_length` |
| `classes_taught` (tutor) | ≥ 1 catalog key | `validation.tuition.classes_taught_required` |
| `bio_bn` / `bio_en` | ≤ 1000 chars each; ≥ 1 language; no contact info (BR-007) | `validation.tuition.bio_length` |
| `hourly_rate_hint` | 0–5000 BDT or empty | `validation.tuition.rate_hint_range` |
| evidence (submit-for-review) | National-ID media ref + ≥ 1 subject-evidence ref (confirmed) | `validation.tuition.evidence_required` |
| `decision_note` (reject) | Required, 5–500 chars | `validation.tuition.decision_note_required` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (web/app) generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any tuition endpoint | `UNAUTHENTICATED`, no side effect |
| 2 | Cross-tenant queue/oversight access | `TENANT_MISMATCH` / 404, no leak (`TUT-IT-003`) |
| 3 | Unverified user posts / tutors / interests | `NOT_VERIFIED` + how-to-get-verified guidance |
| 4 | Evidence media deleted / R2 object missing | Degraded placeholder; decision blocked for that item — never a crash |
| 5 | Reduced motion enabled | Static wizard steps, chips, success overlays |
| 6 | Offline wizard submit (app) | Queued with banner — never silently lost |
| 7 | Matching job runs twice (retry/crash) | Idempotent — no duplicate rows or pushes |
| 8 | Tutor suspended after being notified | Interest refused `CONFLICT`; profile leaves browse/matching |
| 9 | Interest tap while guardian closes the requirement | `CONFLICT` + polite message; list refreshes |
| 10 | Two accepts race (stale UI / double tap) | First commit wins; second `CONFLICT` (`TUT-IT-008`) |
| 11 | Zero matching tutors in radius | Requirement stays `open`; area empty state; browse suggested |
| 12 | Subject-matched tutor just outside the radius | Not notified; may still appear in browse (visibility ≠ match) |
| 13 | Poster edits budget after notifications | Allowed while `open`; already-notified matches unchanged |
| 14 | Resubmit while a review is pending | `CONFLICT` — one pending review per profile |

## 8. Reporting Needs

- `tuition.VerifiedTutorCount(schoolId)` export — consumed later by 07 landing/dashboard stats ("ভেরিফাইড টিউটর / Verified tutors" figure).
- School Admin dashboard (07) aggregates, counts only: open requirements, verification queue depth, approved/rejected per month, matches by status.
- Match-fee revenue reporting is module 12's ledger scope — this module provides only the accepted-match fact (BR-012).

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Final fee model: 50% of tutor's first month per match, BDT 300/month premium, or both? (`brd.md` §7 proposals) | Rahul | Open (`TODO: Confirm`) | DUE fact on acceptance citing the §7 proposals; collection in module 12; no invented figures |
| 2 | Verification routing: School Admin of the poster's school vs tutor's linked school; platform ops for NULL | Rahul | Open | Linked-school admin when `school_id` set (same-school case = poster's school); platform ops for NULL |
| 3 | Match defaults: 5 km radius, top N = 10, 14-day expiry | Rahul | Open | As stated; owner-tunable config, not code |
| 4 | Do platform-level (`school_id` NULL) university tutors launch in Phase 2? | Rahul | Open | Yes, platform-ops-reviewed |
| 5 | Premium subscription benefits + purchase flow (module 12) | Rahul | Open | Upsell shows the §7 proposal, `TODO: Confirm` benefits, disabled CTA |
| 6 | Do post-approval profile edits re-trigger review? | Rahul | Open | Evidence-backed fields re-submit; bio/availability/photo do not |
| 7 | Verification review SLA + reminder | Rahul | Open | 48 h SLA with reminder job (module 03 alignment) |
