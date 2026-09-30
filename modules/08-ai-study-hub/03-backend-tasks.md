# AI Study Hub — Backend Tasks & Database Design

**Module:** `08-ai-study-hub`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (ai):** N/A at v1 — `applications/ai` (Python FastAPI) is a later adapter behind the same `AIService` interface (internal HTTP, never client-facing); this module ships the Go interface + DeepSeek adapter now
**Stack (web):** N/A — no web frontend in this module (module 07 renders cost cards; module 09 renders analytics; both consume the endpoints/exports declared here)
**Last updated:** 2026-09-30

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `note_scans` (model `NoteScan`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `owner_id` | `uuid` | no | — | FK → 03 users (student); archive is owner-anchored |
| `school_id` | `uuid` | no | — | **Tenant column** → 04 school node |
| `section_id` | `uuid` | yes | — | 04 section context at scan time (informational) |
| `image_asset_id` | `uuid` | no | — | FK → 05 `media_assets`; must be `confirmed` + owned (INV-3) |
| `status` | `text` | no | `processing` | `processing` \| `ready` \| `failed` (CHECK) |
| `summary` | `text` | yes | — | Model summary, bn/en **as returned** (BR-015) |
| `shared` | `boolean` | no | `false` | School-wide visibility toggle — default OFF (BR-006) |
| `locale` | `text` | no | — | Request locale (`bn` default) — language the model was asked for |
| `error_code` | `text` | yes | — | Terminal failure reason (feeds retry UX) |
| `ready_at` | `timestamptz` | yes | — | Set on processing → ready |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK status; owner must be VERIFIED at creation (service). **Indexes:**
`(owner_id, status, created_at DESC)` → "my scans"; partial `(school_id) WHERE shared` →
school-shared archive; GIN `pg_trgm` on `summary` → text search; `(image_asset_id)` → asset
lifecycle joins.

#### `note_tags` (model `NoteTag`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `scan_id` | `uuid` | no | — | FK → `note_scans` ON DELETE CASCADE |
| `level` | `text` | no | — | `subject` \| `chapter` \| `topic` (CHECK) |
| `value` | `text` | no | — | As returned by the model (display) |
| `normalized` | `text` | no | — | NFC, trimmed, lowercase — search/dedupe key |

**Constraints:** UNIQUE `(scan_id, level, normalized)`. **Indexes:** `(normalized, level)` →
tag-chip facets + tag filters; `(scan_id)` → detail render.

#### `ai_tests` (model `AITest`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `kind` | `text` | no | — | `practice` \| `class_test` (CHECK) |
| `school_id` | `uuid` | no | — | **Tenant column** → 04 school node |
| `section_id` | `uuid` | yes | — | 04 section; **NOT NULL iff `kind='class_test'`** (CHECK) |
| `creator_id` | `uuid` | no | — | 03 user (student for practice, teacher for class_test) |
| `subject` / `chapter` / `topic` | `text` | no/no/yes | — | Generation scope; topic optional |
| `question_count` | `int` | no | `10` | Requested count, 5–30 |
| `status` | `text` | no | `generating` | `generating` \| `ready` \| `published` \| `closed` (CHECK) |
| `questions_snapshot` | `jsonb` | yes | — | Frozen question set written at publish (INV-4) |
| `locale` | `text` | no | — | Content language of the generated paper |
| `published_at` / `closed_at` | `timestamptz` | yes | — | Lifecycle stamps |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK kind/section pairing; CHECK `status IN ('published','closed') ⇒
questions_snapshot IS NOT NULL`. **Indexes:** `(creator_id, status, created_at DESC)` → "my
created tests"; `(section_id, status, published_at DESC)` → section test list (students);
`(school_id, kind, status)` → tenant stats.

#### `ai_test_questions` (model `AITestQuestion`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `test_id` | `uuid` | no | — | FK → `ai_tests` ON DELETE CASCADE |
| `ord` | `int` | no | — | 1-based order within the test |
| `stem` | `text` | no | — | Question text (bn/en per test locale) |
| `options` | `jsonb` | no | — | Array of exactly 4 strings (schema-validated) |
| `correct_index` | `int` | no | — | 0–3 (CHECK); **never serialized to students pre-grade** (INV-5) |
| `explanation` | `text` | yes | — | Shown after grading / to the teacher |

**Constraints:** UNIQUE `(test_id, ord)`; `correct_index BETWEEN 0 AND 3`. **Indexes:**
`(test_id, ord)` → paper render + grading join.

#### `ai_test_attempts` (model `AITestAttempt`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `test_id` | `uuid` | no | — | FK → `ai_tests` |
| `student_id` | `uuid` | no | — | FK → 03 users |
| `school_id` | `uuid` | no | — | **Tenant column** = student's school |
| `started_at` | `timestamptz` | no | `now()` | |
| `submitted_at` | `timestamptz` | yes | — | Set at submit |
| `score` | `int` | yes | — | Correct count, written at auto-grade |
| `status` | `text` | no | `in_progress` | `in_progress` \| `submitted` \| `graded` (CHECK) |

**Constraints:** UNIQUE `(test_id, student_id)` (one attempt, INV-6); test must be
`published` (class) / `ready` (practice) and not `closed` (service). **Indexes:** `(test_id,
status)` → teacher results/stats; `(student_id, status)` → "tests I've taken".

#### `ai_test_answers` (model `AITestAnswer`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `attempt_id` | `uuid` | no | — | FK → `ai_test_attempts` ON DELETE CASCADE |
| `question_id` | `uuid` | no | — | FK → `ai_test_questions`; must belong to the attempt's test (service) |
| `chosen_index` | `int` | no | — | 0–3 (CHECK); latest choice wins (upsert) |
| `correct` | `boolean` | no | `false` | Computed **at submit** against `correct_index` (BR-010) |

**Constraints:** UNIQUE `(attempt_id, question_id)`. **Indexes:** `(attempt_id)` → resume +
grading; `(question_id)` → per-question miss stats (`AttemptStats`).

#### `ai_usage_ledger` (model `AIUsageLedger`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → 03 users; `classify` rows use the initiating system actor |
| `feature` | `text` | no | — | `scan` \| `mcq_gen` \| `classify` (CHECK) |
| `week_start` | `date` | no | — | Monday, Asia/Dhaka (fixed in code) |
| `count` | `int` | no | `0` | Calls this week (quota basis) |
| `tokens_in` / `tokens_out` | `bigint` | no | `0` | Cumulative |
| `cost_usd` | `numeric(10,4)` | no | `0` | Cumulative — powers the breaker + cost report |
| `model` | `text` | no | — | Model used (last call; constant per feature in practice) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | `updated_at` powers daily cost sums |

**Constraints:** UNIQUE `(user_id, feature, week_start)` — quota reservation is a conditional
upsert on this key (INV-2). **Indexes:** `(updated_at)` → daily cost sum (breaker); `(week_start)`
→ weekly reporting; `(user_id, feature, week_start)` UNIQUE → quota read.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261101090000_aih_note_scans_tags` (note_scans + note_tags, CHECKs, trgm GIN, partial shared index) | ✅ |
| 2 | `20261101091000_aih_tests_questions` (ai_tests + ai_test_questions, kind/section + snapshot CHECKs) | ✅ |
| 3 | `20261101092000_aih_attempts_answers` (ai_test_attempts + ai_test_answers, unique attempt, per-question unique) | ✅ |
| 4 | `20261101093000_aih_usage_ledger` (ai_usage_ledger, UNIQUE quota key, breaker/report indexes) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| "Demo High School" (fictional, marked): 2 scans (bn) with subject/chapter/topic tags + summaries, 1 `published` practice test (10 MCQs, bn, physics ch. 3), 1 graded attempt with answers, ledger rows for both features | `DRAFT` (clearly fictional) | `prd.md` §5.2 shapes; `TODO:` none — fictional demo data per `prompt.txt` §12; never seeded into real tenants |

---

## 2. Server Contracts

### Endpoint summary (all Go handlers generated from the OpenAPI spec; auth chain on every route: authenticate → load role claims → tenant-scope → `auth.RequireVerified`)

| # | Endpoint | Purpose | Errors (beyond common) | Stories |
| --- | --- | --- | --- | --- |
| 1 | `POST /api/v1/ai/notes` | Create scan from a confirmed 05 media asset → reserve quota → enqueue tagging job | `QUOTA_EXCEEDED` · `VALIDATION_FAILED` · `RATE_LIMITED` | US-001 |
| 2 | `GET /api/v1/ai/notes?scope=mine\|shared&status=&cursor=` | My archive / shared-in-school list, 20/page | — | US-001/002 |
| 3 | `GET /api/v1/ai/notes/search?q=&tags=&scope=` | pg_trgm text + tag-chip search (visibility matrix) | `RATE_LIMITED` | US-002 |
| 4 | `GET /api/v1/ai/notes/{id}` | Scan detail (tags, summary, image URL, share state) | `TENANT_MISMATCH`/404 | US-001 |
| 5 | `PATCH /api/v1/ai/notes/{id}/share` | Owner toggles school-wide share | `FORBIDDEN` (non-owner) | US-001 |
| 6 | `DELETE /api/v1/ai/notes/{id}` | Owner deletes scan + tags (audited) | `FORBIDDEN` | US-001 |
| 7 | `POST /api/v1/ai/tests` | Student: practice gen · Teacher: class-test gen (role must match kind) → enqueue MCQ job | `QUOTA_EXCEEDED` · `VALIDATION_FAILED` | US-003/005 |
| 8 | `GET /api/v1/ai/tests?role=created\|taken\|section` | My created / taken / my-section lists | — | US-004/005/006 |
| 9 | `GET /api/v1/ai/tests/{id}` | Test detail — **key-gated** (INV-5); teacher gets key | `TENANT_MISMATCH`/404 | US-003/006 |
| 10 | `POST /api/v1/ai/tests/{id}/publish` | Teacher publishes (snapshot freeze + section push) | `FORBIDDEN` · `CONFLICT` (not ready) | US-004 |
| 11 | `POST /api/v1/ai/tests/{id}/close` | Teacher closes (new attempts refused) | `FORBIDDEN` · `CONFLICT` | US-004 |
| 12 | `POST /api/v1/ai/tests/{id}/attempts` | Start attempt (unique per test+student) | `CONFLICT` (closed/already attempting) | US-006 |
| 13 | `POST /api/v1/ai/attempts/{id}/answers` | Upsert one answer `{questionId, chosenIndex}` (in_progress only) | `VALIDATION_FAILED` · `CONFLICT` | US-006 |
| 14 | `POST /api/v1/ai/attempts/{id}/submit` | Auto-grade (deterministic) → score + result payload with key | `CONFLICT` (already graded) | US-007 |
| 15 | `GET /api/v1/ai/usage` | Own quota state per feature (used/limit/week_start/plan) | — | US-008 |
| 16 | `GET /api/v1/ai/admin/cost-report?month=YYYY-MM` | Super Admin: platform · School Admin: own tenant | `FORBIDDEN` | US-010 |

Common errors on every route (RFC-7807 `application/problem+json`): `UNAUTHENTICATED` ·
`FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` · `NOT_FOUND` · `NOT_VERIFIED` ·
`QUOTA_EXCEEDED` · `RATE_LIMITED` · `CONFLICT` · `INTERNAL`. Rate-limit class **`ai`** on
1/3/7/12/13 (generation + search + answer writes); default class elsewhere.

### Detailed endpoint blocks

### Endpoint `POST /api/v1/ai/notes` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope → verified gate |
| **Input** | `{imageAssetId}`; contract-generated validator; asset re-verified server-side (confirmed, kind=image, owner) — never trusted from the client |
| **Result** | `{ "data": { scan: { id, status: "processing", createdAt } } }` — enqueue is async; client polls/pushes |
| **Errors** | `QUOTA_EXCEEDED` (BR-002/004) · `VALIDATION_FAILED` (asset unconfirmed/foreign) · `NOT_VERIFIED` · `RATE_LIMITED` |
| **Rate limit** | `ai` |
| **Audit** | No (create is benign); delete/share are audited |
| **Stories** | AIH-US-001 · BR-002/003/006 |

### Endpoint `POST /api/v1/ai/tests` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope → verified gate |
| **Input** | `{kind, subject, chapter, topic?, count?, sectionId?}`; role-kind match enforced (student⇒practice, teacher⇒class_test); teacher's section validated via `hierarchy.ResolveUserNodes` |
| **Result** | `{ "data": { test: { id, status: "generating", questionCount } } }` |
| **Errors** | `QUOTA_EXCEEDED` (student practice, BR-003; teacher cap BR-005) · `VALIDATION_FAILED` (count 5–30, scope lengths) · `FORBIDDEN` (kind/role mismatch, foreign section) |
| **Rate limit** | `ai` |
| **Audit** | Yes on class_test creation (teacher-authored artifact) |
| **Stories** | AIH-US-003/005 · BR-002/003/005 |

### Endpoint `POST /api/v1/ai/attempts/{id}/submit` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope → verified gate; attempt owner only |
| **Input** | path id; empty body |
| **Result** | `{ "data": { attempt: { score, status: "graded" }, results: [ { questionId, ord, stem, chosenIndex, correctIndex, correct, options, explanation } ] } }` — key released **only now** (INV-5); single transaction: grade → score → status; no model call (BR-010) |
| **Errors** | `CONFLICT` (already submitted/graded) · `NOT_FOUND`/`TENANT_MISMATCH` (foreign attempt) |
| **Rate limit** | default class |
| **Audit** | No |
| **Stories** | AIH-US-007 · BR-010 |

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web UI. Consumers behind the generated `openapi-fetch` client (never
the database directly): module 07 renders the Super/School Admin cost cards from endpoint #16;
module 09 renders teacher analytics from the `ai.AttemptStats` export (`06` §2) plus its
own aggregation of classified chat queries. Cache tags these surfaces subscribe to are declared
in `06` §4.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `AIH-BE-001` | Schema: migrations 1–4 + sqlc generate + trgm extension | CHECKs per §1.1; every query tenant-scoped | — | — |
| `AIH-BE-002` | `ai.Adapter` — DeepSeek HTTP client behind `AIService` | Model IDs from config; timeouts 30 s (vision) / 60 s (gen); retry ×2 + exp backoff; `response_format` JSON; output validated against versioned JSON schemas; 1 repair attempt on validation failure; prompt registry (code constants + `prompt_version` logged per call) | — | slog: feature, model, tokens, cost, prompt_version (no content) |
| `AIH-BE-003` | `aiquota.Reserve(userID, feature) / Refund(userID, feature)` | Conditional ledger upsert (`count < limit` in UPDATE … WHERE) — atomic last-slot race (INV-2); plan-aware limits (Pro = ∞ via 03 `users.PlanOf` (`users.plan`, expiry-aware)); refund decrements on terminal job failure | `ai:usage:{userId}` | No |
| `AIH-BE-004` | `aiusage.QuotaState(userID)` | Per-feature used/limit/week_start + plan; source for `GET /ai/usage` and app quota chips | read-through `ai:usage:{userId}` TTL 30 s | No |
| `AIH-BE-005` | `notes.CreateScan(owner, imageAssetID)` | Verified; asset confirmed + owned (INV-3); `shared=false` default (BR-006); quota reserve; `jobs.Enqueue("ai-scan-tagging")` | `ai:tags:school:{id}` | No |
| `AIH-BE-006` | `notes.ListScans / GetScan / SearchScans / SetShare / DeleteScan` | Visibility matrix (INV-1); search = pg_trgm(summary) ∧ normalized-tag filter ∧ scope; share/delete owner-only + `audit.Record` | `ai:tags:school:{id}` | Yes (share/delete) |
| `AIH-BE-007` | `aijobs.HandleScanTagging(payload)` | Re-check quota at job start (BR-002); breaker check; `ai.TagNoteImage`; schema-validate; persist tags (upsert) + summary; PROCESSING→READY; push via 06; failure path: retry → dead-letter → FAILED + `aiquota.Refund` | `ai:tags:school:{id}` | slog ledger |
| `AIH-BE-008` | `tests.Create(creator, in)` | Role-kind match; teacher section guard (04); student quota reserve; `status=generating`; `jobs.Enqueue("ai-mcq-generation")`; class_test creation audited | — | Yes (class_test) |
| `AIH-BE-009` | `aijobs.HandleMCQGeneration(payload)` | Re-check quota; breaker check; `ai.GenerateMCQs`; schema-validate (4 options, 1 correct, explanations); insert `ai_test_questions` batch; GENERATING→READY; failure → FAILED + refund | — | slog ledger |
| `AIH-BE-010` | `tests.Publish / Close / List / Get` | Publish: creator + class_test + `ready` → snapshot freeze (INV-4) + 06 push to section; Close: creator, refuses new attempts; Get: DTO mapper **key gate** (INV-5) — teacher/creator see key, students pre-grade never | — | Yes (publish/close) |
| `AIH-BE-011` | `attempts.Start / SaveAnswer / Submit` | Start: section member + published/ready + no prior attempt; SaveAnswer: in_progress + own + question-of-test (upsert); Submit: transactional deterministic grade (chosen vs `correct_index`), score, `graded`, duplicate → `CONFLICT`; result releases key | — | No |
| `AIH-BE-012` | `aicost.Guard / SetBannerState` | Daily ledger cost sum vs configured cap (BR-012); Redis flag `ai:breaker:state` (open/closed + reason); generation paths consult before call; auto-reset at Asia/Dhaka midnight | `ai:breaker:state` | Yes (trip/reset) |
| `AIH-BE-013` | `reports.CostReport(month, actor)` | Super Admin: all tenants; School Admin: own; returns per-feature totals, active users, per-tenant split — the module-07 stub (US-010) | — | No |
| `AIH-BE-014` | `ai.AttemptStats(sectionID, from, to)` + `ai.ClassifyChatQueries` wrapper | Aggregates for 09 (attempts, avg, per-question miss %); classify = adapter call with `feature=classify` ledger write, no user quota (system-initiated) | — | slog ledger |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `AIH-BE-015` | `InsertScan / GetScan / ListScansForOwner / ListSharedScans / SearchScans / SetShare / DeleteScan` | All WHERE `school_id=$caller` ∧ visibility; search: `summary % $q` + tag EXISTS ∧ scope | `(owner_id, status, created_at DESC)` · partial `(school_id) WHERE shared` · GIN trgm |
| `AIH-BE-016` | `InsertTags(batch) / TagsByScan / DistinctTagsBySchool(scope)` | Batch INSERT … ON CONFLICT DO NOTHING; distinct normalized within visibility | `(scan_id)` · `(normalized, level)` |
| `AIH-BE-017` | `InsertTest / GetTest / ListTestsByCreator / ListSectionTests / UpdateTestStatus` | Status transitions guarded in UPDATE … WHERE status | `(creator_id, status, created_at DESC)` · `(section_id, status, published_at DESC)` |
| `AIH-BE-018` | `InsertQuestions(batch) / QuestionsByTest` | Ordered batch insert; render ORDER BY ord | `(test_id, ord)` |
| `AIH-BE-019` | `InsertAttempt / GetAttempt / UpdateAttemptStatus / ListAttemptsByTest` | UNIQUE (test, student); status-guarded transitions | `(test_id, status)` · `(student_id, status)` |
| `AIH-BE-020` | `UpsertAnswer / ListAnswersByAttempt / GradeSubmit` | GradeSubmit: one UPDATE … FROM join on questions setting `correct` + score + status (transactional) | UNIQUE `(attempt_id, question_id)` · `(question_id)` |
| `AIH-BE-021` | `ReserveQuota / RefundQuota / SumDailyCost / CostReportAggregates` | Reserve: `INSERT … ON CONFLICT (user_id, feature, week_start) DO UPDATE SET count = count+1 … WHERE ai_usage_ledger.count < $limit` | UNIQUE quota key · `(updated_at)` · `(week_start)` |
| `AIH-BE-022` | `AttemptStatsBySection(sectionID, from, to)` | Aggregates: attempts, avg score, per-question miss counts + per-topic (test subject/chapter/topic) answered/failed joined via attempts | `(test_id, status)` · `(question_id)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `AIH-BE-023` | `ai-scan-tagging` — TagNoteImage → validate → persist tags/summary → READY → 06 push | `jobs.Enqueue` from `POST /ai/notes` (module 01 runner) | Yes — status-guarded (only PROCESSING rows transition) | Retry ×2 + backoff at adapter; job-level retries per 01; dead-letter → FAILED + `aiquota.Refund` + user copy |
| `AIH-BE-024` | `ai-mcq-generation` — GenerateMCQs → validate → insert questions → READY | `jobs.Enqueue` from `POST /ai/tests` | Yes — GENERATING-guarded | Same retry ladder; malformed → 1 repair attempt → dead-letter → FAILED + refund |
| `AIH-BE-025` | `ai-quota-refund` — compensating decrement on dead-lettered AI jobs | Dead-letter hook (module 01) | Yes — refund applies once per job id (job payload carries reservation ref) | Log + alert if refund fails (quota is re-checked at any retry anyway) |
| `AIH-BE-026` | `ai-daily-cost-guard` — evaluate ledger daily sum → set/clear `ai:breaker:state`; ops alert at 80%/100% | Every 5 min + at Asia/Dhaka midnight reset | Yes — flag is declarative state | Missed runs self-heal next tick; generation paths also compute inline as backstop |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `AIH-UT-001` | `aiquota.Reserve` race: two reserves at count=4/limit=5 → exactly one succeeds | Unit (in-memory ledger fake) | INV-2 / BR-002 |
| `AIH-UT-002` | Auto-grade scorer: chosen vs correct join → score, per-answer correctness; unanswered = incorrect | Unit | BR-010 / INV-6 |
| `AIH-UT-003` | Output validation: malformed MCQ JSON → repair prompt once → valid; malformed twice → job-fail error | Unit | BR-014 / INV-8 |
| `AIH-UT-004` | Prompt registry: template constant + version logged; locale param selects bn/en template | Unit | BR-014/015 |
| `AIH-UT-005` | DTO key gate: student pre-grade payload has no `correct_index`/`explanation`; post-grade + teacher payloads do | Unit | INV-5 / BR-009 |
| `AIH-UT-006` | Search filter builder: q + multi-tag ∧ + scope=mine/shared composes the expected SQL shape | Unit | US-002 |
| `AIH-IT-001` | Quota enforcement (testcontainers Postgres): 5th practice gen allowed, 6th → `QUOTA_EXCEEDED`; Pro flag → unlimited | Integration | BR-002/003 |
| `AIH-IT-002` | Cross-tenant archive/test/attempt access → `TENANT_MISMATCH`/404, no leak | Integration | BR-007 / INV-1 |
| `AIH-IT-003` | Unverified user blocked with `NOT_VERIFIED` on every `/ai` route | Integration | BR-001 |
| `AIH-IT-004` | Scan job end-to-end: enqueue → adapter stub returns valid NoteTags → tags+summary persisted → READY → 06 push called | Integration | US-001 |
| `AIH-IT-005` | Malformed-output retry: stub malformed-once → repair succeeds; stub always-malformed → FAILED + quota refunded | Integration | BR-014 / AIH-BE-025 |
| `AIH-IT-006` | Attempt lifecycle: start → answers upsert (latest wins) → submit grades once → result includes key → duplicate submit `CONFLICT` | Integration | US-006/007 / INV-6 |
| `AIH-IT-007` | Ledger written per call: tokens/cost/model/count increment for scan, mcq_gen, classify | Integration | BR-011 / INV-7 |
| `AIH-IT-008` | Publish flow: teacher publishes → section student sees test; other-section/other-school student does not; key hidden pre-submit | Integration | US-004 / INV-4/5 |
| `AIH-IT-009` | Unauthenticated call → `UNAUTHENTICATED` on all 16 endpoints | Integration | Auth chain |
| `AIH-IT-010` | Breaker: daily sum ≥ cap → generation refused with queued-job state + banner flag set; resumes after reset | Integration | BR-012 |
| `AIH-IT-011` | Share flow: unshared scan invisible in school search; shared visible same-school; unshare removes immediately | Integration | BR-006/007 |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
publish guard blocks `TODO:`; public reads never return drafts.

## 7. Task Checklist

### Schema

- [ ] `AIH-BE-001` migrations 1–4 (scans/tags, tests/questions, attempts/answers, ledger) + sqlc + pg_trgm extension

### Repository · Service · Entry points · Seed · Tests

- [ ] `AIH-BE-015`–`AIH-BE-022` sqlc queries + tenant-scoped repositories
- [ ] `AIH-BE-002` `AIService` interface + DeepSeek adapter (timeouts, retry, schema validation, prompt registry)
- [ ] `AIH-BE-003`/`AIH-BE-004` quota reserve/refund + usage state services
- [ ] `AIH-BE-005`/`AIH-BE-006` notes services (create, list, search, share, delete)
- [ ] `AIH-BE-007`/`AIH-BE-009` job handlers (scan-tagging, mcq-generation)
- [ ] `AIH-BE-008`/`AIH-BE-010` tests services (create, publish/close/list/get with key gate)
- [ ] `AIH-BE-011` attempts services (start, save answer, auto-grade submit)
- [ ] `AIH-BE-012` cost guard + breaker flag; `AIH-BE-026` guard job
- [ ] `AIH-BE-013` cost-report service + endpoint #16; `AIH-BE-014` AttemptStats + classify exports
- [ ] `AIH-BE-023`/`AIH-BE-025` jobs registered with module-01 runner (tagging, generation, refund hook)
- [ ] OpenAPI paths #1–#16 in `applications/api/openapi/` (+ regenerated Go/TS contract code)
- [ ] Seed: Demo High School AI dataset (fictional, marked)
- [ ] Tests: `AIH-UT-001`–`006`, `AIH-IT-001`–`011` green in CI
