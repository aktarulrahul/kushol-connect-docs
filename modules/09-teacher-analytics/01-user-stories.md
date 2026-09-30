# Teacher Analytics — User Stories

**Module:** `09-teacher-analytics`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Implements `brd.md` §5 BR-02 and `prd.md` §5.2 (Pain Point Matrix): every week, failed MCQ topics
and AI-classified chat queries are aggregated per section into a bilingual teacher / School Admin
dashboard — e.g. "৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল / 60% of students are struggling with
Calculus limits" — so teachers can plan remediation before the next class. Aggregates only: raw chat
content and per-student weakness rows never exist in this module.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Teacher | Views the weekly matrix for **own sections only**; triggers rate-limited refresh; receives Monday summary push (P1) |
| School Admin | Views the school-wide matrix across all sections of the own tenant; filters by section for oversight |
| Super Admin | **None** — the Matrix is a per-school licensed feature (`brd.md` §7); platform staff hold no section-level view (default OQ-1) |
| Student | Data subject only — never sees analytics about self or peers; aggregate rows + suppression only |
| Guardian | No access |
| Vendor / EdTech brand | No access; ad targeting (module 13) never consumes this module |
| Unverified user (pending) | No access — verified gate from module 03 |
| System (jobs) | Weekly `analytics.weekly_matrix` job (Sunday 00:00 Asia/Dhaka) + on-demand refresh jobs; Monday push via module 06 |

## 3. Scope

**In scope**

- `weekly_pain_points` table (the only data this module owns) + the aggregation pipeline job that fills it from module 08 exports.
- Four REST endpoints: section matrix, school matrix, weeks list, on-demand refresh — role- and tenant-scoped.
- Web dashboard `/school/ai-matrix` (heatmap, week navigation, section filter, drilldown, CSV export P2 — `ANL-FE-009`).
- App: read-only teacher summary card + detail list in the AI Hub area.
- Minimum-sample suppression (default 5 — `TODO: Confirm`), MCQ-only degradation note, bn/en strings (`analytics.*`, `validation.*`).
- Monday-morning teacher push summary via module 06 (P1, bn locale).

**Out of scope** (explicit — prevents scope drift)

- MCQ generation/testing/grading — module 08 (09 only consumes its aggregate exports).
- Chat rooms, message storage, history — module 05 (09 touches only the aggregation boundary).
- Per-student weakness profiles — **rejected by design** (minor-profiling privacy risk; `02` §10).
- Push delivery mechanics — module 06 · licensing/billing workflow for the per-school feature — modules 07/12.

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 08 ai-study-hub | `ai.AttemptStats(sectionID, weekStart, weekEnd)` failed-MCQ aggregates from `ai_test_answers`; `ai.ClassifyChatQueries(ctx, Samples, Locale)`; tables `ai_tests`/`ai_test_attempts`/`ai_test_answers` |
| 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (teacher → own sections; school_admin → school), `hierarchy.GetSection`, `sections` |
| 05 communication-engine | `chat.SectionQuestionSamples` (anonymized samples, never stored) + `chat.GroupMembers(groupID)`; **only topic tags + counts are persisted** |
| 03 identity-access | `auth.RequireRole`, `users` (role teacher/school_admin; verified gate) |
| 01 foundations | `jobs.Enqueue` + weekly worker, `audit.Record`, RFC-7807 envelope, Redis rate limiting |
| 06 notifications (P1) | Per-user push export for the Monday teacher summary (exact export name fixed in 06's spec) |
| web + app (per app) | `analytics.*` / `validation.*` bn + en message catalogs |

---

## 4. User Stories

### `ANL-US-001` — Teacher opens the weekly matrix for a section

**Priority:** P0 · **Traces:** BR-02 (`brd.md` §5) / PRD §5.2 · **Depends on:** `ANL-US-005`

**Story** — As a **teacher**, I want **a weekly heatmap of my section's weak topics (rows = topic tags, cells = fail rate colored by severity)**, so that **I know exactly what to re-teach this week**.

**Acceptance criteria**

- **Given** I am a VERIFIED teacher of section S, **when** I open `GET /api/v1/analytics/weekly-matrix?sectionId=S` for the latest computed week, **then** I receive topic rows with `failRate`, `sampleSize`, sources and the rendered insight sentence (bn default, en available).
- **Given** I teach several sections, **when** I switch sections, **then** each section resolves independently — my own sections only (`ANL-BR-002`).
- **Given** a week where only MCQ data exists, **when** the matrix renders, **then** chat rows are absent and the note "চ্যাট বিশ্লেষণ নেই — শুধু টেস্টের তথ্য দেখানো হচ্ছে / No chat analysis — showing test data only" explains the gap.

### `ANL-US-002` — Teacher drills into a topic

**Priority:** P0 · **Traces:** BR-02 / PRD §5.2 · **Depends on:** `ANL-US-001`

**Story** — As a **teacher**, I want **to tap a topic row and see the insight sentence, sample size and per-source breakdown (MCQ and chat — counts only)**, so that **I can judge how strong the evidence is before re-teaching**.

**Acceptance criteria**

- **Given** a topic row, **when** I open the drilldown, **then** I see the insight ("৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল" / "60% of students are struggling with Calculus limits"), `sampleSize` (distinct students) and per-source `{source, failRate, sampleSize}` rows.
- **Given** any drilldown, **when** rendered, **then** only counts and topic labels appear — never message text, student names or per-student rows (`ANL-BR-005`).

### `ANL-US-003` — School Admin views the school-wide matrix

**Priority:** P0 · **Traces:** BR-02 / PRD §4A (Command Center) · **Depends on:** `ANL-US-005`

**Story** — As a **School Admin**, I want **a school-wide matrix (topics × sections heatmap) with a section selector**, so that **I can see which classes need support and brief the right teachers**.

**Acceptance criteria**

- **Given** a School Admin of school A, **when** `GET /api/v1/analytics/weekly-matrix/school?week=` is called, **then** every section of school A returns its topic rows; the UI renders a topics × sections grid.
- **Given** the section selector is set to one section, **when** applied, **then** the full per-section matrix for that section renders (same shape as the teacher view).
- **Given** a School Admin of school B, **when** addressing school A's data, **then** `TENANT_MISMATCH` (404 body) — nothing leaks.

### `ANL-US-004` — Rows below the minimum sample are suppressed

**Priority:** P0 · **Traces:** `brd.md` §6 privacy · **Depends on:** `ANL-US-005`

**Story** — As a **product owner protecting minors**, I want **topic rows with `sample_size < 5` hidden from every read**, so that **no individual student's weakness is inferable from a tiny class**.

**Acceptance criteria**

- **Given** a computed week where a topic has `sample_size = 3`, **when** any matrix read returns, **then** that row is absent and `suppressedCount` reports how many rows were hidden.
- **Given** every row of a section is suppressed, **when** the matrix renders, **then** the empty state "এই সপ্তাহে যথেষ্ট তথ্য নেই — কমপক্ষে ৫ জন শিক্ষার্থীর ডেটা প্রয়োজন / Not enough data yet — data from at least 5 students is required" shows.
- **Given** the school-wide rollup, **when** computed, **then** suppressed rows are excluded entirely (no cross-section re-identification).

### `ANL-US-005` — Weekly computation job (system)

**Priority:** P0 · **Traces:** BR-02 / PRD §5.2 · **Depends on:** module 08 delivered

**Story** — As a **system**, I want **a weekly job (Sunday 00:00 Asia/Dhaka) that aggregates the just-closed week per school → per section**, so that **Monday morning every teacher has a fresh matrix without anyone pressing a button**.

**Acceptance criteria**

- **Given** the week Sun→Sat that just closed, **when** the job runs for a school, **then** each section gets rows merged per (topic_tag, source) from `ai.AttemptStats` (MCQ, P0) and `ai.ClassifyChatQueries` (chat, P1), upserted with `UNIQUE(school_id, section_id, week_start, topic_tag, source)`.
- **Given** the AI classify call fails for a section, **when** the job continues, **then** that section publishes MCQ-only rows and the job records the degradation in audit — other sections are unaffected.
- **Given** the job fails mid-run, **when** retried via `jobs`, **then** it is idempotent (upserts) and the previous week's rows remain visible until the new week publishes.

### `ANL-US-006` — Week navigation across history

**Priority:** P0 · **Traces:** BR-02 · **Depends on:** `ANL-US-001`

**Story** — As a **teacher**, I want **to browse previous weeks from a weeks list**, so that **I can compare whether remediation worked last week**.

**Acceptance criteria**

- **Given** `GET /api/v1/analytics/weekly-matrix/weeks?sectionId=S`, **when** called, **then** up to 12 computed weeks return with `status` COMPUTED (mcq+chat) / PARTIAL (mcq only) / EMPTY — newest first.
- **Given** a historical week, **when** opened, **then** rows render exactly as computed — past weeks are immutable (`ANL-BR-006`).

### `ANL-US-007` — Role-scoped access is enforced

**Priority:** P0 · **Traces:** `brd.md` §6 multi-tenant privacy · **Depends on:** `ANL-US-001`

**Story** — As a **School Admin**, I want **teachers limited to their own sections and schools isolated from each other**, so that **analytics about minors never crosses its scope**.

**Acceptance criteria**

- **Given** a teacher requesting another teacher's section, **when** the read executes, **then** `FORBIDDEN` — no rows, no metadata.
- **Given** any caller addressing another school's section/week, **when** the read executes, **then** `TENANT_MISMATCH` (404 body).
- **Given** a Super Admin, Student, Guardian or unauthenticated caller, **when** any analytics endpoint is called, **then** `FORBIDDEN` / `UNAUTHENTICATED` respectively.

### `ANL-US-008` — Teacher triggers an on-demand refresh

**Priority:** P1 · **Traces:** BR-02 · **Depends on:** `ANL-US-001`, `ANL-US-005`

**Story** — As a **teacher**, I want **a "refresh now" action that recomputes the current (in-progress) week for my section**, so that **Friday's test results are visible the same day**.

**Acceptance criteria**

- **Given** `POST /api/v1/analytics/weekly-matrix/refresh {sectionId}`, **when** accepted, **then** `202 {jobId}` and the current week's rows are recomputed (overwriting only the current week) within the job budget.
- **Given** a second refresh for the same section the same day, **when** submitted, **then** `RATE_LIMITED` with `retryAfter` (limit 1/day/section — default OQ-3).
- **Given** the refresh job fails, **when** the teacher reopens the matrix, **then** the last successfully computed rows still render (`ANL-BR-006`).

### `ANL-US-009` — Chat queries classified to topics (P1 source)

**Priority:** P1 · **Traces:** PRD §5.2 ("failed MCQ topics and chat queries") · **Depends on:** `ANL-US-005`

**Story** — As a **teacher**, I want **the week's section-group questions classified into topic tags alongside MCQ results**, so that **confusion students never wrote in a test still shows up**.

**Acceptance criteria**

- **Given** the section's official group, **when** the job samples the week's messages (capped), **then** only derived topic tags + counts persist via `ai.ClassifyChatQueries(ctx, Samples, Locale)`; raw message content is never stored, returned or logged (`ANL-BR-005`).
- **Given** classification fails or 05 is unavailable, **when** the week publishes, **then** MCQ-only rows publish (chat is P1; MCQ alone is sufficient — default OQ-4).
- **Given** a topic classified from chat, **when** displayed, **then** the tag renders as-is with its stored `language` (`bn` or `en`), labelled as chat-sourced.

### `ANL-US-010` — Section with no activity shows an explanatory empty state

**Priority:** P0 · **Traces:** PRD §5.2 · **Depends on:** `ANL-US-001`

**Story** — As a **teacher of a section that ran no tests and had no chat activity**, I want **a clear explanatory empty state instead of a blank chart**, so that **I understand the matrix needs data, not that the app is broken**.

**Acceptance criteria**

- **Given** a section with zero attempts and zero messages in the week, **when** the matrix is read, **then** the response has zero rows and the UI shows "এই সেকশনে এই সপ্তাহে কোনো টেস্ট বা চ্যাট কার্যক্রম হয়নি / No test or chat activity in this section this week".
- **Given** the same state in the app, **when** the summary card renders, **then** the same bilingual copy appears with no crash or spinner.

### `ANL-US-011` — Monday morning push summary (P1)

**Priority:** P1 · **Traces:** BR-02 / PRD §5.2 · **Depends on:** `ANL-US-005`, module 06

**Story** — As a **teacher**, I want **a Monday-morning push with my section's top 3 pain topics**, so that **I walk into class already knowing what to revisit**.

**Acceptance criteria**

- **Given** the weekly job published a section with ≥1 unsuppressed row, **when** the Monday 07:00 (Asia/Dhaka) step runs, **then** each owning teacher receives one per-user push (bn locale) — "এই সপ্তাহের দুর্বলতা: ক্যালকুলাসের লিমিট, … / This week's weaknesses: Calculus limits, …" — deep-linking to the app summary.
- **Given** a section with only suppressed rows, **when** the push step runs, **then** no notification is sent (no empty-alarm spam).

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `ANL-BR-001` | Tenant isolation: `school_id` always comes from the JWT claim, never from the request; cross-school reads return `TENANT_MISMATCH`/404 | Service + repository (both) |
| `ANL-BR-002` | Teachers may read only sections they are assigned to (`hierarchy.ResolveUserNodes`); another teacher's section → `FORBIDDEN` | Service |
| `ANL-BR-003` | School Admin reads the whole own school; Super Admin, Student, Guardian, Vendor: no access (per-school licensed feature) | Service (`auth.RequireRole`) |
| `ANL-BR-004` | Rows with `sample_size < minSample` (default 5, `TODO: Confirm`) are hidden in every read and excluded from school rollups; `suppressedCount` is reported instead | Repository (read filter) + service |
| `ANL-BR-005` | Aggregates only: raw chat message content is never persisted in `weekly_pain_points`, never returned by any endpoint, never logged; drilldowns expose counts and topic labels only | Service + review gate |
| `ANL-BR-006` | Weekly history is immutable: recompute (job or refresh) overwrites **only the current open week**; past weeks are never mutated | Service guard + upsert scope |
| `ANL-BR-007` | On-demand refresh is rate-limited to 1 per section per day; exceeding → `RATE_LIMITED` with `retryAfter` | Redis limiter + service |
| `ANL-BR-008` | `fail_rate` (mcq) = failed attempts ÷ total attempts on the topic's questions; `sample_size` = distinct students. `fail_rate` (chat) = the topic's share of the week's classified queries; `sample_size` = distinct student authors | Service (compute) |
| `ANL-BR-009` | `topic_tag` values may be bn or en (AI-classified); each row stores its `language` and the tag renders as-is; all UI chrome ships bn + en from `analytics.*` | DB CHECK + shared catalogs |
| `ANL-BR-010` | Only VERIFIED teacher/school_admin actors pass; unverified or pending users are refused (`NOT_VERIFIED`) | `auth.RequireRole` + verified gate |
| `ANL-BR-011` | One row per (school, section, week, topic, source): `UNIQUE(school_id, section_id, week_start, topic_tag, source)` — recompute is an upsert, never a duplicate | DB unique constraint |
| `ANL-BR-012` | Seed/demo matrix content is clearly fictional ("Demo High School"), never presented as a real school's data (`prompt.txt` §12) | Seed review |

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| `sectionId` | required UUID; must resolve to a section of the caller's school | `validation.required` · `validation.section_uuid` · `analytics.section_not_in_school` |
| `week` | optional; `YYYY-MM-DD`, must be a Sunday (week window start, Asia/Dhaka); default = latest computed week | `analytics.week_invalid` |
| `source` filter (optional read param) | `mcq` \| `chat` | `analytics.source_invalid` |
| refresh `sectionId` | required UUID; caller must own the section (teacher) | `validation.required` · `analytics.section_not_owned` |
| `week` on reads | not in the future; at most 52 weeks back | `analytics.week_range` |
| list `limit` (weeks) | 1–12 | `validation.page_invalid` |

Mirrored exactly by the OpenAPI contract (server validation) and the zod schemas (web/app) generated
from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any analytics route | `UNAUTHENTICATED`, no side effect |
| 2 | Cross-tenant read (`schoolId`/`sectionId` of another school) | `TENANT_MISMATCH` (404 body), nothing leaked |
| 3 | Teacher reads another teacher's section | `FORBIDDEN` — not even row counts |
| 4 | Unverified (pending) teacher | `NOT_VERIFIED` + how to get verified (module 03 copy) |
| 5 | 08 classify call fails / times out mid-week | MCQ-only rows publish; neutral "no chat analysis" note; audit records degradation |
| 6 | Refresh job fails after accept | Last computed rows remain; error surfaces only as stale `computedAt` + retryable state |
| 7 | Refresh beyond 1/day/section | `RATE_LIMITED` with `retryAfter`; bn/en message |
| 8 | `week` in the future or malformed | `VALIDATION_FAILED` (`analytics.week_invalid` / `analytics.week_range`) |
| 9 | All rows suppressed for a section | Empty matrix + "not enough data" state + `suppressedCount` |
| 10 | Section archived mid-week | Reads still resolve history; refresh refuses with `NOT_FOUND`; no new rows computed |

## 8. Reporting Needs

- The matrix itself is the module's report — consumed by the web dashboard (07 shell) and the app AI Hub summary; CSV export (P2) re-uses the same read.
- School-wide topic rollup (weighted by sample size, suppressed rows excluded) for the School Admin view.
- Compute-run outcomes (computed / degraded / empty per section) into audit — ops only, no teacher exposure; Monday push top-3 built from the same stored rows.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Matrix granularity + audience: weekly per section per topic tag; who sees what? | Rahul | Open | Weekly, per section, per topic tag; teacher sees ONLY their own sections; School Admin the whole school; Super Admin none (per-school feature) |
| 2 | Minimum sample size before a topic row is shown | Rahul | Open — `TODO: Confirm` | 5 (`ANALYTICS_MIN_SAMPLE`); rows below suppressed for privacy |
| 3 | Job schedule + on-demand recompute policy | Rahul | Open | Weekly job Sunday 00:00 Asia/Dhaka; teacher refresh 1/day/section, recomputes the current week only |
| 4 | Include chat-query source at launch? | Rahul | Open | Chat is P1 (last 7 days of section-group messages via 08 `ClassifyChatQueries`, capped sample); MCQ source is P0 and sufficient alone |
| 5 | Monday push timing + locale | Rahul | Open | Monday 07:00 Asia/Dhaka, bn locale, top 3 topics, only when ≥1 unsuppressed row exists |
