# Teacher Analytics — Integration Tasks

**Module:** `09-teacher-analytics` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

`02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
**contract**. No cross-module call, cache key or external dependency may exist in code unless it is
declared here (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `08-ai-study-hub` | we call them | `ai.AttemptStats(sectionId, week)` — failed-MCQ aggregates from `ai_test_answers` (P0 source) | degraded per section — week publishes EMPTY; job retries; never fabricated |
| I-2 | `08-ai-study-hub` | we call them | `ai.ClassifyChatQueries(ctx, Samples, Locale)` — sampled section-group queries → topic tags (P1 source) | degraded — MCQ-only matrix published with neutral note + audit |
| I-3 | `05-communication-engine` | we call them | `chat.GroupMembers(groupID)` — official section group + distinct authors; **aggregates only, no raw message content ever leaves the aggregation boundary** | degraded — chat source skipped that week (MCQ-only) |
| I-4 | `04-organization-hierarchy` | we call them | `hierarchy.ResolveUserNodes(userId)` (teacher → own sections; school_admin → school) + `hierarchy.GetSection(sectionID)` | fatal to reads — refuse `INTERNAL`, never guess scope; job sections skipped + retried |
| I-5 | `03-identity-access` | they gate us | `auth.RequireRole` + verified-status claims on every route | fatal by design — `UNAUTHENTICATED` / `FORBIDDEN` / `NOT_VERIFIED` |
| I-6 | `01-foundations` | we call them | `jobs.Enqueue` + weekly worker (Sunday 00:00 Asia/Dhaka), `audit.Record`, Redis limiter | degraded — refresh unavailable, weekly schedule catches up on worker restart |
| I-7 | `06-notifications` (P1) | we call them | per-user push export (export name fixed in 06's spec; referenced here as `notifications.SendToUser`) — Monday teacher summary | degraded, never fatal — matrix still in-app/web; push skipped |
| I-8 | `07-command-center-web` | they call us | REST §2 of `03-backend-tasks.md` + exports §2 below for the Command Center AI-matrix section | degraded — dashboard shows error/empty state |
| I-9 | DeepSeek (external) | indirect only | all model calls live behind 08's `AIService`; 09 holds no `DEEPSEEK_API_KEY` | degraded via I-1/I-2 paths |

## 2. Exported Contract

```text
analytics.WeeklyMatrix(schoolId uuid, sectionId *uuid, week *string) (SectionMatrixDTO, error)
analytics.SchoolMatrix(schoolId uuid, week *string) (SchoolMatrixDTO, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `WeeklyMatrix(schoolId, sectionId?, week?)` | 06 (push builder source data), future backend consumers | `SectionMatrixDTO{sectionId, sectionLabel, weekStart, status, rows[], suppressedCount, computedAt}` — suppression + merge applied | `NOT_FOUND`, `VALIDATION_FAILED` | Caller must already hold the school scope (service-side callers); HTTP route adds role/ownership checks on top. Row shape per `03` §2 |
| `SchoolMatrix(schoolId, week?)` | 07 dashboards | `SchoolMatrixDTO{weekStart, schoolRollup[], sections[]}` — suppressed rows excluded everywhere | `NOT_FOUND`, `VALIDATION_FAILED` | Read-only, tenant pre-scoped; never exposes suppressed rows |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first. Web/app never import these — they use the REST routes.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `ai.AttemptStats(sectionId, week)` — per-topic failed/total aggregates | 08 | Section publishes EMPTY; job retry ×5 backoff; alarm after dead-letter; prior weeks keep serving |
| `ai.ClassifyChatQueries(ctx, Samples, Locale="bn")` — tags for the capped message sample | 08 | MCQ-only rows published; `status = "PARTIAL"` + neutral note; audit `analytics.week_degraded_mcq_only` |
| `chat.GroupMembers(groupID)` — section-group boundary + distinct authors (metadata only) | 05 | Chat source skipped (MCQ-only); never a blocker — chat is P1 |
| `hierarchy.ResolveUserNodes(userId)` — teacher → own sections; school_admin → school | 04 | Reads refuse `INTERNAL`; job marks section skipped + retries; scope is never approximated |
| `hierarchy.GetSection(sectionID)` — section identity/label | 04 | `NOT_FOUND` propagates; archived section blocks refresh only |
| `auth.RequireRole` + verified claims | 03 | `UNAUTHENTICATED` / `FORBIDDEN` / `NOT_VERIFIED` — the gate is the feature |
| `jobs.Enqueue` + weekly worker · `audit.Record` · Redis limiter | 01 | Refresh returns 503-style problem (`INTERNAL`) with bn/en copy; weekly run catches up; audit falls back to log-only |
| `notifications.SendToUser(userId, payload)` (P1, name per 06's spec) | 06 | Push skipped; once-per-week marker prevents re-spam; in-app matrix unaffected |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| `analytics.weekly_matrix` job upsert (per section) | `school:{schoolId}:matrix:{weekStart}` + `school:{schoolId}:matrix:index` |
| `analytics.refresh_section` completion | `school:{schoolId}:matrix:{weekStart}` + `school:{schoolId}:matrix:index` |

| Read | Tagged with |
| --- | --- |
| `GET /api/v1/analytics/weekly-matrix` | `school:{schoolId}:matrix:{weekStart}` |
| `GET /api/v1/analytics/weekly-matrix/school` | `school:{schoolId}:matrix:{weekStart}` |
| `GET /api/v1/analytics/weekly-matrix/weeks` | `school:{schoolId}:matrix:index` |
| App queries | same tags via the generated client's revalidation headers (07 shares the convention) |

Redis TTL 5 min behind the tags; past weeks are immutable so long TTLs are safe; the current week's
tag is invalidated by every compute path.

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| DeepSeek (via 08 only) | internal Go call — `ai.*` exports | 08's `DEEPSEEK_API_KEY`; 09 holds none | 08-owned (classify ≤ 30 s) | 08-owned; 09 retries at the job level (×5 backoff) | MCQ-only matrix + neutral note; matrix never blocks on AI |
| Redis | RESP (go-redis) cache + limiter | `REDIS_URL` | 2 s | 1× then fall through | Reads uncached (Postgres); refresh limiter fails **closed** (cost guard) |
| (none other) | — | — | — | — | No FCM, R2, payment or SMS contact from this module |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Web heatmap (`ANL-FE-002`) | `GET /api/v1/analytics/weekly-matrix` / `…/school` | Rows merged per topic; `status` drives the degraded note; `suppressedCount` drives the privacy caption |
| Web week/section selectors | `GET …/weekly-matrix/weeks` (+ payload sections) | ≤12 weeks, `COMPUTED`/`PARTIAL`/`EMPTY`; `?week=` echoes back as `weekStart` |
| Web drilldown | data from the matrix response | `insightText` as-is or re-rendered from `analytics.insight.*` + `insightParams{percent, topic}`; sources = counts only |
| Web refresh button | Route Handler → `POST …/weekly-matrix/refresh` | 202 `{jobId, weekStart}` → poll matrix until `computedAt` changes; `RATE_LIMITED` → `retryAfter` copy |
| Web CSV export (P2) | Route Handler re-fetch (scope-safe) | `text/csv`; suppressed rows never leave the server |
| App summary/detail (`ANL-AP-001/002`) | `GET …/weekly-matrix` + `…/weeks` | Same DTOs; offline via cached last matrix |
| Monday push tap (06 payload) | deep link `/(tabs)/ai-hub/matrix/[sectionId]` | Payload carries `{sectionId, weekStart, topTopics[≤3 tags]}` — counts only, no insight text needed |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. The two exported Go signatures are frozen for
Phase 2 consumers (06 push, 07 dashboards). The 08 consumed signatures
(`ai.AttemptStats`, `ai.ClassifyChatQueries`) are frozen by 08's `06` §2 — any change there requires
a migration note here. The suppression threshold is configuration, never a contract change.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 08 classify (DeepSeek/AI) | MCQ aggregation + all reads | MCQ-only matrix, `PARTIAL` status + "চ্যাট বিশ্লেষণ নেই / No chat analysis" note | Next weekly run or teacher refresh re-classifies; audit records the gap |
| 08 `AttemptStats` | Reads of already-computed weeks | Current week EMPTY for affected sections | Job retry ×5; dead-letter alarm; previous weeks untouched |
| 05 communication-engine | MCQ-only compute; all reads | MCQ-only matrix (chat P1 skipped silently) | Chat source returns with 05 |
| 04 hierarchy | Nothing scope-resolved | Reads refuse with `INTERNAL` — scope is never approximated or guessed | Cached section memberships (5 min) absorb brief blips; alarm on 04 |
| 01 jobs worker | All reads; last computed matrix | Refresh button shows unavailable copy; stale `computedAt` | Worker restart runs the missed Sunday window (idempotent upserts) |
| Redis | Reads (Postgres fall-through) | Slightly slower dashboard; refresh refused (fail-closed) | Limiter + tags restore with Redis |
| 06 / FCM (P1 push) | Everything else | No Monday push; matrix in app/web | 06 retry queue; once-per-week marker avoids duplicates |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ANL-UT-101` | Suppression: rows `sample_size < 5` hidden + counted; rollup excludes them | Unit | `ANL-BR-004` |
| `ANL-UT-102` | mcq+chat merge per topic; chat share semantics; severity mapping | Unit | `ANL-BR-008`, `ANL-BR-010` severity constant |
| `ANL-IT-101` | Teacher own-sections only: own section 200 · **cross-teacher `FORBIDDEN`** · school admin section read 200 · teacher on school route `FORBIDDEN` | Integration (testcontainers Postgres) | `ANL-BR-002/003` |
| `ANL-IT-102` | Cross-tenant read + refresh → `TENANT_MISMATCH`/404; no rows, no metadata | Integration | `ANL-BR-001` |
| `ANL-IT-103` | Aggregation correctness: seeded `ai_test_answers` → expected `fail_rate`/`sample_size` per topic/source | Integration | contract with 08 (`AttemptStats` mapping) |
| `ANL-IT-104` | Recompute idempotent: same week computed twice → identical rows; refresh twice in a day → `RATE_LIMITED` | Integration | `ANL-BR-011`, `ANL-BR-007` |
| `ANL-IT-105` | Suppression IT end-to-end: `sample_size < 5` absent from REST responses, exports and rollup | Integration | `ANL-BR-004`, `ANL-INV-004` |
| `ANL-IT-106` | 08 classify stub down → MCQ-only rows, `PARTIAL` status, audit entry; sibling sections unaffected | Integration | I-2 degradation |
| `ANL-IT-107` | Weekly job + refresh upserts invalidate `school:{id}:matrix:{week}`; next read sees fresh data | Integration | §4 tag contract |
| `ANL-IT-108` | Aggregates-only: full run over a seeded group leaves no raw message text in tables, logs or responses | Integration | `ANL-BR-005`, `ANL-INV-003` |
| `ANL-E2E-001` | Playwright: teacher signs in → `/school/ai-matrix` renders seeded heatmap → drilldown shows insight "60% of students are struggling with Calculus limits" + sample size | Playwright (web) | `ANL-US-001/002` golden path |
| `ANL-E2E-002` | Playwright: School Admin school grid + section filter; empty week shows the insufficient-data state | Playwright (web) | `ANL-US-003/004` |
| `ANL-E2E-003` | Maestro: teacher opens AI Hub summary with seeded data → detail → airplane-mode cached render | Maestro (app) | `ANL-AP-001/004` |

## 10. Task Checklist

- [ ] `ANL-INT-001` Implement + export `analytics.WeeklyMatrix` / `analytics.SchoolMatrix` (DTOs, suppression applied) — ____
- [ ] `ANL-INT-002` Consume 08: `AttemptStats` wiring + classify call with capped sample + Locale="bn" — ____
- [ ] `ANL-INT-003` Consume 04/05/03: `ResolveUserNodes`/`GetSection` scoping, `GroupMembers` boundary, `auth.RequireRole` gates — ____
- [ ] `ANL-INT-004` Register `analytics.weekly_matrix` (Sun 00:00 Asia/Dhaka) + `analytics.refresh_section` with 01 worker — ____
- [ ] `ANL-INT-005` P1 Monday push step via 06 (`SendToUser`), once-per-week marker — ____
- [ ] `ANL-INT-006` Cache tags `school:{id}:matrix:{week}` + `…:matrix:index`; invalidation on both compute paths — ____
- [ ] `ANL-INT-007` Degradation paths live (classify-down → PARTIAL; jobs-down → refresh unavailable copy) — ____
- [ ] `ANL-INT-008` Freeze DTOs with 06/07 review; OpenAPI entries + contract regen — ____
- [ ] `ANL-INT-009` Tests `ANL-UT-101/102` · `ANL-IT-101`–`108` · `ANL-E2E-001`–`003` green in CI — ____
