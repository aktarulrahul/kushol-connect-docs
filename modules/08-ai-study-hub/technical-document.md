# AI Study Hub — Technical Document

**Module:** `08-ai-study-hub` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Compressed from this folder's spec set — `01-user-stories.md` · `02-solution-approach.md` · `03-backend-tasks.md` · `04-frontend-tasks.md` · `05-app-tasks.md` · `06-integration-tasks.md`. On any drift, the spec files win.

---

## 1. Overview

### 1.1 Purpose

Provides the DeepSeek-powered study layer: the **Notes Scanner** (handwritten notes vision-tagged into a private-by-default, searchable archive — `AIH-US-001/002`), the **Smart Study Hub** (archive browsing + search), and **Auto-CT** (AI-generated MCQ practice for students, class tests for teachers, deterministic auto-grading — `AIH-US-003–007`). Everything runs behind per-user weekly quotas (5 free Auto-CTs/week; Kushol Pro unlimited — `brd.md` §7) with per-call cost accounting to `ai_usage_ledger` (BR-02, `brd.md` §5; `prd.md` §5.2). All AI calls go through one Go `AIService` interface — DeepSeek direct first, FastAPI later — so clients never change.

### 1.2 Scope

**In:** `AIService` Go interface + DeepSeek adapter (vision tagging, MCQ generation, chat-query classification) with versioned prompt templates and JSON-schema-validated output; server-side weekly quotas enforced before enqueue **and** at job start, plan-aware; Notes Scanner from 05-confirmed media; archive search (pg_trgm + tag filters, own + school-shared); Auto-CT generation/publish/take/auto-grade; cost discipline — ledger per model call, daily cost circuit breaker, admin cost-report stub.

**Out:** Pain Point Matrix dashboards (module 09 consumes `ClassifyChatQueries`/`QuotaState`/`AttemptStats`); Kushol Pro purchase/billing (module 12; Pro flag is plan data from 03); web dashboards/cards (07 renders cost cards — this module ships data endpoints only); chat message writes/reads (05; classification runs over samples 09 supplies); editable scan text/OCR-correction UI, test timers beyond a P2 option, PDF export of tests.

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations | `jobs.Enqueue`/worker (all AI calls async), `audit.Record`, RFC-7807 envelope, rate-limiter base, dead-letter hook |
| consumes | 02 design-system | bn/en catalogs (`ai.*`, `validation.ai.*`), tokens, RN primitives |
| consumes | 03 identity-access | `auth.RequireVerified` (AI is verified-only), user locale + plan flag (fail-closed to free limits) |
| consumes | 04 organization-hierarchy | `hierarchy.ResolveUserNodes` — teach-sections (class tests) + school scope (archive) |
| consumes | 05 communication-engine | `media.PresignUpload`/`ConfirmUpload` — scan images ride 05's R2 upload service |
| consumes | 06 notifications | Push on `scan_ready` + `class_test` (ids + type only, deep links) |
| consumed by | 09 teacher-analytics · 07 command-center-web | 09: `ai.ClassifyChatQueries`, `ai.QuotaState`, `ai.AttemptStats` · 07: `GET /api/v1/ai/admin/cost-report` (role-gated) + `ai.QuotaState` for cost context |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| API language/framework | Go · chi REST handlers generated from OpenAPI 3.1 | one deployable on the shared 2-vCPU VPS (`02` §10 Option A) | `tech-stack.md` api table |
| AI seam | `AIService` Go interface + DeepSeek adapter (stdlib `net/http`); `applications/ai` FastAPI later behind the same interface | interface frozen now so the swap is infra-only (`tech-stack.md` AI row) | DeepSeek: vision + chat, `response_format` JSON, Flash-class models, IDs in config; FastAPI internal HTTP only, never client-exposed |
| Data access | sqlc + pgx · PostgreSQL (Neon) | 7 owned tables, tenant-scoped, trgm GIN search | testcontainers-go for IT |
| Queueing / cache | 01 in-DB job table + Go worker · Redis (go-redis) | async-by-default with retry/dead-letter/refund for free; quota memo, tag facets, breaker flag | no Kafka/RabbitMQ; TTLs per `06` §4 |
| Mobile (app surfaces) | Expo SDK · expo-router · React Native · NativeWind · TanStack Query · zustand · RHF + zod | 360px-first student/teacher screens (`05-app-tasks.md`) | no new app dependencies |
| Web | N/A — no web frontend in this module | dashboards belong to 07 (cost cards) and 09 (matrix) | contract handoff only (`AIH-FE-001/002`) |

---

## 3. Architecture

### 3.1 Component diagram

```text
App (Expo, /ai-hub*) ──▶ chi REST /api/v1/ai/* (authenticate → role claims → tenant-scope → RequireVerified)
   │ scan image via 05: presign → R2 PUT → confirm     │ notes · tests · attempts · usage · cost-report services
   │                                                   ├─▶ aiquota.Reserve (conditional ledger upsert) · aicost.Guard
   │                                                   └─▶ jobs.Enqueue (01 worker): ai-scan-tagging · ai-mcq-generation
   │                                                              └─▶ AIService (Go interface, frozen seam)
   │                       DeepSeek adapter (HTTPS, DEEPSEEK_API_KEY, 30 s/60 s, retry ×2) [later: FastAPI adapter]
   │                              → versioned JSON-schema validation → 1 repair attempt → persist → READY
   └──◀ 06 push (scan_ready / class_test) ────────────┘ every adapter call → ai_usage_ledger upsert
aicost.Guard: daily ledger sum vs cap → Redis ai:breaker:state → generation queues, banner shown
09 consumes: ai.AttemptStats · ai.ClassifyChatQueries · ai.QuotaState   07 consumes: GET /ai/admin/cost-report
```

### 3.2 Boundary

**Owns (tables / services):** `note_scans`, `note_tags`, `ai_tests`, `ai_test_questions`, `ai_test_attempts`, `ai_test_answers`, `ai_usage_ledger` — plus the `AIService` interface, the versioned prompt registry, and the JSON contract schemas for model output.

**Reads (via exported service functions only):** 05 — `media.PresignUpload`/`ConfirmUpload` (never sniffs files itself); 03 — verification gate, locale + plan flag; 04 — `hierarchy.ResolveUserNodes`; 01 — `jobs.Enqueue`/worker, `audit.Record`, error envelope, rate limiter; 06 — push dispatch. Cache tags: `ai:usage:{userId}`, `ai:tags:school:{id}`, `ai:breaker:state` (`06` §4).

### 3.3 Request / data flows

```text
1. Scan (async-by-default): capture → compress ~1 MB → 05 presign → R2 PUT → confirm →
   POST /ai/notes (verified, asset re-checked, quota reserved) → PROCESSING → ai-scan-tagging job →
   ai.TagNoteImage → schema-validate (1 repair) → persist → READY → 06 push; terminal failure →
   dead-letter → FAILED + aiquota.Refund. Enqueue round-trip < 200 ms; client polls 3 s.
2. Generation: POST /ai/tests (role-kind match; teacher section via 04; student quota) →
   ai-mcq-generation job → ai.GenerateMCQs → validate (4 options, 1 correct, explanations) →
   questions inserted → READY; publish freezes questions_snapshot (INV-4) → 06 push to section.
3. Attempt: POST attempts (unique per test+student) → answers upsert while in_progress → submit:
   transactional deterministic grade (chosen vs correct_index — never a model call) → GRADED →
   answer key released (INV-5); duplicate submit → CONFLICT.
4. Cost: every model call (scan|mcq_gen|classify) → ledger upsert count/tokens/cost/model →
   ai-daily-cost-guard sums per day → breaker flag at cap → new jobs queue (not start) behind
   the "AI paused" banner → auto-reset at Asia/Dhaka midnight. Classification (for 09):
   ai.ClassifyChatQueries over 09's samples → TopicTags → ledger `classify`, no user quota.
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `note_scans.status` | processing · ready · failed | — → processing (verified + owner-asset + quota reserved); processing → ready (job ok, quota re-checked); processing → failed (terminal: retries + repair exhausted → dead-letter → quota refunded); failed → processing (user retry) |
| `ai_tests.status` | generating · ready · published · closed | — → generating (role-kind match); generating → ready (schema-valid questions); ready → published (creator, class_test — snapshot frozen); published → closed (creator; new attempts refused `CONFLICT`); terminal generation failure → job FAILED + quota refunded, regenerate = new test (`02` §3) |
| `ai_test_attempts.status` | in_progress · submitted · graded | — → in_progress (section member, no prior attempt); in_progress → submitted → graded (submit, one tx, deterministic); answers writable only while in_progress; submit terminal |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `note_scans` | One scanned note: owner, image ref (05 asset), status, summary as returned, `shared` flag | `school_id` on every row; visibility = owner ∨ (shared ∧ same school) (INV-1) | `(owner_id, status, created_at DESC)` · partial `(school_id) WHERE shared` · GIN trgm `(summary)` · `(image_asset_id)` | `shared` default **false** (BR-006); `locale` drives AI language; `error_code` feeds retry UX |
| `note_tags` | Vision tags per scan: `level ∈ subject\|chapter\|topic` | via owning scan | `(normalized, level)` · `(scan_id)` | UNIQUE `(scan_id, level, normalized)`; `normalized` = NFC/trim/lowercase search key |
| `ai_tests` | Generated MCQ test: kind, scope, status, `questions_snapshot` | `school_id`; class_test also section-scoped | `(creator_id, status, created_at DESC)` · `(section_id, status, published_at DESC)` · `(school_id, kind, status)` | `section_id` NOT NULL iff `kind='class_test'`; published/closed ⇒ snapshot NOT NULL (INV-4) |
| `ai_test_questions` | Normalized working copy: ord, stem, 4 options, `correct_index`, explanation | via owning test | UNIQUE `(test_id, ord)` | `correct_index` never serialized to students pre-grade (INV-5) |
| `ai_test_attempts` | A student's sitting: status, score | `school_id` = student's school | UNIQUE `(test_id, student_id)` · `(test_id, status)` · `(student_id, status)` | one attempt per test+student (INV-6); test must be published/ready and not closed |
| `ai_test_answers` | Per-question choice: `chosen_index`, `correct` computed at submit | via owning attempt | UNIQUE `(attempt_id, question_id)` · `(attempt_id)` · `(question_id)` | latest choice wins (upsert); `(question_id)` powers per-question miss stats |
| `ai_usage_ledger` | Quota + cost ledger per (user, feature ∈ scan\|mcq_gen\|classify, week_start) | row-level user guard; admin path role-guarded | UNIQUE `(user_id, feature, week_start)` · `(updated_at)` daily cost sum · `(week_start)` | quota reservation = conditional upsert `WHERE count < limit` (INV-2); `cost_usd` powers breaker + report |

Migrations 1–4 in `03` §1.2; "Demo High School" fictional seed (`03` §1.3), never seeded into real tenants.

---

## 5. Contracts

### 5.1 REST endpoints

Auth chain on every route: authenticate → load role claims → tenant-scope → `auth.RequireVerified`. Rate-limit class `ai` on #1/#3/#7/#12/#13. Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` · `NOT_FOUND` · `NOT_VERIFIED` · `QUOTA_EXCEEDED` · `RATE_LIMITED` · `CONFLICT` · `INTERNAL` (RFC-7807 `application/problem+json`).

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST · `/api/v1/ai/notes` | Verified student | Create scan from confirmed 05 asset → reserve quota → enqueue tagging job | `QUOTA_EXCEEDED` · `VALIDATION_FAILED` · `RATE_LIMITED` | AIH-US-001 |
| 2 | GET · `/api/v1/ai/notes?scope=mine\|shared&status=&cursor=` | Verified | My archive / shared-in-school list, 20/page | — | AIH-US-001/002 |
| 3 | GET · `/api/v1/ai/notes/search?q=&tags=&scope=` | Verified | pg_trgm text + tag-chip search (visibility matrix) | `RATE_LIMITED` | AIH-US-002 |
| 4–6 | GET · PATCH · DELETE · `/api/v1/ai/notes/{id}` (`…/share`) | Verified (visibility); owner for share/delete | Scan detail — tags, summary, image URL · share toggle · delete (both audited) | `TENANT_MISMATCH`/404 · `FORBIDDEN` | AIH-US-001 |
| 7 | POST · `/api/v1/ai/tests` | Student / Teacher | Practice gen / class-test gen (role must match kind) → enqueue MCQ job | `QUOTA_EXCEEDED` · `VALIDATION_FAILED` · `FORBIDDEN` | AIH-US-003/005 |
| 8 | GET · `/api/v1/ai/tests?role=created\|taken\|section` | Verified | My created / taken / my-section lists | — | AIH-US-004/005/006 |
| 9 | GET · `/api/v1/ai/tests/{id}` | Verified | Test detail — **key-gated** (INV-5); teacher gets key | `TENANT_MISMATCH`/404 | AIH-US-003/006 |
| 10–11 | POST · `/api/v1/ai/tests/{id}/publish` · `…/close` | Teacher (creator) | Publish — snapshot freeze + section push · close — new attempts refused | `FORBIDDEN` · `CONFLICT` | AIH-US-004 |
| 12–14 | POST · `/api/v1/ai/tests/{id}/attempts` · `/api/v1/ai/attempts/{id}/answers` · `…/submit` | Verified student · attempt owner | Start attempt (unique per test+student) · answer upsert (in_progress, latest wins) · deterministic auto-grade → score + result with key | `CONFLICT` · `VALIDATION_FAILED` | AIH-US-006/007 |
| 15 | GET · `/api/v1/ai/usage` | Verified | Own quota state per feature (used/limit/week_start/plan) | — | AIH-US-008 |
| 16 | GET · `/api/v1/ai/admin/cost-report?month=YYYY-MM` | Super Admin / School Admin (own tenant) | Per-feature totals, active users, per-tenant split | `FORBIDDEN` | AIH-US-010 |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `ai-scan-tagging` (`AIH-BE-023`) | Enqueue from `POST /ai/notes` | `TagNoteImage` → validate → persist tags/summary → READY → 06 push | scan owner | Status-guarded (only PROCESSING); adapter retry ×2 + job retries per 01; dead-letter → FAILED + refund |
| `ai-mcq-generation` (`AIH-BE-024`) | Enqueue from `POST /ai/tests` | `GenerateMCQs` → validate → insert questions → READY | creator (teacher preview gets key) | Same ladder; malformed → 1 repair attempt → dead-letter → FAILED + refund |
| `ai-quota-refund` (`AIH-BE-025`) · `ai-daily-cost-guard` (`AIH-BE-026`) | Dead-letter hook (01) · every 5 min + Asia/Dhaka midnight reset | Compensating quota decrement, once per job id · ledger daily sum → set/clear `ai:breaker:state`, ops alert at 80%/100% | quota ledger · generation paths | Log + alert if refund fails (quota re-checked at retries); missed runs self-heal next tick + inline backstop |
| Push (via 06) | scan READY / test PUBLISHED | `scan_ready` / `class_test` — ids + type, deep links | app | Poll + list refetch reveal state; 06 owns delivery retry |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `ai.GenerateMCQs(ctx, scope ChapterScope, count int, locale string)` | internal (mcq-generation job) | `[]MCQ` (schema-validated: stem, 4 options, correct_index 0..3, explanation) | `ErrAIUnavailable` · `ErrMalformedOutput` (after 1 repair) |
| `ai.TagNoteImage(ctx, imageRef ImageRef, locale string)` | internal (scan-tagging job) | `NoteTags{summary, tags[]{level, value, normalized}}` | same — image must be a 05-confirmed asset |
| `ai.ClassifyChatQueries(ctx, samples []ChatQuerySample, locale string)` | 09 | `TopicTags{topics[]{value, normalized, confidence}}` | same — aggregates only; 09 must not persist chat text; ledger `classify`, no user quota |
| `ai.QuotaState(userID uuid.UUID)` | 09 (matrix context), 07 (cost context) | `QuotaStateDTO{plan, features[]{feature, used, limit, week_start}}` | `NOT_FOUND` — DTO only, never ledger rows |
| `ai.AttemptStats(sectionID uuid.UUID, from, to time.Time)` | 09 | `AttemptStatsDTO{attempts, avg_score, per_question[]{question_id, miss_count, miss_pct}, per_topic[]{subject, chapter, topic, answered, failed, fail_rate}}` | `FORBIDDEN` (non-tenant section) — aggregate-only, no student identities |

AI output schemas are versioned separately (`AIContract v1`); prompt templates + versions are code constants logged per call; `questions_snapshot` embeds its contract version (`06` §7).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

N/A — the student/teacher AI surfaces are mobile-only by design; the Command Center has no AI screens in this module. Routes other modules implement against this module's APIs: `/admin/ai-cost` + `/school/ai-cost` (07, from endpoint #16) and `/school/ai-matrix` (09, from the Go exports); handoff tasks `AIH-FE-001/002` keep the DTOs aligned.

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/ai-hub` | AI Hub home — নোট স্ক্যানার · অটো-সিটি · স্টাডি ম্যাটেরিয়াল; `QuotaChip`, `ClassTestBanner`, `AIPausedBanner`, `VerifiedGate` | none (tab root) | cached cards; generation CTAs disabled (not hidden) |
| `/(tabs)/ai-hub/scan` | Scan flow — capture → preview → retake/confirm → progress | none | capture queued offline; confirm blocked with bn/en message |
| `/ai-hub/scan/[id]` | Scan detail — tag chips, AI-generated summary block, share toggle (default OFF), delete | push `type=scan_ready` | cached read; image placeholder keeps tags/summary |
| `/(tabs)/ai-hub/archive` | Archive browser — search bar, scope tabs, tag chips (AND, ≤10), 20/page | push `type=scan_ready` (list) | cached list read-only; search disabled (needs server pg_trgm) |
| `/(tabs)/ai-hub/tests` | Test list — practice/class sections, status badges, scores, quota chip | push `type=class_test` | cached; generating rows poll |
| `/ai-hub/tests/[id]` | Test-taking pager — option tap upsert, resume, submit confirm with unanswered warning | push `type=class_test` | **blocked** with clear message; local selections kept, replay on reconnect |
| `/ai-hub/tests/[id]/result` | Result — animated score ring, per-question ✓/✗ + explanation; teacher stats view | in-app navigation | cached result offline-readable |
| `/(modals)/quota-exhausted` | Quota exhausted + Kushol Pro upsell ("coming soon" CTA until module 12) | `QUOTA_EXCEEDED` response | N/A — modal on response; browsing/taking still work |

360px-first, bn-first copy, bn numerals via `Intl`; reduced-motion variants for shimmer/score ring/chips (`05` §5).

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| DeepSeek API (vision + chat) | scan tagging, MCQ generation, chat-query classification | HTTPS JSON (`response_format` json) | `DEEPSEEK_API_KEY` (envconfig-parsed, server-only) | 30 s vision / 60 s generation · adapter retry ×2 exp backoff + 01 job retries | Jobs queue; "এআই সাময়িকভাবে বন্ধ / AI is paused" banner when the breaker trips; quota refunded on terminal failure |
| Daily cost circuit breaker | Platform-wide spend cap | Redis flag + ledger sum | internal | 200 ms · inline backstop compute | Generation paused at cap (`TODO: Confirm`, default USD 10/day); auto-reset Asia/Dhaka midnight |
| `applications/ai` FastAPI (later) | Adapter swap behind the frozen `AIService` | Internal HTTP (Compose network, no public ingress) | `AI_INTERNAL_TOKEN` | 35 s / 65 s · same retry ladder | Identical to DeepSeek-down — the interface hides the swap (`AI_PROVIDER` switch) |
| FCM (via 06 only) · R2 (via 05 only) | Push on scan-ready / test-published · scan image storage | 06-owned Admin SDK · 05-owned S3 API | 06's `FCM_SERVER_KEY` · 05's `R2_*` | 06/05-owned | Push lost → polling + lists reveal state; image 404 → placeholder, tags/summary intact |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `DEEPSEEK_API_KEY` | Yes | secret (envconfig-parsed) | DeepSeek adapter — server-only; model IDs per task (vision/chat) live in config, not code (OQ-1, Flash-class cheapest) |
| `AI_PROVIDER` | No | `deepseek-go` | adapter switch: `deepseek-go` today, `fastapi` when `applications/ai` lands |
| `AI_INTERNAL_TOKEN` | No (later) | internal shared token | FastAPI adapter auth over the Compose network |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Weekly quotas per feature/plan (free: scans 5, mcq_gen 5 — `TODO: Confirm`; Pro: ∞) | Async-only generation (all model calls are 01 jobs) |
| Teacher class-test cap (default 20/week — `TODO: Confirm`) | Schema-validation gate before persistence + 1-repair-retry rule (INV-8) |
| Daily platform cost cap for the breaker (`TODO: Confirm`, default USD 10) | Answer-key gating on student DTOs (INV-5) |
| DeepSeek model IDs per task + `AI_PROVIDER` switch; adapter timeouts (30 s / 60 s), retry ×2 + backoff; "AI paused" banner copy overrides (bn/en) | Tenant scoping + share-default-off (safety invariants) |
| MCQ defaults: count 10 (range 5–30), 4 options | Deterministic rule-based grading (never a model call); week boundary Monday 00:00 Asia/Dhaka; breaker day boundary Asia/Dhaka; prompt registry = code constants with version fields, logged per call |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope → `auth.RequireVerified` on every `/ai` route (verified-only, BR-001); no public/unauthenticated surface exists |
| Role matrix | Student: own scans, archive own+shared, practice generation/taking. Teacher: class tests for own sections only, shared archive read-only, result aggregates of own tests. School Admin: cost report own tenant. Super Admin: platform cost report. Guardian/Vendor: none — a minor's scans are never exposed to guardians |
| Tenant scope | Every query `school_id = caller` ∧ visibility matrix (INV-1): scan iff owner or shared-same-school; class test iff creator or section member; attempt iff its student; jobs re-run the same repository guards; cross-tenant → `TENANT_MISMATCH`/404 |
| Rate limits | Class `ai` on generation/search/answer routes (BR-012) on top of quotas (BR-002/003); plan read failure → fail-closed free limits |
| Audit events | `audit.Record` on share/delete scan, class_test creation, publish/close test, breaker trip/reset; benign creates unaudited |
| Privacy / minors | Scans PRIVATE by default; school visibility only via explicit per-scan toggle (BR-006, OQ-5 safety decision); answer key never serialized pre-grade (INV-5); no note content, summary or stems in logs — slog carries ids, feature, model, token counts, prompt_version; model output treated as untrusted data, persisted only after schema validation (prompt-injection posture) |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `QUOTA_EXCEEDED` | Weekly per-feature quota spent | `POST /ai/notes` · `POST /ai/tests` (free plan) | Dedicated bn+en screen/modal: reset day + Pro card "৯৯৳/মাস" with "coming soon" CTA (module 12 unshipped); browsing/taking keep working |
| `NOT_VERIFIED` | Unverified (pending) user on any AI action | Every `/ai` route | Gate with how-to-get-verified guidance (module 03 copy) |
| `CONFLICT` | Duplicate submit / answer after submit / closed test / double decision | Attempts + publish/close endpoints | Original result returned unchanged; "টেস্টটি বন্ধ / This test is closed" copy |
| `RATE_LIMITED` | Class-`ai` flood | Create/search/answer routes | Polite retry copy |
| `TENANT_MISMATCH` (404 body) | Cross-tenant read | Scans/tests/attempts of another school | Nothing leaks (`AIH-IT-002`) |
| `VALIDATION_FAILED` | Malformed input incl. unconfirmed/foreign media asset, kind/role mismatch, foreign section | All routes | Per-field `validation.ai.*` keys bn/en; input preserved |
| `ErrMalformedOutput` (internal) | Model output fails schema validation twice | Inside jobs → entity FAILED | Honest "failed + quota refunded" copy with retry — never a junk archive row or dead end |

All errors surface as RFC-7807 `application/problem+json`; messages resolve via `packages/shared` (`ai.*`, `validation.ai.*`) — **bn + en** from day one (bn default).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog: feature, model, tokens, cost, prompt_version — never prompt/response content; adapter errors with request ids |
| Metrics / counters | `ai_usage_ledger` is the cost source of truth (count/tokens/cost_usd/model per user×feature×week) → cost per active user for 07; breaker flag state; ops alerts at 80%/100% of the daily cap |
| Health contribution | None module-specific — `/healthz` is 01's; job-runner liveness matters: jobs are DB-persisted, runner restart resumes |
| Jobs & retries | `ai-scan-tagging` · `ai-mcq-generation` (status-guarded, idempotent) → dead-letter → `ai-quota-refund` compensating decrement (once per job id); `ai-daily-cost-guard` every 5 min; quota refund never over-counts (DB-transactional) |
| Runbook pointers | Failure-matrix drills scripted in CI (`AIH-INT-011`: DeepSeek stub down, breaker trip, runner kill); DeepSeek-down = queue + honest "we'll notify you" copy, never fatal; Neon/Redis recovery per 01/15 runbooks |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Quota last-slot race, auto-grade scorer, output validation/repair ladder, prompt registry + locale, DTO key gate, search filter builder, adapter retry ladder, breaker guard | `AIH-UT-001–008` | go test |
| Integration | Quota enforcement + Pro flag + job-start re-check, cross-tenant, unverified block, scan job e2e, malformed retry + refund, attempt lifecycle + duplicate submit, ledger per call, publish visibility + key hiding, unauthenticated on all 16 routes, breaker trip/reset, share flow, 06 push seam, 09 export seam, FastAPI adapter contract | `AIH-IT-001–014` | testcontainers Postgres |
| E2E | Scan → upload → processing copy → tags ready (bn); generate practice → take → submit → graded result with explanations | `AIH-E2E-001–002` | Maestro |
| CI | — | — | `go test/vet/lint`; drills `AIH-INT-011` in CI smoke; mandatory: unauthenticated denied, validation rejects bad input, cross-tenant `TENANT_MISMATCH`/404, publish guard blocks `TODO:`, public reads never return drafts |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot: ~3 schools × ~2,000 users; ~5% daily AI actives (~300) × ~2 calls/day ≈ 600 model calls/day peak — Flash-class cost stays inside the breaker cap |
| Hot paths + indexes | Quota conditional upsert on the UNIQUE key (no read-modify-write); trgm GIN archive search; `(question_id)` answer index for stats; single-statement ledger writes |
| Latency targets | API round-trip (enqueue) < 200 ms; **scan p95 < 60 s async** (upload ~2 s + queue < 5 s + vision); **MCQ generation p95 < 30 s**; auto-grade p95 < 200 ms (pure SQL, zero model calls); archive search p95 < 300 ms |
| Bundle / payload impact | No new app dependencies — `expo-camera`/`expo-image-picker` are already the 05 media stack; api adds only the stdlib `net/http` DeepSeek adapter |
| Caching | Quota memo `ai:usage:{userId}` TTL 30 s; tag-chip facet `ai:tags:school:{id}` Redis TTL 300 s; breaker flag TTL = rest of day; **no result cache v1** for identical regenerates (rejected alternative — immutability + quota semantics) |

---

## 14. Risks & Open Questions

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Exact DeepSeek model IDs, cheapest Flash-class vision + chat (OQ-1); Flash vision must read Bangla handwriting well enough (`02` §11 risk 1) | Cost/quality trade-off; junk tags erode trust | Rahul | Open — `TODO: Confirm` | Flash-class cheapest, IDs in config so upgrades are instant; tags advisory + deletable; honest failed/empty states |
| 2 | Free weekly scan quota, proposed 5/week (OQ-2) | Freemium balance | Rahul | Open — `TODO: Confirm` | 5 scans/week free; Pro unlimited |
| 3 | Teacher class-test cap, proposed 20/week (OQ-3) | Teacher adoption | Rahul | Open — `TODO: Confirm` | 20/week per teacher |
| 4 | Daily platform AI cost cap for the breaker (OQ-4); model cost must stay in Flash-class budget (`02` §11 risk 2) | Outage vs overrun; breaker trips often | Rahul | Open — `TODO: Confirm` | USD 10/day platform-wide, Asia/Dhaka boundary; per-user quotas + configurable cap; ledger makes overruns visible daily |
| 5 | Scans default share-OFF for minors' safety (OQ-5) slows the archive network effect (`02` §11 risk 6) | Slower archive growth | Rahul | Open — `TODO: Confirm` (safety) | Private by default; per-scan opt-in share; defaults change only with explicit sign-off |
| 6 | MCQ defaults: 10 questions (5–30), 4 options (OQ-6) | Test quality | Rahul | Open — `TODO: Confirm` | 10 questions, 4 options, explanations required |
| 7 | How users obtain the Pro flag before module 12 (OQ-7) | Pro gating correctness | Rahul | Open | Ops/Super Admin sets the plan flag (03 data) manually until 12 |
| 8 | Prompt-injection via photographed notes (`02` §11 risk 3) | Malicious instructions in images | Rahul | Mitigated | Schema-validated data only; no tool use; prompts fixed + versioned |
| 9 | Neon free tier absorbs job polling + ledger writes (`02` §11 risk 4) | Connection pressure | module 01 owner | Assumption | Conservative runner polling; single-statement upserts; upgrade path documented |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-02 — AI features with cost accounting | §5.2 | AIH-US-001–011 | AIH-BE-001–026 · AIH-INT-001–012 | AIH-UT-001–008 · AIH-IT-001–014 |
| `brd.md` §7 — freemium quota (5 free/wk; Pro unlimited) | §5.2 | AIH-US-005 · AIH-US-008 | AIH-BE-003/004 · AIH-AP-013 | AIH-UT-001 · AIH-IT-001 · AIH-IT-010 |
| PRD §5.2 — Notes Scanner / Smart Study Hub · Auto-CT (generate, administer, auto-grade) | §5.2 | AIH-US-001–007 | AIH-BE-005–011 · AIH-AP-001–012 | AIH-IT-004/006/008/011 · AIH-E2E-001/002 |
| Persona — cost discipline | §4A | AIH-US-009/010 | AIH-BE-012/013/023–026 · AIH-FE-001 | AIH-IT-005/007/010 |
| Module 09 feed (analytics exports) | §5.2 | AIH-US-011 | AIH-BE-014 · AIH-INT-007 · AIH-FE-002 | AIH-IT-013 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: `ai.AttemptStats(sectionID, from, to)` takes an explicit window and adds `per_topic` aggregates (09's Sun→Sat week is independent of the Monday quota week); Kushol Pro read via 03 `users.PlanOf` | Claude |
