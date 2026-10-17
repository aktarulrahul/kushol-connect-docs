# Tuition Marketplace — Integration Tasks

**Module:** `10-tuition-marketplace` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `01-foundations` | we call them | `jobs.Enqueue` (matching, expiry, SLA reminder) + `audit.Record` (decisions, admin close, accept/fee fact) | degraded — jobs delayed (idempotent catch-up); audit retried inline, never blocks the decision |
| I-2 | `03-identity-access` | they gate us | `auth.RequireVerified` on every participatory route + `users` identity/claims | fatal by design — writes refused `NOT_VERIFIED` (the gate is the feature) |
| I-3 | `04-organization-hierarchy` | we call them | `hierarchy.ResolveUserNodes(userId)` (poster school context) + section/class-level catalog | degraded — matching job retries; requirement stays `open`; never posts without tenant context (refuse + retry) |
| I-4 | `05-communication-engine` | we call them | `chat` DM open (same-school) + `message_requests` (cross-school negotiation) · `media.PresignUpload`/`ConfirmUpload` (evidence, photos) | degraded — negotiation blocked with retry message; matches intact; evidence upload resumable |
| I-5 | `06-notifications` | we call them | `notify.SendToUser` (match/interest/decision/expiry notices) / `BroadcastTopic` (future area digests) | degraded, never fatal — **matches are created regardless**; 06 owns its retry queue |
| I-6 | `07-command-center-web` | they host nav, we own screens | `/institution/tutors`, `/institution/tutors/[id]`, `/institution/tuitions` call REST #2/#3/#8–#10 via the generated client | degraded — queue shows API error; admin actions retried |
| I-7 | `12-payments` (future) | they will call us | consume the accepted-match DUE fact (INV-8) — additive export when 12 lands (`TODO: Confirm` fee model first) | n/a — out of scope until Phase 3 |
| I-8 | app/web clients | they call us | REST `/api/v1/tuition|school/*` via generated `openapi-fetch`/oapi clients | fatal to the feature surface (standard API errors) |
| I-9 | api → app pushes | we notify | via I-5; deep links `tuition_match` / `tuition_interest` / `tuition_verification` (ids + labels only) | degraded — in-app lists still authoritative |

## 2. Exported Contract

```text
tuition.CreateRequirement(poster ActorClaims, in RequirementInput) (RequirementDTO, error)
tuition.NotifyMatches(requirementID uuid) (MatchResultDTO, error)   // job entry — 01 worker calls this
tuition.VerifiedTutorCount(schoolID uuid) (int, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `tuition.CreateRequirement(poster, in)` | REST #1 handler (app/web) | `RequirementDTO` (`open`, `expiresAt`) | `NOT_VERIFIED`, `VALIDATION_FAILED` | Enqueues the `tuition.match` job; no inline matching |
| `tuition.NotifyMatches(requirementID)` | 01 job worker (`tuition.match`); future: re-match admin tool | `MatchResultDTO{notified, skipped}` | `NOT_FOUND`, `CONFLICT` (requirement not open) | Idempotent — UNIQUE pair + `ON CONFLICT DO NOTHING`; pushes via 06 are best-effort |
| `tuition.VerifiedTutorCount(schoolID)` | 07 landing/dashboard stats (later) | `int` | `NOT_FOUND` (unknown school) | Cached 600 s under `tuition:tutorcount:{schoolId}`; platform-level profiles excluded per OQ-4 default |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `auth.RequireVerified` / role + tenant claims | 03 | Writes refused `NOT_VERIFIED`/`FORBIDDEN` — never bypassed |
| `users` identity lookups (poster/tutor/reviewer) | 03 | `NOT_FOUND` propagated; no cached identity past 30 s |
| `hierarchy.ResolveUserNodes(userId)` + class-level catalog | 04 | Matching job retries with backoff; requirement create refused `INTERNAL` rather than guessing tenant scope |
| `chat` DM open / `message_requests` (negotiation after accept) | 05 | Accept still commits; chat handle returned as `{pendingRequest}` state; client shows retry copy — matches intact |
| `media.PresignUpload` / `ConfirmUpload` (evidence, profile photo) | 05 | Upload blocked → profile stays `draft`; queue shows degraded placeholder; resumable |
| `notify.SendToUser` / `BroadcastTopic` | 06 | Log + continue — match/decision state is DB-first; 06 retries delivery |
| `jobs.Enqueue` + worker runtime, `audit.Record` | 01 | Enqueue failure → `INTERNAL` on create (requirement not silently unmatched); audit retried inline |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Verification approve/reject | `tuition:tutors:{area}` (tutor's area) · `tuition:tutor:{id}` · `tuition:tutorcount:{schoolId}` |
| Tutor profile edit / suspend | `tuition:tutor:{id}` · `tuition:tutors:{area}` · `tuition:tutorcount:{schoolId}` |
| Requirement create/edit/close/match | none (per-user reads; matches never page-cached) |

| Read | Tagged with |
| --- | --- |
| `GET /tuition/tutors?area=` (server cache, TTL 120 s) | `tuition:tutors:{area}` |
| `GET /tuition/tutors/{id}` (server cache, TTL 300 s) | `tuition:tutor:{id}` |
| `tuition.VerifiedTutorCount` (TTL 600 s) | `tuition:tutorcount:{schoolId}` |
| My requirements / my matches / queues | never cached (per-user + admin-fresh) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| (none directly) | — | — | — | — | All externals are reached **through module owners**: R2 via 05 media, FCM via 06 push, rate-limit Redis via 01 base |
| Cloudflare R2 (indirect via 05) | S3 presigned PUT/GET | 05-owned `R2_*` env | 05-owned | 05-owned | Evidence/photo upload blocked; profiles stay `draft`; queue placeholders |
| FCM (indirect via 06) | HTTPS Admin SDK | 06-owned `FCM_SERVER_KEY` | 06-owned | 06-owned queue | No push; matches + in-app lists unaffected |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Wizard submit (app) | `POST /tuition/requirements` | `{data:{requirement}}`; offline queue replays once; `VALIDATION_FAILED` fields mapped to steps |
| My requirements / detail | `GET /tuition/requirements` · `GET /tuition/requirements/{id}/matches` | Poster-only rows; interested tutors public-safe + badge |
| Accept dialog | `POST /tuition/matches/{id}/accept` | Returns `{match, contact, chat:{dmGroupId\|messageRequestId}}`; `CONFLICT` → "already matched" toast |
| Interest CTA (tutor) | `POST /tuition/matches/{id}/interest` | `CONFLICT` on closed/expired/matched; optimistic chip rollback on failure |
| Browse / profile | `GET /tuition/tutors` · `GET /tuition/tutors/{id}` | Public-safe DTO; contact fields `null` pre-accept (INV-4) |
| Tutor setup + evidence | `POST /tuition/tutor-profile` · `POST /tuition/tutor-profile/submit-for-review` (+ 05 media flow) | Draft-safe; tracker reads status from profile |
| Verification queue (web) | `GET /institution/tutor-verifications` · `POST /institution/tutor-verifications/{id}/approve|reject` | Reviewer-scoped; reject requires `decisionNote`; evidence via 05 media URLs |
| Oversight (web) | `GET /tuition/requirements` (School Admin role) · `PATCH /tuition/requirements/{id}` (close) | Read-only except close; audit note stored |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. The public-safe tutor DTO (contact-null
rule, INV-4) and the accept response (`contact` + `chat` handle) are frozen contracts the app
renders against; additions (e.g. ratings, premium fields) are additive. Deep-link payload types
(`tuition_match` / `tuition_interest` / `tuition_verification`) are declared here and owned with
module 06 — unknown payload types are ignored by clients.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 06 notifications / FCM | Requirement posts, matching, match rows, accept/decline, browse | No pushes; lists still show fresh states in-app | 06's queue delivers on restore; nothing lost (DB-first) |
| 05 communication-engine | Posts, matching, interest, accept (commit + reveal) | "চ্যাট এখন অনুপলব্ধ — আবার চেষ্টা করুন / Chat unavailable — try again" on the chat hand-off; evidence upload blocked | Chat opens on retry once 05 returns; matches intact; uploads resumable |
| 01 jobs worker | All REST reads/writes | Matches arrive late (≤ worker lag); expiry delayed | Queued jobs run idempotently on recovery; alarm after 3 failures |
| 04 hierarchy | Nothing that needs tenant context (by design) | Requirement create refused with retry copy; no tenant-guessing | Job/retry once `ResolveUserNodes` answers |
| R2 (via 05) | Text flows, matching, decisions on complete evidence | Degraded evidence placeholder; photo/evidence upload errors | Resumable uploads; reviewer blocked only for incomplete items |
| Redis | Everything (DB source of truth) | Browse slower (cache bypass); limits fall back to safe defaults | Tags rebuild on return |
| Neon (Postgres) degraded | Nothing marketplace-side | Errors on writes/reads | 01/15 runbooks: pool alarm, failover path |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `TUT-UT-010` | Tag invalidation set of approve/reject/profile-edit covers `tuition:tutors:{area}` + `tuition:tutor:{id}` + count key | Unit | §4 contract |
| `TUT-UT-011` | Push payload builder emits ids + labels only (no contact, no evidence refs) | Unit | BR-007 privacy |
| `TUT-IT-011` | Match-query correctness end-to-end: subject + radius + verified filters (suspended/unverified/out-of-radius excluded) — seeded Postgres | Integration | BR-002/003 |
| `TUT-IT-012` | Contact reveal across **both** API shapes: browse/detail payload `null` until accepted; accept unlocks contact for the accepted pair only (poster + tutor DTOs) | Integration | BR-006 / INV-4 |
| `TUT-IT-013` | Cross-tenant queue access denied: School Admin B sees nothing of school A's verifications/requirements; platform rows invisible to school admins | Integration | BR-013 / INV-6 |
| `TUT-IT-014` | Unverified poster/tutor blocked (`NOT_VERIFIED`) at every participatory seam | Integration | BR-001 |
| `TUT-IT-015` | Expiry job: stale requirement → `expired` (+ matches, + poster notice); idempotent re-run | Integration | BR-008 |
| `TUT-IT-016` | Evidence visibility: media handles resolve only for routed reviewer + owner; absent from browse/detail/cache payloads | Integration | BR-011 / INV-6 |
| `TUT-IT-017` | 06 down (stub errors): matches still created; pushes queued for retry; accept flow unaffected | Integration | I-5 degraded-not-fatal |
| `TUT-E2E-001` | Maestro: guardian posts requirement → (seeded tutor) receives match → expresses interest → guardian accepts → chat opens (05 DM) with contact revealed | Maestro (app) | US-001/005/006/007 golden path |

## 10. Task Checklist

- [x] `TUT-INT-001` Implement + export `tuition.CreateRequirement` (verified gate + job enqueue) — 2026-10-03 (verified gate + `tuition.match` enqueue)
- [x] `TUT-INT-002` Implement + export `tuition.NotifyMatches` and register the `tuition.match` job on the 01 worker — 2026-10-03 (registered on the 01 worker in cmd/api)
- [x] `TUT-INT-003` Implement + export `tuition.VerifiedTutorCount` (+ cache key) with the 07 handoff note — 2026-10-03 (`tuition:tutorcount:{schoolId}` tag helper; read-through cache lands with traffic)
- [x] `TUT-INT-004` Consume `hierarchy.ResolveUserNodes` for tenant context (refuse-and-retry, never guess) — 2026-10-03 (refuse-and-retry — never guesses tenant scope)
- [x] `TUT-INT-005` Wire the accept → 05 seam (same-school DM / cross-school Message Request) incl. degraded chat state — 2026-10-03 (same-school DM / cross-school Message Request; degraded `{pending:true}` handle)
- [x] `TUT-INT-006` Wire evidence/photo uploads through `media.PresignUpload`/`ConfirmUpload` — 2026-10-03 (evidence media refs validated at submit; 05 flow wired app-side at Stage 5 review — G-2)
- [x] `TUT-INT-007` 06 notification templates + deep-link payloads (`tuition_match`/`tuition_interest`/`tuition_verification`) — 2026-10-03 (additive push types in 06's frozen builder; deep links + bn/en copy in the api catalog)
- [x] `TUT-INT-008` Register `tuition.expiry` + `tuition.verification-reminder` jobs — 2026-10-03 (`tuition.expiry` + `tuition.verification-reminder` registered)
- [x] `TUT-INT-009` Audit events (approve/reject, admin close, accept/fee fact) on `audit.Record` — 2026-10-03 (approve/reject, admin close, accept + fee-DUE fact on `audit.Record` — best-effort tx)
- [x] `TUT-INT-010` Cache tags `tuition:tutors:{area}` / `tuition:tutor:{id}` / count key + invalidations — 2026-10-03 (`bustTutorTags` invalidation set — UT-010; wired via the shared tag cache)
- [x] `TUT-INT-011` Failure-matrix drills (06-down stub, 05-down stub, worker lag) in CI smoke — 2026-10-03 (06-down/05-down degradation proven with fakes in the IT file — runs pending owner)
- [x] `TUT-INT-012` Tests `TUT-UT-010`–`011`, `TUT-IT-011`–`017`, `TUT-E2E-001` green in CI — 2026-10-03 (UT green `-race`; IT + Maestro written — **runs pending owner**, G-6/G-1)

### Additions from the 2026-10-04 marketplace build (integration pass owns these)

- Web surfaces `/tuition`, `/tuition/post`, `/tuition/register` run on `fixtures/tuition-market.ts`
  — swap to the generated client when the contracts below land.
- Additive OpenAPI: tuition **requirements without an institution FK** (poster name/phone,
  subject, class level, area, sessions/week, budget), **tutor registrations** (user-linked,
  subject/class levels/area), **matching + tutor notification** (06 push type `tuition.match`
  already exists — fire it on match), **interview calls** (`mode: in_person | online`, slot,
  venue/meeting link), **tutor ratings** (1–5, unique per rater per session).
- Keep the institution-side P0 (verification queue, oversight) untouched — it is consumed by
  school admins at `/institution/tuitions` and platform admins via the marketplace page's arrange flow.
