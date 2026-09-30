# Teacher Analytics — Backend Tasks & Database Design

**Module:** `09-teacher-analytics`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below is designed until the schema is settled. `weekly_pain_points` carries
`school_id` on every row — unscoped queries are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `weekly_pain_points` (model `WeeklyPainPoint`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK → `schools` (04); **tenant column** — always from the JWT claim on reads |
| `section_id` | `uuid` | no | — | FK → `sections` (04) |
| `week_start` | `date` | no | — | Sunday that opens the week window (Asia/Dhaka), `YYYY-MM-DD` |
| `topic_tag` | `text` | no | — | AI-classified topic value (e.g. "ক্যালকুলাসের লিমিট" / "Calculus limits") — rendered as-is |
| `language` | `text` | no | — | `bn` / `en` — language of `topic_tag` (`ANL-BR-009`) |
| `source` | `text` | no | — | `mcq` (failed tests, P0) / `chat` (classified queries, P1) |
| `fail_rate` | `numeric(5,4)` | no | — | 0–1; mcq: failed/total attempts · chat: topic share of classified queries (`ANL-BR-008`) |
| `sample_size` | `int` | no | — | distinct students (mcq) / distinct authors (chat); rows < `ANALYTICS_MIN_SAMPLE` suppressed on read |
| `insight_text` | `text` | no | — | Rendered insight (bn default) e.g. "৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল"; clients may re-render bn/en from `analytics.insight.*` templates + `{percent, topic}` params |
| `computed_at` | `timestamptz` | no | `now()` | Last upsert of this row |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FKs `school_id`, `section_id`; `CHECK (language IN ('bn','en'))`; `CHECK (source IN ('mcq','chat'))`; `CHECK (fail_rate BETWEEN 0 AND 1)`; `CHECK (sample_size >= 0)`; `UNIQUE(school_id, section_id, week_start, topic_tag, source)` (`ANL-BR-011`).
**Tenant scope:** `school_id` on every row; every repository method takes the claim-scoped school id — no method accepts a caller-supplied one.
**Indexes:** unique `(school_id, section_id, week_start, topic_tag, source)` → section matrix read + upsert conflict target; `(school_id, week_start)` → school-wide grid + weeks list; `(section_id, week_start)` → refresh overwrite of the current week.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261019090001_create_weekly_pain_points` | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| None in production — the table is computed, never hand-seeded | — | `ANL-BR-012` |
| Demo rows for "Demo High School" (fictional topics: "ক্যালকুলাসের লিমিট", "Calculus limits") for the 07 dashboard demo build | `DRAFT` — clearly fictional, marked demo | `prompt.txt` §12 |
| Integration fixtures: seeded `ai_test_answers` (module 08 tables) driving expected fail rates | Test-only (testcontainers) | `ANL-IT-003` |

---

## 2. Server Contracts

All routes live under `/api/v1/analytics`; errors use the shared RFC-7807 envelope.

### `GET /api/v1/analytics/weekly-matrix?sectionId=&week=&source=` (section matrix)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims (`TEACHER`, `SCHOOL_ADMIN`) → tenant-scope; verified gate (`ANL-BR-010`) |
| **Input** | query `sectionId` (uuid, required), `week` (`YYYY-MM-DD` Sunday, optional — default latest computed), `source` filter optional; contract-generated validators |
| **Result** | `{ "data": { sectionId, sectionLabel, weekStart, status: "COMPUTED"\|"PARTIAL"\|"EMPTY", rows: [ { topicTag, language, failRate, sampleSize, severity, sources: [ { source, failRate, sampleSize } ], insightText, insightParams: { percent, topic } } ], suppressedCount, computedAt } }` — rows merged per topic across sources; suppressed rows absent (`ANL-BR-004`) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (teacher ≠ section owner) · `TENANT_MISMATCH`/404 (other school) · `NOT_FOUND` (section) · `VALIDATION_FAILED` · `NOT_VERIFIED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none (read-only) |
| **Stories** | `ANL-US-001`, `ANL-US-002`, `ANL-US-004`, `ANL-US-007` |

### `GET /api/v1/analytics/weekly-matrix/school?week=&sectionId=` (school-wide grid)

| | |
| --- | --- |
| **Auth** | authenticate → `auth.RequireRole(SCHOOL_ADMIN)` → tenant-scope |
| **Input** | `week` optional (default latest), `sectionId` optional filter (must belong to the claim's school) |
| **Result** | `{ "data": { weekStart, schoolRollup: [ { topicTag, language, failRate, sampleSize } ], sections: [ { sectionId, sectionLabel, status, rows: [ …same row shape ] } ] } }` — rollup weighted by sample size, suppressed rows excluded (`ANL-BR-004`) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (non-admin incl. teachers — teachers use the section route) · `TENANT_MISMATCH`/404 · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none (read-only) |
| **Stories** | `ANL-US-003`, `ANL-US-004`, `ANL-US-007` |

### `POST /api/v1/analytics/weekly-matrix/refresh` (on-demand recompute)

| | |
| --- | --- |
| **Auth** | authenticate → `auth.RequireRole(TEACHER)` → tenant-scope; verified gate |
| **Input** | `{ "sectionId": uuid }` — caller must own the section (`ANL-BR-002`) |
| **Result** | `202 { "data": { jobId, weekStart } }` — enqueues `analytics.refresh_section` (current open week only, `ANL-BR-006`) |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (not owner) · `TENANT_MISMATCH`/404 · `NOT_FOUND` (archived section) · `RATE_LIMITED` + `retryAfter` (1/day/section, `ANL-BR-007`) · `VALIDATION_FAILED` · `NOT_VERIFIED` · `INTERNAL` |
| **Rate limit** | 1/day/section (Redis, fail-closed on Redis outage) |
| **Audit** | yes — refresh requested (`audit.Record`) |
| **Stories** | `ANL-US-008` |

### `GET /api/v1/analytics/weekly-matrix/weeks?sectionId=&limit=` (available weeks)

| | |
| --- | --- |
| **Auth** | same as the section matrix read |
| **Input** | `sectionId` required (teacher: own section); `limit` 1–12 (default 12) |
| **Result** | `{ "data": { weeks: [ { weekStart, status: "COMPUTED"\|"PARTIAL"\|"EMPTY" } ] } }` — newest first; status derives from stored rows (chat row present → COMPUTED; mcq-only → PARTIAL; no rows → not listed or EMPTY for the current week) |
| **Errors** | as the section matrix read |
| **Rate limit** | default class |
| **Audit** | none |
| **Stories** | `ANL-US-006` |

### Web Server Action / Route Handler (Next.js)

`/school/ai-matrix` screens call the Go API through the generated `openapi-fetch` client — never the
database directly. The CSV export (P2, `ANL-FE-009`) is a Route Handler that re-fetches the matrix
for the selected week and streams CSV; same auth chain (session → role claims → school scope) and
zod-validated query params mirroring `validation.*`.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `ANL-BE-001` | `ComputeSectionWeek(sectionId, weekStart)` | Pipeline per `02` §2: 04 identity → 08 `AttemptStats` (P0) → 05 `GroupMembers` boundary → 08 `ClassifyChatQueries` (P1, skip on failure) → merge per (topic, source) per `ANL-BR-008` → upsert **current week only** (`ANL-INV-002`) | `school:{id}:matrix:{week}` + `school:{id}:matrix:index` | yes — computed / degraded-mcq-only |
| `ANL-BE-002` | `WeeklyMatrix(actor, sectionId, week, source)` | Role checks (`ANL-BR-002/003/010`); week window validation; read + merge rows per topic; suppression filter + `suppressedCount`; status derivation | — | no |
| `ANL-BE-003` | `SchoolMatrix(actor, week, sectionId?)` | `SCHOOL_ADMIN` only; all sections of the claim's school; weighted rollup over unsuppressed rows | — | no |
| `ANL-BE-004` | `AvailableWeeks(actor, sectionId, limit)` | Same scoping as `ANL-BE-002`; ≤12 weeks, newest first | — | no |
| `ANL-BE-005` | `RequestRefresh(actor, sectionId)` | Teacher owns section; Redis limiter 1/day/section (`RATE_LIMITED` + `retryAfter`); enqueue `analytics.refresh_section` | — | yes — refresh requested |
| `ANL-BE-006` | `RunWeeklyJob(schoolId, weekStart)` | Fan-out ACTIVE sections → `ANL-BE-001` per section; per-section error isolation; catch-up window when the Sunday run was missed | tags per section | yes — run summary |
| `ANL-BE-007` | `BuildWeeklyPush(schoolId, weekStart)` (P1) | Sections with ≥1 unsuppressed row → top 3 topics → 06 per-user push to owning teachers, bn locale; once per section/week | — | no |
| `ANL-BE-008` | `applySuppression(rows, minSample)` / `rollup(rows)` | Pure: filter `sample_size < minSample`; school rollup = Σ(rate·size)/Σ(size) over unsuppressed rows only | — | no |
| `ANL-BE-009` | `renderInsight(row, locale)` | Pure: `analytics.insight.mcq` / `analytics.insight.chat` templates + `Intl` bn numerals ("৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল" / "60% of students are struggling with Calculus limits") | — | no |
| `ANL-BE-010` | `severityOf(failRate)` | Pure: <0.30 steady · 0.30–0.49 watch · 0.50–0.69 alert · ≥0.70 critical (labels from `analytics.severity.*`) | — | no |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `ANL-BE-011` | `UpsertWeeklyRows(schoolId, sectionId, weekStart, rows)` | `INSERT … ON CONFLICT (school_id, section_id, week_start, topic_tag, source) DO UPDATE SET fail_rate, sample_size, insight_text, computed_at` — batched; week guard in service | unique index |
| `ANL-BE-012` | `ListSectionWeek(schoolId, sectionId, weekStart, minSample)` | `WHERE school_id=$1 AND section_id=$2 AND week_start=$3 AND sample_size >= $4` | unique index prefix |
| `ANL-BE-013` | `ListSchoolWeek(schoolId, weekStart, minSample)` | `WHERE school_id=$1 AND week_start=$2 AND sample_size >= $3` | `(school_id, week_start)` |
| `ANL-BE-014` | `ListWeeks(schoolId, sectionId, limit)` | `SELECT week_start, bool_or(source='chat') … GROUP BY week_start ORDER BY week_start DESC LIMIT $3` | `(section_id, week_start)` |
| `ANL-BE-015` | `CountSuppressed(schoolId, sectionId, weekStart, maxSample)` | `SELECT count(*) … WHERE sample_size < $4` | unique index prefix |

Every query is tenant-scoped at the repository layer (`ANL-BR-001`, `ANL-INV-005`) — no method
accepts a caller-supplied `school_id`. The read filter (`sample_size >= minSample`) lives in the
query itself, so suppressed rows cannot leak through any code path (`ANL-INV-004`).

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `ANL-BE-016` | `analytics.weekly_matrix` worker (schedule: Sunday 00:00 Asia/Dhaka, per school) | Module 01 weekly worker via `jobs.Enqueue` | Yes — upserts on the unique index; re-run produces identical rows | Per-section error isolation; section-level retry ×5 backoff → dead-letter + audit; previous weeks remain served (`ANL-US-005`) |
| `ANL-BE-017` | `analytics.refresh_section` worker | `POST …/refresh` (202) enqueues | Yes — same upsert path, current week only | Failure leaves last good rows; teacher retries next day (limiter) |
| `ANL-BE-018` | `analytics.weekly_push` step (P1) | After `ANL-BE-016` completes a school | Yes — once per section/week marker in job payload | 06 owns delivery retry; push failure never blocks the matrix |

The job computes the window that just closed (Sun→Sat); a missed Sunday run catches up on worker
restart, computing the same `week_start` — safe because writes are idempotent upserts.

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ANL-UT-001` | `applySuppression` hides rows < threshold and counts them; rollup excludes suppressed rows | Unit | `ANL-BR-004`, `ANL-INV-004` |
| `ANL-UT-002` | Merge of mcq + chat rows per topic (two sources → one row, per-source breakdown) | Unit | `ANL-BR-008`, `ANL-INV-001` |
| `ANL-UT-003` | Insight rendering bn/en with `Intl` numerals from `analytics.insight.*` templates | Unit | `ANL-BR-009` |
| `ANL-UT-004` | fail_rate/sample_size computation from a fixture `AttemptStats` payload; chat share semantics | Unit | `ANL-BR-008` |
| `ANL-UT-005` | Payload validation → `validation.*` keys (uuid, week Sunday format, week range, limit) | Unit | §6 of `01-user-stories.md` |
| `ANL-IT-001` | Role scoping: teacher reads own section OK; **another teacher's section → `FORBIDDEN`**; school admin on section route OK; teacher on school route → `FORBIDDEN` | Integration (testcontainers Postgres) | `ANL-US-007`, `ANL-BR-002/003` |
| `ANL-IT-002` | Cross-tenant read/refresh denied → `TENANT_MISMATCH`/404, nothing leaked | Integration | `ANL-BR-001`, `ANL-INV-005` |
| `ANL-IT-003` | Aggregation correctness: seeded `ai_test_answers` (module 08 tables) → expected `fail_rate`/`sample_size` rows | Integration | `ANL-BR-008`, `ANL-IT` contract with 08 |
| `ANL-IT-004` | Recompute idempotent: run the same week twice → same rows, no duplicates; second refresh same day → `RATE_LIMITED` | Integration | `ANL-BR-011`, `ANL-BR-007` |
| `ANL-IT-005` | Suppression IT: `sample_size < 5` rows absent from every read; `suppressedCount` correct | Integration | `ANL-BR-004` |
| `ANL-IT-006` | Past-week immutability: recompute/refresh targeting a closed week is a no-op + audit warning | Integration | `ANL-BR-006`, `ANL-INV-002` |
| `ANL-IT-007` | 08 classify stub fails → MCQ-only rows + PARTIAL status; other sections unaffected | Integration | `ANL-US-009`, degradation path |
| `ANL-IT-008` | Aggregates-only invariant: after a full run, no raw message text appears in any table, log line, or response body (assert on captured output) | Integration | `ANL-BR-005`, `ANL-INV-003` |
| `ANL-IT-009` | Unauthenticated → `UNAUTHENTICATED`; unverified → `NOT_VERIFIED`; bad input → `VALIDATION_FAILED` on every route | Integration | `ANL-BR-010`, 02 §6 security |

Always included: unauthenticated call denied for every protected entry point; validation rejects bad
input; cross-tenant read/write returns `TENANT_MISMATCH`/404 for every tenant-scoped table; suppressed
rows never returned by any read path.

## 7. Task Checklist

### Schema

- [ ] Migration 1 (§1.2) + sqlc models — prerequisite for every `ANL-BE-*` task below — ____

### Repository · Service · Entry points · Seed · Tests

- [ ] `ANL-BE-011`–`015` sqlc: upsert + suppressed-filtered reads + weeks list — ____
- [ ] `ANL-BE-008`–`010` pure helpers: suppression, rollup, insight render, severity — ____
- [ ] `ANL-BE-001` compute pipeline (consume 08 `AttemptStats` / `ClassifyChatQueries`, 05 `GroupMembers`, 04 `GetSection`) — ____
- [ ] `ANL-BE-002`–`004` read services (role/tenant scoping, merge, status derivation) — ____
- [ ] `ANL-BE-005` refresh orchestration (limiter + enqueue + audit) — ____
- [ ] `ANL-BE-006`/`016`–`017` jobs: weekly worker + refresh worker (register with 01 runner) — ____
- [ ] `ANL-BE-007`/`018` P1 Monday push step via 06 — ____
- [ ] Entry points: 4 endpoints per §2 + OpenAPI spec entries + contract regen — ____
- [ ] i18n: `analytics.*` + `validation.*` keys in `packages/shared` (bn + en) — ____
- [ ] Demo seed rows (§1.3, fictional, marked demo) — ____
- [ ] Tests: `ANL-UT-001`–`005` · `ANL-IT-001`–`009` green in CI — ____
