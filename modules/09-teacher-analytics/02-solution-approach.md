# Teacher Analytics — Solution Approach

**Module:** `09-teacher-analytics` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Written before any task list and any code (`docs/prompt/prompt-build.md` §4 step 1). The single owned
table, the aggregation pipeline, the privacy invariants and the degradation behaviour are settled here.

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `weekly_pain_points` | One aggregate row per (school, section, week, topic tag, source): `fail_rate`, `sample_size`, `insight_text`, `computed_at` | Yes |
| `ai_tests` / `ai_test_attempts` / `ai_test_answers` | Auto-CT tests and per-answer results (failed-MCQ raw material) | No — module 08 |
| `sections` / schools / enrollments | Hierarchy that defines "own sections" vs "whole school" | No — module 04 |
| `users` | Teacher / School Admin identity, verified status | No — module 03 |
| `chat_groups` / messages | Official section groups; sampled inside the aggregation boundary only | No — module 05 |
| `jobs` | Durable queue: weekly `analytics.weekly_matrix` + `analytics.refresh_section` | No — module 01 |

### 1.2 Relationships

```text
schools (04) 1 ──── n weekly_pain_points n ──── 1 sections (04)
weekly_pain_points: UNIQUE(school_id, section_id, week_start, topic_tag, source)

inputs (read-only, via exports — never joined directly):
  `ai.AttemptStats(sectionID, weekStart, weekEnd)`      ← ai_test_answers (08)
  ai.ClassifyChatQueries(Samples)       ← official section group messages (05), inside the boundary
```

No FK from `weekly_pain_points` into 08 tables — the job copies aggregates at compute time, so the
matrix survives source retention windows and stays cheap to read.

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `ANL-INV-001` | One row per (school, section, week, topic, source); recompute upserts, never duplicates | Unique constraint + `ON CONFLICT DO UPDATE` |
| `ANL-INV-002` | Past weeks are immutable; only the current open week (Sun→Sat, Asia/Dhaka) may be overwritten | Service guard on every write path |
| `ANL-INV-003` | Aggregates only: no raw message text, no per-student rows, no free-text query content is stored or returned | Schema has no such columns; review gate + tests |
| `ANL-INV-004` | Reads expose only rows with `sample_size ≥ minSample`; school rollups exclude suppressed rows entirely | Repository read filter (`ANL-BR-004`) |
| `ANL-INV-005` | Every query is scoped by `school_id` from the caller's claim; no repository method accepts a caller-supplied school id | Repository scoping (`ANL-BR-001`) |
| `ANL-INV-006` | Topic tags render as-is with their stored `language`; UI chrome is always bn + en from `analytics.*` | `language` CHECK + shared catalogs |

## 2. Module Boundary

**Owns (writes):** `weekly_pain_points`.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 08 | `ai.AttemptStats(sectionID, weekStart, weekEnd)` — failed-MCQ aggregates; `ai.ClassifyChatQueries(ctx, Samples, Locale)` — chat → topic tags | MCQ grading and AI prompting are 08's domain; 09 never touches `ai_test_answers` SQL or DeepSeek directly |
| 04 | `hierarchy.ResolveUserNodes(userId)` (teacher → own sections; school_admin → school), `hierarchy.GetSection`, `sections` | Scope decisions follow the hierarchy; 09 never re-derives ownership |
| 05 | `chat.SectionQuestionSamples` (anonymized, PII-masked samples, classified then discarded) + `chat.GroupMembers(groupID)` (distinct authors); **only topic tags + counts are persisted** | Messaging belongs to 05; 09 consumes member/author metadata and derives tags via 08 |
| 03 | `auth.RequireRole`, verified status on `users` | Verification and RBAC are 03's gate |
| 01 | `jobs.Enqueue` + weekly worker, `audit.Record`, Redis rate limiter, RFC-7807 envelope | No bespoke scheduler; audit trail is platform-wide |
| 06 (P1) | Per-user push export for the Monday summary | Delivery mechanics stay in 06 |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

### The aggregation pipeline (exact chain)

```text
jobs worker (Sunday 00:00 Asia/Dhaka, per school; or analytics.refresh_section per section)
  └─► analytics.ComputeSectionWeek(sectionId, weekStart)          (09 service)
        ├─ hierarchy.GetSection(sectionId)                        → section identity + school scope
        ├─ `ai.AttemptStats(sectionID, weekStart, weekEnd)`                       → MCQ topic aggregates (P0) from ai_test_answers
        ├─ chat.SectionQuestionSamples(sectionID, from, to, 200)  → anonymized chat text (in-memory, never stored)
        ├─ chat.GroupMembers(groupID)                             → distinct authors
        │    (sample ≤ cap messages of the week — inside the boundary; raw text never persisted)
        ├─ ai.ClassifyChatQueries(ctx, Samples, Locale="bn")      → chat topic tags (P1) — skipped on failure
        ├─ merge per (topic_tag, language, source):
        │    fail_rate / sample_size per ANL-BR-008 · insight_text rendered bn (template + Intl numerals)
        ├─ upsert weekly_pain_points (current week only — ANL-INV-002)
        ├─ audit.Record("analytics.week_computed" | "analytics.week_degraded_mcq_only")
        └─ invalidate cache tag school:{schoolId}:matrix:{week}
```

## 3. Lifecycle

```text
week:      OPEN (current Sun→Sat, refresh may overwrite) ──Sunday 00:00 job──▶ COMPUTED (immutable history)
section-week outcome:  COMPUTED (mcq+chat) · PARTIAL (mcq only — chat failed/skipped) · EMPTY (no data)
push:      published week + ≥1 unsuppressed row ──Monday 07:00──▶ summary push sent (P1, once)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| (none) | weekly job / refresh | OPEN-week rows upserted | week window valid; section ACTIVE | audit + cache invalidation |
| OPEN | Sunday 00:00 job closes the week | COMPUTED (immutable) | — | Monday push step (P1) |
| OPEN | refresh `1/day/section` | OPEN rewritten | rate limit + teacher owns section | audit "analytics.refresh" |
| COMPUTED | read (any week) | — | role + tenant + suppression filters | tagged cache read |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `/school/ai-matrix` (web) | Server Component first paint → TanStack Query for interactive heatmap/selectors | API Redis, 5 min TTL | `school:{id}:matrix:{week}` |
| Drilldown panel | Client (data already in the matrix response — no second fetch) | same response | `school:{id}:matrix:{week}` |
| App AI Hub summary | Client (TanStack Query), offline cache of last matrix | MMKV/react-query persist | `school:{id}:matrix:{week}` |
| Weeks list | Client | Redis, 5 min TTL | `school:{id}:matrix:index` |

Writes (job upsert, refresh completion) revalidate the week tag + index tag (§4 of `06`). Matrix
reads are cheap after materialization — the cache exists to absorb dashboard refresh storms, not to
hide slow queries.

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Min sample size `ANALYTICS_MIN_SAMPLE` (default 5 — `TODO: Confirm` OQ-2) | Suppression always applied at read (no opt-out) |
| Chat sample cap per section/week (default 500 messages) | Week window Sun→Sat, Asia/Dhaka; `week_start` = the Sunday |
| Per-school feature availability (licensed feature toggle, module 07) | Refresh limit 1/day/section; refresh recomputes the current week only |
| Monday push enable/timing (default Mon 07:00 Asia/Dhaka, bn) | Severity thresholds: <0.30 steady · 0.30–0.49 watch · 0.50–0.69 alert · ≥0.70 critical |
| — | Sources enum `mcq` \| `chat`; Super Admin exclusion; aggregates-only invariant |

## 6. Security

Entry points run **authenticate → load role claims → tenant-scope**; errors use the shared RFC-7807
envelope (`UNAUTHENTICATED`, `FORBIDDEN`, `VALIDATION_FAILED`, `TENANT_MISMATCH`, `NOT_FOUND`,
`RATE_LIMITED`, `NOT_VERIFIED`, `INTERNAL`).

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| `GET /api/v1/analytics/weekly-matrix` | `auth.RequireRole(TEACHER, SCHOOL_ADMIN)` + verified gate | `school_id` from claim; teacher additionally limited to `ResolveUserNodes` sections — other teacher's section → `FORBIDDEN` |
| `GET /api/v1/analytics/weekly-matrix/school` | `auth.RequireRole(SCHOOL_ADMIN)` | Whole own school only; `sectionId` filter must resolve inside the claim's school |
| `POST /api/v1/analytics/weekly-matrix/refresh` | `auth.RequireRole(TEACHER)` + verified | Own sections only; Redis limiter 1/day/section (`RATE_LIMITED`) |
| `GET /api/v1/analytics/weekly-matrix/weeks` | TEACHER / SCHOOL_ADMIN | Same scoping as the matching matrix read |
| Privacy | — | Aggregates only; suppression on every read; students/guardians have no endpoint; drilldowns carry counts, never text or names (`ANL-INV-003/004`) |
| Audit | — | Refresh triggers, weekly-run outcomes and degradations recorded via `audit.Record` |

Validation is contract-first (OpenAPI-generated validators); the repository accepts only
claim-scoped parameters.

## 7. Accessibility & Motion

The heatmap never encodes meaning in colour alone: every cell shows its numeric fail rate and an
aria-label ("ক্যালকুলাসের লিমিট — ৬০%, সতর্কতা / Calculus limits — 60%, alert"). Cells are buttons
opening the drilldown; focus moves into the panel and returns on close. Motion is limited to cell
hover/focus rings and a drilldown slide/fade (details in `04` §5); reduced-motion renders both
instantly. Bangla numerals via `Intl` (`৬০%`), Hind Siliguri everywhere.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | 08 `ClassifyChatQueries` fails / times out | Job error per section | Section publishes MCQ-only; neutral "no chat analysis" note; audit records degradation | Next weekly run (or refresh) retries classification; no data lost |
| 2 | 08 `AttemptStats` fails for a section | Job error | That section's week stays EMPTY; other sections continue | Job retry via `jobs` (backoff ×5); previous weeks untouched |
| 3 | Weekly job misses (worker down Sunday 00:00) | Job table alarm | Teachers see the prior week | Worker restart runs the missed window (schedule catch-up); refresh unavailable meanwhile |
| 4 | Refresh job fails after 202 | Job status | Stale `computedAt` shown | Teacher may refresh again next day; matrix keeps last good rows (`ANL-INV-002`) |
| 5 | 04 `ResolveUserNodes` unavailable | Scope resolution error | Reads refuse with `INTERNAL` — never guess scope | Cached section membership (5 min) softens; alarm on 04 |
| 6 | Redis down | Limiter/cache errors | Refresh fails closed (cost guard); reads fall through to Postgres | Limiter restores with Redis; matrix still readable |

## 9. Performance

- **Volumes:** year 1 target 10 schools × ~10 sections × 52 weeks × ~6 topics × ≤2 sources ≈ 62k rows/year — trivial for Postgres; the job writes per school in one batched transaction.
- **Hot queries:** section matrix `WHERE school_id=$1 AND section_id=$2 AND week_start=$3` (unique index prefix); school grid `(school_id, week_start)`; weeks list `DISTINCT week_start … LIMIT 12`. All indexes defined in `03` §1.
- **Job cost:** one `AttemptStats` SQL aggregate + at most one batched `ClassifyChatQueries` call per section per week (DeepSeek Flash-class, capped sample) — cost stays O(sections)/week, matching the cost-efficient AI principle (`docs/persona.md`).
- **Bundle impact:** web dashboard route gains Recharts (~45 kB gzip, code-split to the admin route only); app adds no new dependency.

## 10. Alternatives Considered

### Option A — Compute-on-read · Option B — Materialized weekly table (chosen)

| | A: compute on read | B: materialized `weekly_pain_points` |
| --- | --- | --- |
| Advantages | Always current; no schema of our own | Dashboard latency (one indexed read); DeepSeek called once per section/week, not per view; history is queryable and immutable |
| Disadvantages | Every dashboard open re-runs SQL aggregates + possibly an AI call; slow on 3G-bound teachers; cost scales with views | Stale up to the refresh limit; needs the job machinery |
| Complexity / weight | Low code, high runtime cost | One table + two jobs (already provided by 01) |

### Option A — AI free-text clustering · Option B — Raw tag aggregation (chosen)

| | A: cluster raw queries per week | B: aggregate 08's existing topic tags |
| --- | --- | --- |
| Advantages | Might surface novel themes | Deterministic, cheap, reuses the taxonomy students' tests already use; comparable across weeks |
| Disadvantages | New DeepSeek prompt class, unstable week-to-week labels, harder suppression accounting | Limited to 08's taxonomy |
| Complexity / weight | High — prompt versioning + clustering evaluation | Low — merge-only |

### Per-student weakness view — **REJECTED**

A per-student drilldown was evaluated and rejected: it turns a class-planning tool into a
minor-profiling surveillance surface (`brd.md` §6 guardians'/minors' data minimization), invites
teacher misuse, and would make suppression meaningless. The section-level aggregate with minimum
sample size is the deepest granularity this module exposes; revisit only with an explicit ADR and
product-owner sign-off.

**Recommendation:** B + B — materialized weekly rows aggregating 08's tags. **ADR:** record the
materialization and the per-student rejection in this module's `07-progress.md` (the rejection is
referenced by any future analytics proposal).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | 08's `AttemptStats` returns per-topic failed/total aggregates usable directly | Re-computation logic leaks into 09 | Contract frozen in 08's `06` §2; 09 treats it as the only MCQ input (`ANL-IT-003` proves the mapping) |
| 2 | Chat classification quality on Bangla slang is good enough to be useful | Noise rows erode teacher trust | Chat stays P1 behind a neutral note; sample cap; suppression; threshold tunable (`OQ-2`) |
| 3 | Teachers read `fail_rate` correctly | Misread rates → wrong remediation | Insight sentence + sample size always shown together; severity labels; definition tooltip (`04` §2) |
| 4 | Small sections (<5 students with data) suppress everything | Feature feels empty for pilot classes | `suppressedCount` + honest empty copy; threshold is config, `TODO: Confirm` with pilot feedback |
| 5 | Chat sampling could drift into private content | Trust failure with parents/schools | Official section group only (never DMs/clubs), capped sample, aggregates-only invariant tested (`ANL-IT-008`), raw text never persisted or logged |
