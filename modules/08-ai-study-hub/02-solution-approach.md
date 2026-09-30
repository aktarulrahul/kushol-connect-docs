# AI Study Hub — Solution Approach

**Module:** `08-ai-study-hub` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `note_scans` | One scanned note: owner (student), tenant school, optional section context, image ref (05 `media_assets`), `status ∈ processing\|ready\|failed`, bilingual summary **as returned by the model**, `shared` flag (default false) | Yes |
| `note_tags` | Vision tags per scan: `level ∈ subject\|chapter\|topic`, raw `value` + `normalized` (NFC, trimmed, lowercase) for search/dedupe | Yes |
| `ai_tests` | A generated MCQ test: `kind ∈ practice\|class_test`; creator; `section_id` NOT NULL for class tests, NULL for practice; subject/chapter/topic scope; `status ∈ generating\|ready\|published\|closed`; `questions_snapshot` jsonb frozen at publish | Yes |
| `ai_test_questions` | Normalized questions: order, stem, `options` jsonb (4), `correct_index`, explanation — the working copy the app renders | Yes |
| `ai_test_attempts` | A student's sitting: started/submitted_at, score, `status ∈ in_progress\|submitted\|graded`; UNIQUE (test, student) | Yes |
| `ai_test_answers` | Per-question choices: `chosen_index`, `correct` (computed at submit) — UNIQUE (attempt, question) | Yes |
| `ai_usage_ledger` | Quota + cost ledger: per (user, feature ∈ scan\|mcq_gen\|classify, week_start): count, tokens_in/out, cost_usd, model | Yes |
| `AIService` (interface) | The AI seam: DeepSeek adapter today, FastAPI adapter later — same Go interface, same JSON contract shapes | Yes (code seam) |
| `media_assets` | Scan images (R2, sniffed, confirmed) | No — module 05 |
| `users` (locale, plan flag) | Locale for AI content language; Pro flag for quotas | No — module 03 |
| `sections` / `school` nodes | Class-test targeting + archive visibility scope | No — module 04 |
| Push delivery | `notifications` fan-out on scan-ready / test-published | No — module 06 |

### 1.2 Relationships

```text
user (03, student) 1───* note_scans *───1 media_assets (05, confirmed image)
school (04) 1───* note_scans (tenant)          note_scans 1───* note_tags
user (03, student|teacher) 1───* ai_tests (creator)      ai_tests.section_id *───1 section (04, class_test only)
school (04) 1───* ai_tests (tenant)            ai_tests 1───* ai_test_questions  (+ questions_snapshot jsonb)
ai_tests 1───* ai_test_attempts *───1 user (03, student)      ai_test_attempts 1───* ai_test_answers *───1 ai_test_questions
user (03) 1───* ai_usage_ledger (unique per feature × week_start)
AIService ◀── scan job (TagNoteImage) · mcq job (GenerateMCQs) · module 09 (ClassifyChatQueries)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-1 | Every scan/test/attempt query is tenant-scoped (`school_id = caller`) **and** visibility-guarded: scan visible iff `owner=caller ∨ (shared ∧ school=caller)`; class test iff creator or section member; attempt iff its student | Tenant-scoped repositories (`AIH-IT-002`) |
| INV-2 | Quota: reservation is a conditional ledger upsert (`count < limit` in the UPDATE … WHERE) — atomic; re-checked at job start; refunded on terminal job failure | `aiquota.Reserve` (`AIH-UT-001`, `AIH-IT-001`) |
| INV-3 | A scan references only a `confirmed` 05 media asset owned by the scan owner | Service guard on `POST /ai/notes` |
| INV-4 | `kind='class_test' ⇒ section_id NOT NULL`; `published ⇒ questions_snapshot NOT NULL`; questions immutable after publish | DB CHECKs + no UPDATE path |
| INV-5 | Student DTOs exclude `correct_index`/`explanation` until the caller's attempt is `graded` | DTO mapper gate (`AIH-UT-005`) |
| INV-6 | One attempt per (test, student); answers writable only while `in_progress`; submit terminal; grading deterministic (chosen vs `correct_index`) | UNIQUE index + state machine |
| INV-7 | Every model call writes the ledger (tokens, cost, model, count) — including calls whose downstream work later fails; prompt template version logged per call | Adapter post-call hook (`AIH-IT-007`) |
| INV-8 | Model output persists only after JSON-schema validation; malformed → 1 repair attempt → job failed; model text is data, never instructions (prompt-injection posture) | DeepSeek adapter (`AIH-IT-005`) |

## 2. Module Boundary

**Owns (writes):** `note_scans`, `note_tags`, `ai_tests`, `ai_test_questions`, `ai_test_attempts`,
`ai_test_answers`, `ai_usage_ledger` — plus the `AIService` interface, the versioned prompt
registry, and the JSON contract schemas for model output.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 05 | `media.PresignUpload`/`ConfirmUpload` — scan images ride the shared R2 upload service | Upload hardening (magic bytes, caps) lives once; 08 never proxies bytes |
| 03 | Verification gate (`auth.RequireVerified`), user locale + plan flag | Identity/plan data is 03's source of truth |
| 04 | `hierarchy.ResolveUserNodes(userId)` — teach-sections (class tests) + school scope (archive) | Hierarchy is 04's data model |
| 01 | `jobs.Enqueue`/worker, `audit.Record`, RFC-7807 envelope, rate limiter | Foundations own the plumbing |
| 06 | Push dispatch on scan-ready / test-published | FCM fan-out is 06's job |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4
(`ai:usage:{userId}`, `ai:tags:school:{id}`, `ai:breaker:state`).

## 3. Lifecycle

Three async-first state machines. **Async-by-default:** every generation runs as a module-01 job;
the API returns immediately; completion reaches users via 06 push + app refetch/poll.

```text
scan:   PROCESSING ──job ok──▶ READY ──delete──▶ (removed)      PROCESSING ──terminal failure──▶ FAILED ──retry──▶ PROCESSING
test:   GENERATING ──job ok──▶ READY ──teacher publish──▶ PUBLISHED ──teacher close──▶ CLOSED
                GENERATING ──terminal failure──▶ FAILED (regenerate = new test)
attempt: IN_PROGRESS ──submit (auto-grade)──▶ SUBMITTED ──score written──▶ GRADED (terminal)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| — | `POST /ai/notes` (confirmed media) | scan PROCESSING | verified + owner-asset + quota reserved (BR-002) | job enqueued; ledger row reserved |
| scan PROCESSING | tagging job succeeds | READY | quota re-check at job start (INV-2) | tags + summary persisted; 06 push "scan complete"; ledger cost write |
| scan PROCESSING | tagging job fails ×N | FAILED | retry/backoff/dead-letter per 01 | quota refunded; `failed` copy + retry action |
| scan READY | `PATCH …/share` | shared on/off | owner only | visibility flips in school search |
| — | `POST /ai/tests` | GENERATING | verified; role matches kind; section guard (teacher) / quota (student) | MCQ job enqueued |
| test GENERATING | MCQ job succeeds | READY | schema-validated questions (INV-8) | questions + rows inserted; teacher preview gets key |
| test READY | teacher publishes | PUBLISHED | creator + class_test + own section | snapshot frozen (INV-4); 06 push to section; students see test |
| test PUBLISHED | teacher closes / student starts attempt | CLOSED / attempt IN_PROGRESS | close: creator; attempt: section member + no prior attempt | closed refuses new attempts (`CONFLICT`) |
| attempt IN_PROGRESS | submit | SUBMITTED → GRADED | all-or-nothing grade; duplicate submit `CONFLICT` | score written; answers marked correct; result + key released to student |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| App archive/search lists | TanStack Query (paginated 20/page); search is server-computed (pg_trgm) | Last result page cached in memory for back-navigation only | `ai:archive:user:{id}` (memory) |
| App scan detail | Query + poll every 3 s while `processing` (or 06 push cancels polling) | none (state is fresh-critical) | — |
| App test list / detail / result | TanStack Query; test detail refetches on attempt submit | result cached offline (read-only) per attempt | `ai:tests:user:{id}` (memory) |
| Server tag-chips list (distinct normalized tags in visibility scope) | Redis, TTL 300 s | busts on scan create/delete/share-flip | `ai:tags:school:{id}` |
| Server quota state (`GET /ai/usage`) | Cheap ledger SELECT per request | Redis memo TTL 30 s (quota changes are rare per minute) | `ai:usage:{userId}` |
| Server breaker flag | Redis key read per generation request | the key **is** the cache (TTL = rest of day) | `ai:breaker:state` |
| Generated question/summary reuse | **No result cache v1** — identical regenerate requests run fresh (immutability + simplicity) | alternative noted in §10 | — |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Weekly quotas per feature/plan (free: scans 5, mcq_gen 5; Pro: ∞) | Async-only generation (all model calls are module-01 jobs) |
| Teacher class-test cap (default 20/week — `TODO: Confirm`) | Schema validation gate before persistence + 1-repair-retry rule (INV-8) |
| Daily platform cost cap for the circuit breaker (`TODO: Confirm`, default USD 10) | Answer-key gating on student DTOs (INV-5) |
| DeepSeek model IDs per task (vision/chat) + `AI_PROVIDER` switch (`deepseek-go` today, `fastapi` later) | Tenant scoping + share-default-off (safety invariants) |
| MCQ defaults: count 10 (range 5–30), 4 options | Deterministic rule-based grading (never a model call) |
| Adapter timeouts (vision 30 s / gen 60 s) and retry ×2 + backoff | Week boundary: Monday 00:00 Asia/Dhaka; breaker day boundary Asia/Dhaka |
| "AI paused" banner copy overrides (bn/en) | Prompt registry: templates are code constants with version fields, logged per call |

## 6. Security

Entry points: 16 REST endpoints under `/api/v1/ai` (see `03` §2). Every entry runs
**authenticate → load role claims → tenant-scope → `auth.RequireVerified`** — AI features are
verified-only (`AIH-BR-001`). No public/unauthenticated surface exists in this module.

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| `note_scans` (list/get/search/patch/delete) | Verified; delete/share: owner only; shared reads: same-school members; teacher: shared read-only | `school_id = caller.schoolId` ∧ visibility matrix (INV-1) on every query |
| `ai_tests` (create/list/get/publish/close) | Verified; practice = student, class_test = teacher of the section; publish/close = creator | `school_id = caller.schoolId`; class tests additionally `section ∈ caller's teach-sections` (04) |
| `ai_test_attempts` / answers | Verified student, own attempts only; teacher reads aggregates of own tests | `school_id = caller.schoolId` ∧ `student_id = caller` (write path) |
| `ai_usage_ledger` | Own via `GET /ai/usage`; admin cost report: Super Admin (all) / School Admin (own tenant) | Row-level user guard; admin path tenant-guarded by role |
| Jobs (scan/mcq) | System-initiated; carry user + tenant ids in payload; re-verify quota + scope at start | Job handlers re-run the same repository guards as the API path |

Validation/sanitisation: contract-generated validators on every route; model output treated as
**untrusted data** — persisted only after versioned JSON-schema validation; prompt text never
includes other users' content; images go to DeepSeek as 05-confirmed R2 URLs. Rate limits: class
`ai` on generation/search routes (BR-013) on top of quotas (BR-002/003). Privacy: scans of minors
default-private (BR-006); no note content, summary or stems in logs (slog redaction) — logs carry
ids, feature, model, token counts, prompt_version; audit records on share/delete/publish/close.

## 7. Accessibility & Motion

App-side surfaces (details + 360px layouts in `05-app-tasks.md` §5/§7): scan progress uses a
purposeful shimmer + text (never a bare spinner); the result score ring animates once with a
static reduced-motion form; tag chips fade in as a group. Screen reader: each result question is
one semantic unit ("প্রশ্ন ৩ — সঠিক / Question 3 — correct"); quota chip is a live region; the
quota-exhausted screen is a full-screen announcement in bn + en. Web: N/A this module.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | DeepSeek timeout (30 s vision / 60 s gen) | Adapter context deadline | Job stays in progress; user sees processing copy | Retry ×2 with exponential backoff (module 01 job retries); dead-letter after exhaustion → `failed` + quota refund |
| 2 | Malformed model output (schema validation fails) | Validator reject | No persistence | 1 repair attempt (validation errors appended to the prompt); second failure → job failed + refund (`AIH-IT-005`) |
| 3 | Daily cost circuit breaker trips | `aicost.Guard` ledger sum + Redis flag | New AI jobs queue, not start; banner shown | Jobs resume automatically at day reset; ops alerted at 80%/100% thresholds |
| 4 | R2 object missing for a ready scan | 404 on presigned GET | Image placeholder in detail | Tags/summary unaffected; user may rescan; 05's rehydration applies if archived |
| 5 | Job runner down (module 01) | Runner health | Scans/tests stay PROCESSING/GENERATING longer | Jobs persist in DB — runner restart resumes; user copy already says "we'll notify you" |
| 6 | Neon (Postgres) degraded | Connection errors | AI surfaces fail (source of truth) | 01/15 runbooks: pool alarm, failover; jobs resume after recovery |
| 7 | Push (module 06) down | BroadcastTopic error | User misses the ready/published push | In-app poll + list refetch still reveal the state; 06 retries its queue |
| 8 | Ledger write fails after a successful model call | Post-call hook error | Cost under-count for one call | Hook retries ×3 then logs an alert row (slog) — quota is DB-transactional so never over-counted |

## 9. Performance

- Volumes (pilot): 3 schools × ~2,000 users; assume 5% daily AI actives (~300) × ~2 calls/day ≈
  600 model calls/day peak — DeepSeek Flash-class cost stays trivially inside the breaker cap.
- **Scan latency: target p95 < 60 s async** (upload ~2 s on 3G + queue < 5 s + vision model);
  **MCQ generation p95 < 30 s**. Both are async — the API round-trip itself is < 200 ms (enqueue).
- Auto-grade: pure SQL UPDATE+JOIN against `ai_test_questions` — p95 < 200 ms, zero model calls.
- Archive search: pg_trgm GIN on `note_scans.summary` + `note_tags.normalized`; p95 < 300 ms at
  pilot scale; composite indexes per `03` §1.1.
- Ledger: single upsert per call (`(user_id, feature, week_start)` UNIQUE) — no read-modify-write.
- Bundle impact: **no new app dependencies** — `expo-camera`/`expo-image-picker` are already the
  module-05 media stack; API adds only the DeepSeek HTTP adapter (stdlib `net/http`).

## 10. Alternatives Considered

### Option A — DeepSeek direct from Go behind `AIService` · Option B — FastAPI AI service first

| | A (chosen for v1) | B |
| --- | --- | --- |
| Advantages | No second service to run on the shared 2 vCPU VPS; one deployable; interface frozen now so the swap is infra-only (`tech-stack.md` decision, README row) | Python's AI ecosystem for future prompt chains/parsing |
| Disadvantages | Go-side prompt/JSON plumbing (small, schema-driven) | Extra container + internal API to operate before Phase-2 scale justifies it |
| Complexity / weight | Low | Medium |

**Recommendation:** A now, B later behind the same interface — clients never change. ADR: record
the swap in `07-progress.md` when `applications/ai` lands (FastAPI adapter = HTTP over internal
network only, never client-exposed).

### Option A — async jobs for all generation · Option B — synchronous API

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Retry/dead-letter/refund for free; mobile survives network drops; latency budget honest | Simpler code path |
| Disadvantages | States (PROCESSING/GENERATING) + push wiring | 30–60 s mobile connections die on 3G; retry = duplicate cost; timeouts look like failures |
| Complexity / weight | Medium (module 01 jobs already exist) | Low code, product-fatal on target networks |

**Recommendation:** A — the target user is on 360px/3G; sync generation would be the single
biggest reliability risk in the product.

### Option A — normalized questions + jsonb snapshot · Option B — jsonb-only

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Typed per-question rows for grading joins, stats (`AttemptStats`), and per-question answers; snapshot freezes the published paper immutably | One column; no second write |
| Disadvantages | Two representations to keep consistent (write once at job completion + freeze at publish) | Grading/stats become jsonb surgery; per-question answer FKs impossible |
| Complexity / weight | Low–medium | Low code, high query cost later |

**Recommendation:** A — grading, result screens and module-09 analytics all want relational
questions; the snapshot is the immutability guarantee, not the working copy.

### Option A — rule-based grading · Option B — model-based grading

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Deterministic, instant, free, explainable | Handles fuzzy "almost right" answers |
| Disadvantages | MCQ is exact-match anyway — B buys nothing | Cost + latency + non-determinism on a graded score (trust risk for schools) |
| Complexity / weight | Trivial | Medium + ongoing cost |

**Recommendation:** A — *never call a model when a rule will do* (persona). The model's job ends
at generating a well-formed MCQ with one correct option.

### Rejected v1: result cache for identical regenerate requests

Serving repeated identical `GenerateMCQs` calls (same scope/count/locale) from a short-window
ledger check would cut cost, but risks two students sharing one paper during a class test and
couples quota semantics to caching. Kept simple: **no result cache v1**; revisit as a
ledger-window dedupe for practice-only traffic if cost data justifies it (noted as alternative).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | DeepSeek Flash vision reads Bangla handwritten notes well enough for subject/chapter/topic tags | Junk tags erode trust in the archive | Tags are advisory + deletable; summary is clearly "AI-generated"; failed/empty extractions surface honestly; model IDs are config so upgrades are instant |
| 2 | Model cost per call stays in Flash-class budget | Breaker trips often; users locked out | Quotas cap per-user spend; breaker threshold is admin-configurable; cost ledger makes overruns visible daily (US-010) |
| 3 | Prompt-injection via photographed notes cannot pivot into system actions | Malicious instructions in images | Output is schema-validated data only; no tool use, no persistence of instructions; prompts fixed + versioned |
| 4 | Neon free tier absorbs job-table polling + ledger writes | Connection pressure | Module-01 runner polls conservatively; ledger upserts are single-statement; upgrade path documented (`tech-stack.md`) |
| 5 | Week-boundary (Monday Asia/Dhaka) matches user expectations of "weekly quota" | Support noise at reset time | Copy states the reset moment; boundary is fixed in code, changeable with an ADR |
| 6 | Share-default-off limits the "school-wide database" network effect | Slower archive growth | Sharing is one toggle with a friendly value-prop copy; revisit defaults only with Rahul's explicit sign-off (OQ-5 — safety) |
