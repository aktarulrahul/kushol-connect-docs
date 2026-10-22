# AI Study Hub — User Stories

**Module:** `08-ai-study-hub`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Provides the DeepSeek-powered study layer of Kushol Connect: the **Notes Scanner** (photos of handwritten notes are vision-tagged into a private-by-default, searchable archive), the **Smart Study Hub** (archive browsing + search), and **Auto-CT** (AI-generated MCQ practice tests for students, class tests for teachers, with in-app testing and deterministic auto-grading). Everything runs behind per-user quotas (5 free Auto-CTs/week; Kushol Pro unlimited — `brd.md` §7) with per-call cost accounting to `ai_usage_ledger` (BR-02, `brd.md` §5; `prd.md` §5.2). All AI calls go through one Go `AIService` interface — DeepSeek direct first, a Python FastAPI service later — so clients never change.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Sees the AI Hub tab but every action is gated with `NOT_VERIFIED` (module 03) |
| Student | Scans notes, browses/searches the archive (own + school-shared), generates practice Auto-CTs (quota'd), takes tests, gets auto-graded results |
| Guardian | N/A — guardians have no AI surface; a minor's scans are never exposed to guardians (privacy of minors) |
| Teacher | Generates + publishes MCQ class tests for their own sections; reads the school-shared archive (read-only); views per-test result summaries |
| School Admin | No direct UI here; tenant-scoped cost report data feeds module 07 |
| Super Admin | Platform-wide cost report stub (monthly cost per active user) feeding module 07 |
| Partner / EdTech brand | N/A — partners never touch AI study features |
| System (jobs, webhooks) | Scan-tagging + MCQ-generation jobs (module 01 runner), quota ledger upserts, daily cost circuit breaker, push hand-off to module 06 |

## 3. Scope

**In scope**

- `AIService` Go interface + DeepSeek adapter (vision tagging, MCQ generation, chat-query classification); prompt templates versioned in code; outputs validated against versioned JSON schemas before persistence.
- Per-user/per-feature weekly quotas enforced server-side (before enqueue **and** at job start), plan-aware (free vs Kushol Pro flag from module 03).
- Notes Scanner: scan from 05-confirmed media → async vision job → tags (subject/chapter/topic) + bilingual summary → searchable archive; per-scan share toggle (private default).
- Archive search across own + shared-in-school scans (pg_trgm text + tag filters).
- Auto-CT: student practice generation (5/week free), teacher class-test generation/publish for a section, in-app test-taking, deterministic auto-grading with explanations.
- Cost discipline: every model call writes tokens/cost/model to `ai_usage_ledger`; daily platform cost circuit breaker ("AI paused" degradation); admin cost-report stub endpoint.

**Out of scope** (explicit — prevents scope drift)

- Pain Point Matrix dashboards — module 09 consumes the `ClassifyChatQueries`/`QuotaState`/`AttemptStats` exports; no dashboards here.
- Kushol Pro purchase/billing — module 12; until then the Pro flag is plan data from module 03 (ops-set).
- Web dashboards/cards — module 07 (School/Super Admin); this module ships the data endpoints only.
- Chat message writes/reads — chat stays in module 05; classification runs over samples 09 supplies.
- Editable scan text/OCR-correction UI (v1 stores model output as returned); test timers beyond a P2 option; PDF export of tests.

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | `jobs.Enqueue`/worker (all AI calls run async), `audit.Record`, RFC-7807 error envelope, rate-limiter base |
| 02 design-system | bn/en catalogs (`ai.*`, `validation.*`), tokens, RN primitives |
| 03 identity-access | `auth.RequireVerified` (AI is verified-only), users: locale + `users.PlanOf` (Kushol Pro, `users.plan` column) |
| 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (section/school scope for archive visibility + class tests) |
| 05 communication-engine | `media.PresignUpload`/`ConfirmUpload` (scan images ride 05's R2 upload service) |
| 06 notifications | Push on scan-ready + test-published (deep links) |

---

## 4. User Stories

### `AIH-US-001` — Student scans handwritten notes into their archive

**Priority:** P0 · **Traces:** BR-02 (`brd.md` §5) / PRD §5.2 (Smart Study Hub) · **Depends on:** 05, 03

**Story** — As a **verified student**, I want **to photograph my handwritten notes and have AI tag and summarize them privately**, so that **my paper notes become a searchable, organised study archive**.

**Acceptance criteria**

- **Given** I have scan quota left, **when** I capture, preview and confirm upload, **then** the image flows through 05's media service (presign → R2 PUT → confirm), a scan row is created `processing` **private by default** (share is an explicit per-scan toggle), quota is reserved, and a tagging job is enqueued — ≤ 3 interactions.
- **Given** the job returns subject/chapter/topic tags + a summary in my locale (bn stays bn), **when** validation passes, **then** the scan flips `ready` and module 06 pushes "নোট স্ক্যান সম্পন্ন হয়েছে / Note scan complete" deep-linking to the detail; polling covers push loss.
- **Given** DeepSeek is slow/down or the output is malformed, **when** retries and the one repair attempt exhaust, **then** I keep seeing "প্রসেসিং চলছে — জানানো হবে / Processing — we'll notify you", then an honest `failed` state with retry and my quota refunded — never a dead end or a junk archive row.

### `AIH-US-002` — Student searches the archive by text and tags

**Priority:** P0 · **Traces:** PRD §5.2 ("searchable school-wide database") · **Depends on:** AIH-US-001

**Story** — As a **student**, I want **to search my own scans and shared school scans by Bangla text and tag chips**, so that **I find "ক্যালকুলাস অধ্যায় ৩" notes in seconds before an exam**.

**Acceptance criteria**

- **Given** I type a query, **when** I search, **then** `GET /ai/notes/search?q=&tags=` matches summaries and normalized tags via pg_trgm (Bangla NFC-normalized), p95 < 300 ms, in bn and en.
- **Given** the scope filter, **when** I pick "আমার নোট / My notes" or "স্কুলে শেয়ারকৃত / Shared to school", **then** results respect visibility: own always, shared only within my school; multiple tag chips AND-combine (`AIH-IT-002`).

### `AIH-US-003` — Teacher generates an MCQ class test from chapters

**Priority:** P0 · **Traces:** BR-02 / PRD §5.2 (Auto-CT) · **Depends on:** 04, 03

**Story** — As a **class teacher**, I want **to generate an MCQ test for my section from chosen chapters/topics**, so that **I get a ready-to-run class test in minutes instead of an evening of typing**.

**Acceptance criteria**

- **Given** I teach section N, **when** I create a class test (subject + chapter/topic, count 5–30 default 10), **then** a test row is created `generating`, an MCQ job runs `GenerateMCQs`, and schema-valid questions (4 options, one correct, explanations) land in `ai_test_questions` (weekly teacher cap 20 — `TODO: Confirm`).
- **Given** a `ready` test, **when** I preview it, **then** I see full questions **with** answer key + explanations, and I can publish or discard; malformed output → one repair attempt, then a graceful failure I can regenerate (US-009).

### `AIH-US-004` — Teacher publishes a class test; section students see it

**Priority:** P0 · **Traces:** PRD §5.2 · **Depends on:** AIH-US-003

**Story** — As a **teacher**, I want **to publish the test to exactly my section and close it afterwards**, so that **only my students get it at the right moment**.

**Acceptance criteria**

- **Given** my `ready` class test, **when** I publish, **then** status → `published`, the question set is frozen (jsonb snapshot immutability), and module 06 pushes "নতুন ক্লাস টেস্ট / New class test" to the section's students with a deep link; students of other sections/schools never see it (`TENANT_MISMATCH`/404).
- **Given** a published test, **when** I close it, **then** status → `closed`, new attempts are refused `CONFLICT`, and existing graded results stay viewable.

### `AIH-US-005` — Student generates a practice Auto-CT (free quota gate)

**Priority:** P0 · **Traces:** `brd.md` §7 (5 free/week; Pro unlimited) · **Depends on:** AIH-US-003 mechanics

**Story** — As a **student**, I want **to generate MCQ practice tests from any chapter**, so that **I can drill exactly what I am weak at before exams**.

**Acceptance criteria**

- **Given** I am a free-plan student with < 5 practice gens this week, **when** I pick subject/chapter + count and generate, **then** quota is reserved server-side (5th allowed), a `generating` test appears, and questions land ≤ 30 s target — quota checked before enqueue **and** at job start.
- **Given** I used 5 this week, **when** I try to generate, **then** I get `QUOTA_EXCEEDED` and the Kushol Pro upsell (US-008); a Pro-flag student has no weekly cap and sees "প্রো / Pro" instead of a count chip.

### `AIH-US-006` — Student takes a test in-app

**Priority:** P0 · **Traces:** PRD §5.2 ("administers") · **Depends on:** AIH-US-004/005

**Story** — As a **student**, I want **a clean one-question-at-a-time test screen**, so that **taking a test on a 360px phone is friction-free**.

**Acceptance criteria**

- **Given** I start an attempt, **when** `POST /ai/tests/{id}/attempts` succeeds, **then** a unique `in_progress` attempt opens the pager at question 1; each option tap upserts via `POST /ai/attempts/{id}/answers` (latest wins) and my selections survive a remount.
- **Given** I tap submit with unanswered questions, **when** the confirm sheet shows, **then** it warns "২টি প্রশ্নের উত্তর দেওয়া হয়নি / 2 questions unanswered"; the answer key never reaches my device pre-submit.

### `AIH-US-007` — Auto-grading with instant, explained results

**Priority:** P0 · **Traces:** PRD §5.2 ("auto-grades") · **Depends on:** AIH-US-006

**Story** — As a **student**, I want **my test graded instantly with per-question correctness and explanations**, so that **I learn from mistakes immediately**.

**Acceptance criteria**

- **Given** I submit, **when** `POST /ai/attempts/{id}/submit` runs, **then** grading is deterministic server-side (chosen vs `correct_index` — a rule, never a model call), score written, status → `graded`, response < 1 s; a duplicate submit returns `CONFLICT` and the original result.
- **Given** grading completes, **when** the result screen renders, **then** I see a score ring (৭/১০) and per-question ✓/✗ with the correct answer + explanation in my locale; the result stays readable offline.

### `AIH-US-008` — Quota exhausted is a path, not a dead end

**Priority:** P0 · **Traces:** `brd.md` §7 (freemium → Pro) · **Depends on:** AIH-US-005

**Story** — As a **free-plan student**, I want **a clear, friendly quota-exhausted screen that shows the Pro path**, so that **I know exactly how to get unlimited Auto-CT**.

**Acceptance criteria**

- **Given** `QUOTA_EXCEEDED`, **when** the app receives it, **then** a dedicated bn+en screen shows "এই সপ্তাহের ফ্রি কোটা শেষ / This week's free quota is used up", the reset day, and the Pro card "কুশল প্রো — ৯৯৳/মাস, আনলিমিটেড অটো-সিটি"; with module 12 unshipped the CTA shows "শীঘ্রই আসছে / Coming soon" — never a broken purchase flow.
- **Given** any AI screen, **when** quota remains, **then** a chip shows "৩/৫ বাকি / 3 of 5 left", sourced from `GET /ai/usage`; archive browsing and taking already-generated tests keep working.

### `AIH-US-009` — AI service down: retries, honest states, never fatal

**Priority:** P0 · **Traces:** persona (degradation) · **Depends on:** AIH-US-001/003

**Story** — As a **user**, I want **AI hiccups absorbed by the system**, so that **my scan or test eventually completes or is honestly failed with my quota refunded — never lost**.

**Acceptance criteria**

- **Given** DeepSeek times out (30 s vision / 60 s gen), **when** the adapter retries ×2 with backoff, **then** the job stays queued and users keep the processing copy; no UI ever blocks on a model call.
- **Given** the daily platform cost cap is hit, **when** the circuit breaker trips, **then** new AI jobs queue (not start) behind the banner "এআই সাময়িকভাবে বন্ধ — শীঘ্রই ফিরবে / AI is paused — back soon", resuming at reset; terminal failures refund quota automatically.

### `AIH-US-010` — Every AI call logs cost; admins get a report stub

**Priority:** P1 · **Traces:** persona (cost discipline) / `prd.md` §4A · **Depends on:** AIH-US-001/003

**Story** — As the **platform operator**, I want **tokens, cost, model and call count recorded per user/feature/week with an admin report endpoint**, so that **AI spend per active user is measurable and module 07 can render it later**.

**Acceptance criteria**

- **Given** any model call (scan | mcq_gen | classify), **when** the adapter returns, **then** `ai_usage_ledger` upserts count/tokens/cost/model — including calls whose downstream work later fails (we paid DeepSeek) while user quota is refunded separately.
- **Given** `GET /api/v1/ai/admin/cost-report?month=YYYY-MM`, **when** a Super Admin (platform) or School Admin (own tenant) calls it, **then** it returns per-feature totals, active users and per-tenant split; other roles `FORBIDDEN`; empty months return valid zeros for 07.

### `AIH-US-011` — Teacher sees class-test results summary

**Priority:** P1 · **Traces:** PRD §5.2 / module 09 feed · **Depends on:** AIH-US-007

**Story** — As a **teacher**, I want **per-test stats (average, per-question miss rate) for my published tests**, so that **I know what to re-teach — and module 09's matrix gets clean aggregates**.

**Acceptance criteria**

- **Given** attempts exist on my published test, **when** I open its results, **then** I see attempt count, average score and per-question miss % (computed by `ai.AttemptStats`, exported for 09).
- **Given** another teacher's or another school's test, **when** I request its stats, **then** I get `FORBIDDEN`/404 — creator + same-tenant section only.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `AIH-BR-001` | Every `/ai` surface requires a VERIFIED user (`auth.RequireVerified`); others get `NOT_VERIFIED` | Service layer, every entry point |
| `AIH-BR-002` | Quota checked server-side **before enqueue AND at job start**; reservation is an atomic conditional ledger upsert (last slot cannot double-spend); refunded on terminal job failure | `aiquota.Reserve` + job handlers |
| `AIH-BR-003` | Free students: 5 practice Auto-CT generations/week (`brd.md` §7) and 5 scans/week (`TODO: Confirm`); Kushol Pro (plan flag): unlimited; quota is per generation, not per attempt | Service + ledger |
| `AIH-BR-004` | Teachers: class-test generation capped 20/week per teacher (`TODO: Confirm`); only sections they teach | Service + `hierarchy.ResolveUserNodes` |
| `AIH-BR-005` | Scans are PRIVATE by default; school-wide visibility only via explicit per-scan share toggle (privacy of minors, `brd.md` §6); delete/share owner-only + audited | DB default `shared=false` + service |
| `AIH-BR-006` | Archive visibility = own scans ∪ shared scans of the same school; teachers read shared-in-school; nothing crosses tenants | Tenant-scoped repository (every query) |
| `AIH-BR-007` | Publishing freezes the question set: `questions_snapshot` written, questions immutable after publish; grading uses the snapshot's `correct_index` | Service + DB (no UPDATE path post-publish) |
| `AIH-BR-008` | The answer key (`correct_index`, `explanation`) is never serialized to a student client before their attempt is graded | DTO mapper gate (`AIH-UT-005`) |
| `AIH-BR-009` | One attempt per (test, student); answers writable only while `in_progress`; submit terminal; grading deterministic (never a model call) | DB UNIQUE + service state machine |
| `AIH-BR-010` | Every model call (scan/mcq_gen/classify) writes tokens_in/out + cost_usd + model + count to `ai_usage_ledger` (classify: system-initiated by 09 — costs recorded, no user quota) | Adapter post-call hook |
| `AIH-BR-011` | Platform-wide daily cost circuit breaker: trips at the configured cap (`TODO: Confirm`) → jobs queue + "AI paused" banner; resets next day (Asia/Dhaka) | `aicost.Guard` + Redis flag |
| `AIH-BR-012` | AI REST endpoints rate-limited under class `ai`; generation additionally quota'd (BR-002/003) | Redis rate limiter |
| `AIH-BR-013` | Model output persists only after versioned JSON-schema validation; malformed → 1 repair attempt → job failure; prompt template + version logged per call | DeepSeek adapter + prompt registry |
| `AIH-BR-014` | AI-generated content language follows the user's stored locale (bn default); summaries/tags stored as returned | Adapter `locale` param from 03 users |

> Content-accuracy (`prompt.txt` §12): seeded scans/tests use clearly fictional "Demo High School" content marked in `03` §1.3; generated questions are schema-validated; demo artifacts are never published to real tenants.

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| Scan `imageAssetId` | Required; asset `confirmed` (05 sniff), `kind=image`, owned by caller | `validation.ai.media_required` |
| Search `q` | 0–100 chars after trim (empty = tag-filter browse) | `validation.ai.query_length` |
| Search `tags` | ≤ 10 chips, `level:value` pairs | `validation.ai.tags_invalid` |
| Test `kind` | `practice` (student) \| `class_test` (teacher) — role must match kind | `validation.ai.kind_invalid` |
| Test `count` | Integer 5–30, default 10 (`TODO: Confirm`) | `validation.ai.count_range` |
| Test `subject`/`chapter`/`topic` | 1–120 chars; chapter required, topic optional | `validation.ai.scope_required` · `scope_length` |
| Class-test `sectionId` | Required; a section the teacher teaches (04) | `validation.ai.section_not_yours` |
| Answer `chosenIndex` | 0–3; question belongs to the attempt's test; only while `in_progress` | `validation.ai.choice_invalid` · `attempt_closed` |
| Cost-report `month` | `YYYY-MM`, not in the future | `validation.ai.month_invalid` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (app) generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any `/ai` route | `UNAUTHENTICATED`, no side effect (`AIH-IT-009`) |
| 2 | Cross-tenant read (scan/test/attempt of another school) | `TENANT_MISMATCH` / 404, no leak (`AIH-IT-002`) |
| 3 | Unverified (pending) user calls any AI action | `NOT_VERIFIED` + how-to-get-verified guidance |
| 4 | R2 object behind a ready scan deleted/archived | Detail degrades to placeholder; tags + summary still render — never a crash |
| 5 | Reduced motion enabled | Score ring and progress states render static (app §5) |
| 6 | Offline action (app) | Scan capture queued; test-taking blocked with a clear bn/en message — never silent loss (app §8) |
| 7 | Two concurrent generations at the last quota slot | Conditional ledger upsert: exactly one wins; loser gets `QUOTA_EXCEEDED` (`AIH-UT-001`) |
| 8 | Student probes for the answer key pre-submit | Payload never contains `correct_index`/`explanation` (`AIH-UT-005`) |
| 9 | Duplicate submit / answer after submit | `CONFLICT`; original result returned unchanged |
| 10 | Shared scan unshared/deleted while a peer views it | Peer's next fetch 404s with "নোটটি আর শেয়ার করা হয়নি / This note is no longer shared" |
| 11 | Model returns schema-valid but empty tags/summary | Treated as failure → repair attempt → `failed` + refund (not a junk archive row) |
| 12 | Year-end section migration (04) | Class tests keep their section; student archives follow the owner, not the section |
| 13 | Circuit breaker tripped mid-browsing | Browsing/search/taking existing tests work; only new generation/scan actions gate with the paused banner |

## 8. Reporting Needs

- **Module 07 (web):** monthly AI cost totals, cost per active user, per-feature/per-tenant split — served by `GET /ai/admin/cost-report` (US-010); 07 renders the cards when data exists.
- **Module 09 (analytics):** weekly per-section attempt aggregates (`ai.AttemptStats(sectionID, weekStart, weekEnd)`) + `ClassifyChatQueries` topic tags over samples 09 supplies.
- **Operational:** weekly scans/tests/attempt volumes per tenant for capacity + cost forecasting (slog metrics + ledger).

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Exact DeepSeek model IDs (cheapest Flash-class vision + chat) | Rahul | Open (`TODO: Confirm`) | Flash-class cheapest vision + chat models, IDs in config not code |
| 2 | Free weekly scan quota (proposed 5/week, aligned with freemium) | Rahul | Open (`TODO: Confirm`) | 5 scans/week free; Pro unlimited |
| 3 | Teacher class-test generation cap (proposed 20/week/teacher) | Rahul | Open (`TODO: Confirm`) | 20/week per teacher |
| 4 | Platform-wide daily AI cost cap for the circuit breaker | Rahul | Open (`TODO: Confirm`) | USD 10/day platform-wide, Asia/Dhaka day boundary |
| 5 | Scans default share-OFF with explicit opt-in share (minors' safety) | Rahul | Open (`TODO: Confirm` — safety decision) | Private by default; share per-scan toggle, off |
| 6 | MCQ defaults: questions per test (proposed 10, range 5–30) and options per question (proposed 4) | Rahul | Open (`TODO: Confirm`) | 10 questions, 4 options, explanations required |
| 7 | How users obtain the Kushol Pro flag before module 12 billing ships | Rahul | Open | Super Admin sets `users.plan` via 03 `users.SetPlan` (07 action) until 12 billing lands |
