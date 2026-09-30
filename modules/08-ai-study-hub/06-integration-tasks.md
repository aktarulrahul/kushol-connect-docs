# AI Study Hub — Integration Tasks

**Module:** `08-ai-study-hub` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `01-foundations` | we call them | `jobs.Enqueue` / worker runner (scan-tagging, mcq-generation, refund, cost-guard jobs); `audit.Record`; RFC-7807 envelope; rate-limiter base | degraded — jobs delayed; API still validates + reserves quota; runner restart resumes |
| I-2 | `05-communication-engine` | we call them | `media.PresignUpload` / `media.ConfirmUpload` for scan images | fatal to scanning only (not fatal platform-wide); app keeps captured image queued |
| I-3 | `03-identity-access` | we call them | `auth.RequireVerified` middleware; users locale + plan flag (Kushol Pro) | fatal to all AI actions by design (`NOT_VERIFIED`); plan-flag read failure → safe default (free limits) |
| I-4 | `04-organization-hierarchy` | we call them | `hierarchy.ResolveUserNodes(userId)` (teacher sections for class tests; school scope for archive) | fatal to class-test create (cannot verify section) — refuse `FORBIDDEN`, never guess |
| I-5 | `06-notifications` | we call them | push dispatch on `scan_ready` + `class_test` (topic/payload per §5) | degraded — in-app polling still reveals state; 06 owns retry |
| I-6 | `09-teacher-analytics` | they call us | exported fns `ai.ClassifyChatQueries`, `ai.QuotaState`, `analytics.AttemptStats` (§2) | degraded — 09 skips the week's classify/aggregation |
| I-7 | `07-command-center-web` | they call us | REST `GET /api/v1/ai/admin/cost-report` (generated client) | degraded — 07 renders zeros/error state |
| I-8 | DeepSeek (external) | outbound | HTTPS JSON API (vision + chat, JSON-schema-validated output) | degraded — jobs queue + retry; breaker may pause (§8) |
| I-9 | `applications/ai` (external, later) | outbound | internal HTTP FastAPI adapter behind the same `AIService` interface; Compose-internal network only, never client-exposed | degraded — same as I-8 (adapter swap is transparent) |

## 2. Exported Contract

```text
ai.GenerateMCQs(ctx context.Context, scope ChapterScope, count int, locale string) ([]MCQ, error)
ai.TagNoteImage(ctx context.Context, imageRef ImageRef, locale string) (NoteTags, error)
ai.ClassifyChatQueries(ctx context.Context, samples []ChatQuerySample, locale string) (TopicTags, error)
ai.QuotaState(userID uuid.UUID) (QuotaStateDTO, error)
analytics.AttemptStats(sectionID uuid.UUID, weekStart time.Time) (AttemptStatsDTO, error)
```

Contract shapes (versioned JSON schemas, additive evolution):

```text
ChapterScope { subject, chapter, topic? string }
MCQ          { stem string; options [4]string; correct_index int 0..3; explanation string }
NoteTags     { summary string; tags []{ level: subject|chapter|topic; value, normalized string } }
TopicTags    { topics []{ value, normalized string; confidence float } }
QuotaStateDTO{ plan string; features []{ feature scan|mcq_gen|classify; used, limit int; week_start date } }
AttemptStatsDTO{ attempts int; avg_score float; per_question []{ question_id; miss_count; miss_pct } }
ImageRef     { assetID uuid; r2Key string }   // 05-confirmed asset only
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `ai.GenerateMCQs` | internal (mcq-generation job) | `[]MCQ` (schema-validated) | `ErrAIUnavailable`, `ErrMalformedOutput` (after 1 repair) | Adapter-dispatched (DeepSeek now / FastAPI later); ledger `mcq_gen` written by caller job; **teacher preview may see `correct_index`; student DTOs never pre-grade** (INV-5) |
| `ai.TagNoteImage` | internal (scan-tagging job) | `NoteTags` (schema-validated) | same | Vision model; image must be a 05-confirmed asset; ledger `scan` |
| `ai.ClassifyChatQueries` | 09 | `TopicTags` | same | Samples supplied by 09; ledger `classify` (no user quota — system feature); **aggregates only — 09 must not persist chat text** |
| `ai.QuotaState` | 09 (context for matrix), 07 (cost context) | `QuotaStateDTO` | `NOT_FOUND` | DTO only, never ledger rows |
| `analytics.AttemptStats` | 09 | `AttemptStatsDTO` | `FORBIDDEN` (non-tenant section) | Aggregate-only — per-student identity never leaves |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `media.PresignUpload` / `media.ConfirmUpload` (scan images) | 05 | Refuse scan creation with `VALIDATION_FAILED`; client keeps capture queued; never sniff files ourselves |
| `jobs.Enqueue` / runner registration | 01 | Enqueue failure → 503-shaped `INTERNAL` + in-memory fallback retry; jobs are DB-persisted so runner restart resumes |
| `auth.RequireVerified` + locale/plan claims | 03 | Writes refused `NOT_VERIFIED`; plan read failure → free-tier limits (fail-closed, never over-generous) |
| `hierarchy.ResolveUserNodes` | 04 | Class-test creation refused `FORBIDDEN`; archive falls back to owner-only scope (shared search disabled) until nodes resolve |
| Push dispatch (`scan_ready`, `class_test`) | 06 | Log + continue; polling + list refetch reveal state; 06 owns delivery retry |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Scan create / delete / share-flip | `ai:tags:school:{schoolId}` (chip facets, TTL 300 s) |
| Generation / quota reserve / refund | `ai:usage:{userId}` (TTL 30 s memo) |
| Publish / close test | app-side query invalidation via 06 push (`class_test`) — no server page-cache |
| Answer/submit | none (per-user, fresh-critical) |
| Breaker trip/reset | `ai:breaker:state` (the flag itself; TTL = rest of Asia/Dhaka day) |

| Read | Tagged with |
| --- | --- |
| `GET /ai/usage` | `ai:usage:{userId}` |
| Tag-chip facet | `ai:tags:school:{id}` |
| Archive/search/results | none (per-user fresh queries; app memory cache only) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| DeepSeek API (vision + chat) | HTTPS JSON (`response_format` json) | `DEEPSEEK_API_KEY` (envconfig-parsed, server-only) | 30 s vision / 60 s generation | ×2 exp backoff (adapter) + job-level retries via 01 | Jobs queue; "এআই সাময়িকভাবে বন্ধ / AI is paused" banner when breaker trips; quota refunded on terminal failure |
| Daily cost circuit breaker | Redis flag + ledger sum | internal | 200 ms | inline backstop compute | Generation paused at cap (`TODO: Confirm`, default USD 10/day); auto-resets at Asia/Dhaka midnight; ops alert at 80/100% |
| `applications/ai` FastAPI (later) | Internal HTTP (Compose network, no public ingress) | mTLS/shared internal token (`AI_INTERNAL_TOKEN`) | 35 s / 65 s | ×2 + job retries (same ladder) | Identical to DeepSeek-down — the interface hides the swap; `AI_PROVIDER=fastapi` config switch |
| FCM (via 06 only) | 06-owned Admin SDK | 06's `FCM_SERVER_KEY` | 06-owned | 06-owned | Push lost; in-app poll + lists still reveal `ready`/`published` |
| R2 (via 05 only) | 05-owned S3 API | 05's `R2_*` | 05-owned | 05-owned | Scan image URL 404 → placeholder; tags/summary intact |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| AI Hub quota chip | `GET /ai/usage` | `QuotaStateDTO`; `QUOTA_EXCEEDED` anywhere routes to the upsell modal |
| Scan confirm | `POST /media/upload-url` → R2 PUT → `POST /media/{id}/confirm` (05) → `POST /ai/notes` | Scan `processing` id returned; poll `GET /ai/notes/{id}` every 3 s |
| Scan detail | `GET /ai/notes/{id}` · `PATCH …/share` · `DELETE …` | Poll until `ready`/`failed`; short-lived R2 image URL; share toggle optimistic |
| Archive/search | `GET /ai/notes?scope=` · `GET /ai/notes/search?q=&tags=&scope=` | 20/page; chips from facet; bn search server-side |
| Generate sheet | `POST /ai/tests` | `generating` id; row polls until `ready`/`failed` |
| Test paper | `GET /ai/tests/{id}` → `POST /ai/tests/{id}/attempts` | Key-free DTO pre-grade (INV-5); attempt id for answers |
| Answers / submit | `POST /ai/attempts/{id}/answers` (upsert) · `POST /ai/attempts/{id}/submit` | Submit returns score + per-question key (only now) |
| Push taps (06) | deep links `/ai-hub/scan/[id]`, `/ai-hub/tests/[id]` | Payload carries ids + type only (no content) |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. **AI output schemas are versioned
separately** (`AIContract v1`): prompt templates and their expected JSON shapes are code constants;
the version is logged with every model call and stored with generated artifacts (`questions_snapshot`
embeds its contract version). Evolution is additive (new optional fields only); breaking shape
changes require `v2` templates + a read path for v1 artifacts. The `AIService` Go interface is the
frozen seam for the FastAPI swap — adapter changes never touch callers, and the internal HTTP
contract of `applications/ai` must mirror these schemas exactly (never client-exposed).

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| DeepSeek down / degraded | Archive browse/search, taking already-ready tests, results, usage | New scans/gens stay pending: "প্রসেসিং চলছে — হয়ে গেলে জানানো হবে / Processing — we'll notify you" | Adapter retries; jobs resume; terminal failures → `failed` + quota refund |
| Breaker tripped (daily cap) | Everything except new generation | "এআই সাময়িকভাবে বন্ধ — শীঘ্রই ফিরবে / AI is paused — back soon" banner; CTAs disabled, not hidden | Auto-reset at day boundary; ops alerted; cap tunable |
| R2 down (via 05) | All non-image AI surfaces | Scan upload blocked: "আপলোড ব্যর্থ — আবার চেষ্টা হবে / Upload failed — will retry"; capture kept | Client queues capture (§8 of `05-app-tasks.md`); presign retry |
| 01 job runner down | REST reads/writes validate + reserve | Longer processing waits (honest copy) | Jobs DB-persisted; runner restart resumes; dead-letter path unchanged |
| 06 push down | Full in-app flows | No push; polling + lists reveal state | 06 retries its queue |
| Neon degraded | Nothing AI-side (source of truth) | Errors on read/write | 01/15 runbooks: pool alarm, failover; jobs resume after recovery |
| FastAPI adapter (later) unhealthy | Interface falls back per config or fails identically to I-8 | Same as DeepSeek-down | Compose restart; DeepSeek-direct config switch if prolonged |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `AIH-UT-007` | Adapter retry ladder: timeout → ×2 backoff → `ErrAIUnavailable`; malformed → repair-once → `ErrMalformedOutput` | Unit | BR-014 / §5 retry table |
| `AIH-UT-008` | Breaker guard: cap check reads ledger sum + Redis flag; tripped guard blocks generation before enqueue | Unit | BR-012 |
| `AIH-IT-001` | Quota enforcement: 5th practice gen allowed, 6th → `QUOTA_EXCEEDED`; Pro flag → unlimited; quota re-checked at job start | Integration | BR-002/003 |
| `AIH-IT-005` | Malformed-output retry: repair succeeds once; twice → job FAILED + quota refunded (compensating job) | Integration | BR-014 / AIH-BE-025 |
| `AIH-IT-007` | Cost ledger written per call (scan/mcq_gen/classify): count, tokens_in/out, cost_usd, model | Integration | BR-011 |
| `AIH-IT-002` | Cross-tenant archive read denied (`TENANT_MISMATCH`/404) incl. shared-scope search | Integration | BR-007 |
| `AIH-IT-003` | Unverified blocked with `NOT_VERIFIED` on every `/ai` route | Integration | BR-001 |
| `AIH-IT-010` | Breaker trip: generation refused + banner flag set + jobs queued; resets after boundary | Integration | BR-012 |
| `AIH-IT-012` | 06 seam: scan READY / test publish call push dispatch with correct deep-link payload (06 stubbed) | Integration | I-5 contract |
| `AIH-IT-013` | 09 seam: `AttemptStats` scoped to section+week; foreign section → `FORBIDDEN`; aggregates only (no student identities) | Integration | I-6 contract |
| `AIH-IT-014` | FastAPI adapter contract (when built): same schemas over internal HTTP; malformed internal responses rejected like external | Integration | I-9 / §7 |
| `AIH-E2E-001` | Maestro: scan → upload → processing copy → tags ready on detail (bn) | Maestro (app) | US-001 golden path |
| `AIH-E2E-002` | Maestro: generate practice test → take → submit → graded result with explanations | Maestro (app) | US-005/006/007 golden path |

## 10. Task Checklist

- [ ] `AIH-INT-001` Implement `AIService` interface + DeepSeek adapter (model IDs in config, timeouts 30/60 s, retry ×2, schema validation, versioned prompt registry)
- [ ] `AIH-INT-002` Consume 05 `media.PresignUpload`/`ConfirmUpload` for scan images (no local upload path)
- [ ] `AIH-INT-003` Register jobs with 01 runner (scan-tagging, mcq-generation, quota-refund hook, daily cost guard) + dead-letter → refund wiring
- [ ] `AIH-INT-004` Wire 06 push on `scan_ready` + `class_test` (payload = ids + type, deep links per `05-app-tasks.md` §1)
- [ ] `AIH-INT-005` Consume 03 verified gate + locale + plan flag (fail-closed free limits)
- [ ] `AIH-INT-006` Consume 04 `hierarchy.ResolveUserNodes` (teacher sections, archive school scope)
- [ ] `AIH-INT-007` Export `ai.ClassifyChatQueries`, `ai.QuotaState`, `analytics.AttemptStats` for 09 + `cost-report` endpoint for 07; verify 07/09 handoff (`AIH-FE-001/002`)
- [ ] `AIH-INT-008` Daily cost circuit breaker: Redis flag `ai:breaker:state` + ledger sum + banner copy (bn/en) + reset job
- [ ] `AIH-INT-009` Cache-tag contract live (`ai:usage:{userId}`, `ai:tags:school:{id}`) + app query keys aligned
- [ ] `AIH-INT-010` AI output JSON schemas versioned + embedded contract version in `questions_snapshot`; FastAPI adapter contract documented for the later swap (`AI_PROVIDER` switch)
- [ ] `AIH-INT-011` Failure-matrix drills scripted in CI smoke (DeepSeek stub down, breaker trip, runner kill)
- [ ] `AIH-INT-012` Tests `AIH-UT-007/008`, `AIH-IT-001`–`014`, `AIH-E2E-001/002` green in CI
