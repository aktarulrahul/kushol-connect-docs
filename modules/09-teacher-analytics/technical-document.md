# Teacher Analytics — Technical Document

**Module:** `09-teacher-analytics` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Compressed from this folder's spec set — `01-user-stories.md` · `02-solution-approach.md` · `03-backend-tasks.md` · `04-frontend-tasks.md` · `05-app-tasks.md` · `06-integration-tasks.md`. On any drift, the spec files win.

---

## 1. Overview

### 1.1 Purpose

Implements `brd.md` §5 BR-02 and `prd.md` §5.2 (Pain Point Matrix): every week, failed-MCQ topics and AI-classified chat queries are aggregated per section into a bilingual teacher / School Admin dashboard — e.g. "৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল / 60% of students are struggling with Calculus limits" — so teachers can plan remediation before the next class. Aggregates only: raw chat content and per-student weakness rows never exist in this module (the per-student view was evaluated and **rejected** — `02` §10).

### 1.2 Scope

**In:** `weekly_pain_points` table (the only data this module owns) + the aggregation pipeline job fed by module 08 exports; four REST endpoints (section matrix, school matrix, weeks list, on-demand refresh) — role- and tenant-scoped; web dashboard `/school/ai-matrix` (Recharts heatmap, week navigation, section filter, drilldown; CSV export P2 — `ANL-FE-009`); app read-only teacher summary card + section detail; minimum-sample suppression (default 5 — `TODO: Confirm`), MCQ-only degradation note; Monday-morning teacher push via module 06 (P1, bn).

**Out:** MCQ generation/testing/grading (module 08 — only its aggregate exports are consumed); chat rooms/message storage/history (module 05 — only the aggregation boundary); per-student weakness profiles (**rejected by design** — minor-profiling privacy risk); push delivery mechanics (module 06); licensing/billing workflow for the per-school feature (modules 07/12).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 08 ai-study-hub | `ai.AttemptStats(sectionID, weekStart, weekEnd)` failed-MCQ aggregates (P0 source); `ai.ClassifyChatQueries(ctx, Samples, Locale)` (P1 source); `ai.QuotaState` context; tables `ai_tests`/`ai_test_attempts`/`ai_test_answers` are 08-owned |
| consumes | 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (teacher → own sections; school_admin → school), `hierarchy.GetSection`, `sections` |
| consumes | 05 communication-engine | `chat.SectionQuestionSamples` (anonymized samples → 08 classify, never persisted) + `chat.GroupMembers(groupID)` (distinct-author counts); only topic tags + counts are stored |
| consumes | 03 identity-access | `auth.RequireRole`, `users` verified gate (teacher / school_admin only) |
| consumes | 01 foundations | `jobs.Enqueue` + weekly worker (Sunday 00:00 Asia/Dhaka), `audit.Record`, RFC-7807 envelope, Redis rate limiting |
| consumes | 06 notifications (P1) | Per-user push export (`notify.SendToUser`) for the Monday teacher summary |
| consumed by | 07 command-center-web | `analytics.SchoolMatrix` export + REST §2 for the Command Center AI-matrix section |
| consumed by | 06 notifications | `analytics.WeeklyMatrix` as push-builder source data |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| API language/framework | Go · chi REST handlers generated from OpenAPI 3.1 | four scoped endpoints + two exported Go functions | `tech-stack.md` api table |
| Data access | sqlc + pgx · PostgreSQL (Neon) | one materialized table; reads are single indexed queries | testcontainers-go for IT |
| Queueing | 01 in-DB job table + weekly worker | no bespoke scheduler; idempotent upserts make reruns safe | `analytics.weekly_matrix` · `analytics.refresh_section` |
| Cache / limiter | Redis (go-redis) | matrix read cache (TTL 5 min) + refresh limiter (fail-closed) | tags per `06` §4 |
| Web charts | Recharts heatmap | Pain Point Matrix visualization, code-split to the admin route | ~45 kB gzip (`tech-stack.md` charts row) |
| Web framework | Next.js App Router (07 shell) · TanStack Query · Tailwind v4 + shadcn/ui | Server Component first paint + client islands | this module owns everything under `/school/ai-matrix`; 07 owns the shell entry |
| Mobile | Expo / expo-router (read-only surfaces) | teacher glances at the week's top weaknesses | no new app dependency |
| AI (indirect) | DeepSeek via 08's `AIService` only | 09 holds no `DEEPSEEK_API_KEY`; never calls a model directly | cost stays O(sections)/week |

---

## 3. Architecture

### 3.1 Component diagram

```text
01 weekly worker (Sun 00:00 Asia/Dhaka, per school) · POST /weekly-matrix/refresh (teacher, 1/day/section)
        │
        ▼
analytics.ComputeSectionWeek(sectionId, weekStart)                    (09 service)
   ├─ 04 hierarchy.GetSection / ResolveUserNodes → section identity + scope (never guessed)
   ├─ 08 `ai.AttemptStats(sectionID, weekStart, weekEnd)`        → MCQ topic aggregates (P0)
   ├─ 05 chat.SectionQuestionSamples + GroupMembers → anonymized samples + distinct authors (in-memory)
   ├─ 08 ai.ClassifyChatQueries(Samples, "bn")   → chat topic tags (P1 — skipped on failure)
   ├─ merge per (topic_tag, language, source): fail_rate · sample_size · insight_text (ANL-BR-008)
   ├─ upsert weekly_pain_points (current open week only — ANL-INV-002)
   ├─ audit.Record("analytics.week_computed" | "analytics.week_degraded_mcq_only")
   └─ invalidate school:{id}:matrix:{week} + school:{id}:matrix:index
Reads: GET /api/v1/analytics/weekly-matrix[/school|/weeks] → suppression filter (min sample)
        → web /school/ai-matrix (Recharts heatmap + drilldown) · app AI Hub summary card
Monday 07:00: analytics.weekly_push (P1) → 06 SendToUser → owning teachers (top 3, bn)
```

### 3.2 Boundary

**Owns (tables / services):** `weekly_pain_points` — nothing else. No FK into 08 tables: the job copies aggregates at compute time, so the matrix survives source retention windows and stays cheap to read.

**Reads (via exported service functions only):** 08 — `AttemptStats`, `ClassifyChatQueries` (frozen by 08's `06` §2); 04 — `ResolveUserNodes`, `GetSection`; 05 — `SectionQuestionSamples`, `GroupMembers` (member/author metadata only); 03 — `auth.RequireRole` + verified claims; 01 — `jobs.Enqueue` + weekly worker, `audit.Record`, Redis limiter; 06 (P1) — per-user push. Cache tags: `school:{id}:matrix:{week}`, `school:{id}:matrix:index`.

### 3.3 Request / data flows

```text
1. Weekly computation: Sunday 00:00 job fans out ACTIVE sections per school → ComputeSectionWeek
   per section (pipeline above) → batched upserts; per-section error isolation; MCQ-only
   publication when classification fails; idempotent so a missed run catches up on restart.
2. On-demand refresh: teacher POST /weekly-matrix/refresh {sectionId} → 202 {jobId, weekStart} →
   analytics.refresh_section recomputes ONLY the current open week → tag invalidation →
   dashboard polls until computedAt changes (≤ 60 s); 1/day/section limiter.
3. Teacher read: GET /weekly-matrix?sectionId= → role/ownership checks → suppression filter
   (sample_size ≥ minSample) → merged per-topic rows + suppressedCount + status → heatmap.
4. Admin read: GET /weekly-matrix/school → whole claim's school → topics × sections grid +
   weighted rollup over unsuppressed rows only.
5. Monday push (P1): sections with ≥1 unsuppressed row → top 3 topics → 06 per-user push (bn),
   once per section/week; suppressed-only sections get no push.
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| week | OPEN (current Sun→Sat; refresh may overwrite) · COMPUTED (immutable history) | Sunday 00:00 job closes the week; recompute/refresh overwrites **only the current open week** (ANL-INV-002, ANL-BR-006) |
| section-week outcome | COMPUTED (mcq+chat) · PARTIAL (mcq only) · EMPTY | classify fails/skips → PARTIAL + neutral note + audit; zero attempts/messages → EMPTY |
| Monday push (P1) | published week + ≥1 unsuppressed row → sent once | suppressed-only or empty sections send nothing (no empty-alarm spam) |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `weekly_pain_points` | One aggregate row per (school, section, week, topic tag, source): `fail_rate`, `sample_size`, `insight_text`, `computed_at` | `school_id` on every row — always from the JWT claim; no repository method accepts a caller-supplied school id (ANL-INV-005) | UNIQUE `(school_id, section_id, week_start, topic_tag, source)` · `(school_id, week_start)` · `(section_id, week_start)` | CHECKs: `language ∈ bn\|en`, `source ∈ mcq\|chat`, `fail_rate` 0–1; recompute = `ON CONFLICT DO UPDATE` (ANL-BR-011); rows with `sample_size < ANALYTICS_MIN_SAMPLE` filtered in the query itself (ANL-INV-004); topic tags render as-is with stored `language` (ANL-BR-009) |

Migration `20261110090001_create_weekly_pain_points`; no production seed — the table is computed (`ANL-BR-012`); fictional "Demo High School" demo rows for the 07 dashboard build; testcontainers fixtures seed 08's `ai_test_answers`.

---

## 5. Contracts

### 5.1 REST endpoints

All routes under `/api/v1/analytics`; auth chain: authenticate → role claims (`auth.RequireRole`) → tenant-scope; verified gate (ANL-BR-010). Errors use the shared RFC-7807 envelope.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | GET · `/api/v1/analytics/weekly-matrix?sectionId=&week=&source=` | TEACHER (own sections) · SCHOOL_ADMIN | Section matrix — merged topic rows, status, `suppressedCount`, `computedAt` | `FORBIDDEN` (cross-teacher) · `TENANT_MISMATCH`/404 · `VALIDATION_FAILED` · `NOT_VERIFIED` | ANL-US-001/002/004/007 |
| 2 | GET · `/api/v1/analytics/weekly-matrix/school?week=&sectionId=` | SCHOOL_ADMIN | School-wide grid — weighted rollup + per-section rows; suppressed rows excluded everywhere | `FORBIDDEN` (incl. teachers) · `TENANT_MISMATCH`/404 | ANL-US-003/004/007 |
| 3 | POST · `/api/v1/analytics/weekly-matrix/refresh` | TEACHER (own section) | On-demand recompute of the current open week → `202 {jobId, weekStart}` | `FORBIDDEN` · `RATE_LIMITED` + `retryAfter` (1/day/section) · `NOT_FOUND` (archived) | ANL-US-008 |
| 4 | GET · `/api/v1/analytics/weekly-matrix/weeks?sectionId=&limit=` | TEACHER / SCHOOL_ADMIN | Up to 12 computed weeks, newest first, with status | as #1 | ANL-US-006 |

CSV export (P2, `ANL-FE-009`) is a web Route Handler that re-fetches the matrix scope-safely and streams `text/csv`; suppressed rows never leave the server.

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `analytics.weekly_matrix` (`ANL-BE-016`) | 01 weekly worker, Sunday 00:00 Asia/Dhaka, per school | Fan-out ACTIVE sections → `ComputeSectionWeek` per section | matrix reads, Monday push | Idempotent upserts (re-run identical); per-section error isolation; retry ×5 backoff → dead-letter + audit; missed run catches up on worker restart |
| `analytics.refresh_section` (`ANL-BE-017`) | `POST …/refresh` (202) | Recompute current open week for one section | requesting teacher | Failure leaves last good rows; limiter allows retry next day |
| `analytics.weekly_push` (`ANL-BE-018`, P1) | After `weekly_matrix` completes a school | Top-3 unsuppressed topics → 06 `SendToUser` (bn), once per section/week marker | owning teachers | 06 owns delivery retry; push failure never blocks the matrix |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `analytics.WeeklyMatrix(schoolId uuid, sectionId *uuid, week *string)` | 06 (push-builder source), future backend consumers | `SectionMatrixDTO{sectionId, sectionLabel, weekStart, status, rows[], suppressedCount, computedAt}` — suppression + merge applied | `NOT_FOUND` · `VALIDATION_FAILED` — caller must already hold school scope; HTTP route adds role/ownership checks |
| `analytics.SchoolMatrix(schoolId uuid, week *string)` | 07 dashboards | `SchoolMatrixDTO{weekStart, schoolRollup[], sections[]}` — suppressed rows excluded everywhere | `NOT_FOUND` · `VALIDATION_FAILED` — read-only, tenant pre-scoped |

Exports return DTOs (never sqlc rows); web/app never import them — they use the REST routes. The two signatures are frozen for Phase-2 consumers; the consumed 08 signatures are frozen by 08's `06` §2.

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/school/ai-matrix` | Pain Point Matrix dashboard — role-adaptive: teacher = own section(s) single-column heatmap; School Admin = topics × sections grid + section filter; `WeekSelector`, `DegradedNote`, `RefreshButton` (teacher), `SuppressionCaption`, empty states | Server Component first paint + TanStack Query client islands (`school:{id}:matrix:{week}`) | School Admin · Teacher (verified) |
| `/school/ai-matrix` (drilldown panel) | Topic drilldown — insight sentence (bn/en re-render from `analytics.insight.*` + `insightParams`), sample size, per-source breakdown (counts only) | Client slide-over, focus-trapped; data ships in the matrix response | same |
| CSV export (P2, `ANL-FE-009`) | Week CSV download — disabled on EMPTY weeks | Route Handler → `text/csv` stream | same scope |

Module 07 owns the Command Center shell/navigation entry ("AI Pain Point Matrix" per `prd.md` §4A); this module owns everything under the route. Heatmap a11y: cells are buttons with numeric fail-rate labels + aria-labels ("ক্যালকুলাসের লিমিট — ৬০%, সতর্কতা"); severity never colour-only; axe clean on all states.

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/ai-hub/matrix` | Weekly pain-point summary — top-3 topics per owned section (cards, severity colour, bn numerals); inline empty states; degraded note | push `type=analytics_weekly` (module 06, P1) · AI Hub entry card | MMKV-cached last matrix + "অফলাইন — সর্বশেষ হিসাব / Offline — showing the last computed matrix" banner |
| `/(tabs)/ai-hub/matrix/[sectionId]` | Section detail — full topic list, per-source counts, week navigation (≤12 weeks, prev/next) | summary card tap · push payload `{sectionId, weekStart, topTopics[≤3]}` | cached weeks only; uncached weeks show "সংযোগ প্রয়োজন / Connection needed" |

Read-only surface — refresh stays a web-dashboard action; no write path exists, so nothing is queued or silently lost (`05` §8). 360px-first, bn-first, `Intl` bn numerals.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| None direct — DeepSeek is reached only via 08's exports | Chat-query classification (indirect, P1) | Internal Go call to `ai.*` exports | 08's `DEEPSEEK_API_KEY` — 09 holds none | 08-owned (classify ≤ 30 s); 09 retries at job level (×5 backoff) | MCQ-only matrix, `PARTIAL` status + neutral note; matrix never blocks on AI |
| Redis | Matrix cache tags (TTL 5 min) + refresh limiter | RESP (go-redis) | `REDIS_URL` (01-owned) | 2 s · 1× then fall through | Reads uncached (Postgres fall-through); refresh limiter fails **closed** (cost guard) |
| (none other) | — | — | — | — | No FCM, R2, payment or SMS contact from this module |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None module-owned | — | — | 09 declares no env vars; `REDIS_URL` and job config belong to module 01, and 09 deliberately holds no `DEEPSEEK_API_KEY` (all model calls live behind 08) |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Min sample size `ANALYTICS_MIN_SAMPLE` (default 5 — `TODO: Confirm` OQ-2) | Suppression always applied at read (no opt-out) |
| Chat sample cap per section/week (default 500 messages) | Week window Sun→Sat Asia/Dhaka; `week_start` = the Sunday |
| Per-school feature availability (licensed-feature toggle, module 07) | Refresh limit 1/day/section; refresh recomputes the current week only |
| Monday push enable/timing (default Mon 07:00 Asia/Dhaka, bn) | Severity thresholds: <0.30 steady · 0.30–0.49 watch · 0.50–0.69 alert · ≥0.70 critical |
| — | Sources enum `mcq` \| `chat`; Super Admin exclusion; aggregates-only invariant |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims (`auth.RequireRole`) → tenant-scope; verified gate on every route (ANL-BR-010) — unverified/pending users refused `NOT_VERIFIED` |
| Role matrix | Teacher: matrix + weeks for **own sections only** (04 `ResolveUserNodes`); refresh own sections. School Admin: whole own school + section filter. Super Admin, Student, Guardian, Partner: **no access** — per-school licensed feature (OQ-1 default); unauthenticated → `UNAUTHENTICATED` |
| Tenant scope | `school_id` always from the JWT claim, never the request (ANL-BR-001/INV-005); no repository method accepts a caller-supplied school id; cross-school reads/refresh → `TENANT_MISMATCH`/404 — no rows, no metadata |
| Rate limits | Reads: default class, behind 5-min Redis cache; refresh: 1/day/section (Redis limiter, fail-closed on Redis outage → `RATE_LIMITED` + `retryAfter`) |
| Audit events | Refresh requested; `analytics.week_computed` / `analytics.week_degraded_mcq_only` per section; weekly-run summaries; recompute targeting a closed week is a no-op + audit warning; compute-run outcomes are ops-only, no teacher exposure |
| Privacy / minors | Aggregates only: raw chat text is never stored in `weekly_pain_points`, returned by any endpoint, or logged (ANL-BR-005/INV-003, asserted by `ANL-IT-008/108`); rows below min-sample suppressed on every read + excluded from rollups, `suppressedCount` reported (ANL-BR-004); chat sampling uses the official section group only (never DMs/clubs), capped; per-student weakness view **REJECTED** (`02` §10) — section-level aggregate with minimum sample is the deepest granularity |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `FORBIDDEN` | Cross-teacher section read; teacher on school route; refresh of a non-owned section | ANL-BR-002/003 | "এই সেকশনের রিপোর্ট দেখার অনুমতি নেই / You're not allowed to view this section's report" — no rows, no metadata |
| `TENANT_MISMATCH` (404 body) | Cross-school read or refresh | ANL-BR-001 | Nothing leaks (`ANL-IT-002/102`) |
| `VALIDATION_FAILED` (`analytics.week_invalid` / `analytics.week_range`) | Week not a Sunday / in the future / > 52 weeks back; bad uuid; invalid source filter | §6 of `01` | Field-level bn/en copy; selectors re-validate |
| `RATE_LIMITED` + `retryAfter` | Second refresh for the same section the same day | ANL-BR-007 | "আজ এই সেকশনের জন্য আপডেট সীমা শেষ — কাল আবার চেষ্টা করুন / Today's refresh is used up — try again tomorrow"; button disabled with `retryAfter` |
| `NOT_VERIFIED` | Pending teacher/admin | ANL-BR-010 | Module 03 verification guidance |
| `NOT_FOUND` | Unknown section; refresh on an archived section | §2 #1/#3 | History reads still resolve; refresh refuses, week nav stays usable |
| `UNAUTHENTICATED` | No session | Every route | Login redirect |

All errors surface as RFC-7807 `application/problem+json`; messages resolve via `analytics.*` / `validation.*` catalogs — **bn + en** from day one (bn default).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog via the api; no raw chat content in any log line (asserted by `ANL-IT-008/108`) |
| Metrics / counters | Per-section compute outcomes (computed / degraded / empty) into audit — ops only; `suppressedCount` per read; refresh-limiter hits; cache-tag hit behaviour |
| Health contribution | None module-specific — the weekly-worker schedule alarm lives in 01's job table |
| Jobs & retries | `analytics.weekly_matrix` (Sunday 00:00, idempotent upserts, per-section isolation, retry ×5 backoff → dead-letter + audit; missed Sunday window catches up on worker restart); `analytics.refresh_section` (current week only; failure keeps last good rows); `analytics.weekly_push` (P1, once-per-section/week marker prevents re-spam) |
| Runbook pointers | Worker-down catch-up (`02` §8 #3); Redis-down = reads fall through to Postgres while refresh fails closed; 04 scope-resolution unavailable → reads refuse `INTERNAL` — scope is never guessed (cached section membership, 5 min, softens blips); deploy/runbooks per module 15 |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Suppression + rollup, mcq+chat merge + severity mapping, insight rendering bn/en, fail-rate/sample-size math, payload validation | `ANL-UT-001–005` (`03` §6) · `ANL-UT-101–102` (`06` §9) | go test |
| Integration | Role scoping (cross-teacher `FORBIDDEN`, teacher on school route), cross-tenant denial, aggregation correctness from seeded `ai_test_answers`, idempotent recompute + `RATE_LIMITED`, suppression end-to-end, classify-down `PARTIAL`, tag invalidation, aggregates-only invariant, auth chain | `ANL-IT-001–009` · `ANL-IT-101–108` | testcontainers Postgres |
| E2E | Teacher heatmap + drilldown golden path; School Admin grid + insufficient-data empty state; Maestro summary → detail → airplane-mode cached render | `ANL-E2E-001–002` (Playwright + axe) · `ANL-E2E-003` (Maestro) | axe clean on all states |
| CI | — | — | `go test/vet/lint`; mandatory: unauthenticated denied, cross-tenant `TENANT_MISMATCH`/404, **suppressed rows never returned by any read path**, publish guard blocks `TODO:` |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Year 1: 10 schools × ~10 sections × 52 weeks × ~6 topics × ≤2 sources ≈ 62k rows/year — trivial for Postgres; the job writes per school in one batched transaction |
| Hot paths + indexes | Section matrix on the unique-index prefix `(school_id, section_id, week_start)`; school grid `(school_id, week_start)`; weeks list `DISTINCT week_start … LIMIT 12` on `(section_id, week_start)` |
| Latency targets | Dashboard = one indexed read after materialization; Redis 5-min TTL absorbs dashboard refresh storms; refresh completes within the job budget (client polls ≤ 60 s); job cost O(sections)/week — one `AttemptStats` aggregate + ≤1 batched classify call per section |
| Bundle / payload impact | Web route gains Recharts ~45 kB gzip, code-split to the admin route only; app adds no new dependency |
| Caching | Tags `school:{id}:matrix:{week}` + `…:matrix:index`; past weeks are immutable → long TTLs safe; every compute path invalidates the current week's tag |

---

## 14. Risks & Open Questions

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Matrix granularity + audience (OQ-1) | Scope disputes | Rahul | Open | Weekly, per section, per topic tag; teacher = own sections only; School Admin = whole school; Super Admin none |
| 2 | Minimum sample size (OQ-2) | Small sections suppress everything | Rahul | Open — `TODO: Confirm` | 5 (`ANALYTICS_MIN_SAMPLE`); revisit with pilot feedback |
| 3 | Job schedule + on-demand recompute policy (OQ-3) | Freshness expectations | Rahul | Open | Sunday 00:00 Asia/Dhaka weekly; teacher refresh 1/day/section, current week only |
| 4 | Include chat-query source at launch? (OQ-4) | Matrix richness vs noise | Rahul | Open | Chat is P1 (capped sample of section-group messages); MCQ alone is sufficient |
| 5 | Monday push timing + locale (OQ-5) | Notification fatigue | Rahul | Open | Monday 07:00 Asia/Dhaka, bn, top 3, only when ≥1 unsuppressed row |
| 6 | 08 `AttemptStats` shape serves directly (`02` §11 risk 1) | Compute logic leaks into 09 | 08 owner | Contract frozen in 08's `06` §2 | `ANL-IT-003/103` prove the mapping |
| 7 | Bangla slang classification quality (`02` §11 risk 2) | Noise rows erode trust | Rahul | Assumption | Chat stays P1 behind a neutral note; capped sample; suppression; tunable threshold |
| 8 | Teachers read `fail_rate` correctly (`02` §11 risk 3) | Wrong remediation | Rahul | Mitigated | Insight sentence + sample size always shown together; severity labels; definition tooltip |
| 9 | Small pilot sections (<5 with data) feel empty (`02` §11 risk 4) | Feature seems broken | Rahul | Accepted | `suppressedCount` + honest empty copy; threshold is config |
| 10 | Chat sampling drifting into private content (`02` §11 risk 5) | Trust failure with parents | Rahul | Mitigated | Official section group only, capped sample, aggregates-only invariant tested (`ANL-IT-008/108`) |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-02 — pain-point intelligence for teachers | §5.2 · §4A | ANL-US-001–011 | ANL-BE-001–018 · ANL-INT-001–009 | ANL-UT-001–005/101–102 · ANL-IT/E2E ranges |
| `brd.md` §6 — minors' data minimization | §6 | ANL-US-004 · ANL-US-007 | ANL-BE-008 · ANL-BE-012–015 | ANL-IT-005/105 · ANL-IT-002/102 · ANL-IT-008/108 |
| PRD §4A — Command Center analytics section | §4A | ANL-US-003 | ANL-BE-003 · ANL-FE-001/004 · ANL-INT-008 | ANL-E2E-002 |
| `brd.md` §8 Phase 2 exit — "teachers see a Pain Point Matrix" | — | ANL-US-005 | ANL-BE-016 · ANL-INT-004 | ANL-IT-004/104 |
| PRD §5.2 — chat queries alongside failed MCQs | §5.2 | ANL-US-009 | ANL-BE-001/007 · ANL-INT-002/005 | ANL-IT-007/106 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migration re-versioned `20261110090001` (after 08); consumes `ai.AttemptStats(sectionID, weekStart, weekEnd)` per-topic data and 05 `chat.SectionQuestionSamples` (anonymized, never stored); `notify.SendToUser`; teacher web access confirmed in 07 | Claude |
