# Command Center Web — Integration Tasks

**Module:** `07-command-center-web` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `03-identity-access` | we call them | REST via generated client: session auth (cookie + CSRF), `GET /verification-requests`, `POST …/{id}/approve\|reject`, `GET /institution/users`, additive export `verification.PendingCount(schoolID)` | fatal to portal routes (no unauthenticated portal); queue screen degrades to error state |
| I-2 | `04-organization-hierarchy` | we call them | REST via generated client: `POST/PATCH /admin/schools`, `POST /admin/cities`, picker reads, `POST /institution/sections*`, migration create/get/commit; additive exports `hierarchy.PlatformCounts()` / `hierarchy.SchoolCounts(schoolID)` | degraded — dashboard card shows partial flag; wizard blocks with error + retry |
| I-3 | `05-communication-engine` | we call them | REST via generated client: `GET/POST /notices`, `PATCH /notices/{id}/pin`, `DELETE /notices/{id}`, media #19/#20, custom-group approval endpoints (its §2 web-seam note: `/institution/clubs`); additive export `chat.NoticeStats(schoolID)` | degraded — composer/board/clubs show API error; nothing else affected |
| I-4 | `01-foundations` | we call them | generated contract code, `/healthz`, `audit.Record` (called by our api services), `audit_log` scoped-list queries surfaced at `GET /admin/audit-log` | audit failure aborts the wrapped action (01 I-3); viewer shows error state |
| I-5 | `11-campus-commerce`, `13-b2b-ads-events` | they call us | exported Go service functions `leads.Create`-shaped REST + `vendors.Approve` (see §2) + `GET /admin/stats` reads | our outage blocks vendor onboarding (11) — fatal to that path only |
| I-6 | `02-design-system` | we consume | tokens, web primitives, `LocaleProvider`/`t()`; namespace whitelist extended with `landing`/`school`/`vendor` (additive, parity-gated) | build-time fatal if missing; runtime bn fallback |

## 2. Exported Contract

```text
REST (OpenAPI-generated, consumed by module 11 and future dashboards):
  POST   /api/v1/leads                          # public create (rate-limit class `leads`)
  POST   /api/v1/vendor/register                # public inquiry → lead + pending vendor_accounts
  GET    /api/v1/admin/leads                    # Super Admin pipeline
  PATCH  /api/v1/admin/leads/{id}               # status transition
  GET    /api/v1/admin/vendors                  # Super Admin queue
  PATCH  /api/v1/admin/vendors/{id}/approve|reject|suspend
  GET    /api/v1/admin/stats · /api/v1/school/stats · /api/v1/admin/audit-log
Go exports (in-process, for api-side consumers):
  leads.Create(ctx, in LeadInput) (LeadDTO, error)
  vendors.Approve(ctx, actor Principal, vendorID uuid) (VendorAccountDTO, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `leads.Create` | module 11 (storefront signup reuses lead capture), 13 (campaign inquiry funnel) | `LeadDTO{id, type, status}` | `VALIDATION_FAILED`, `RATE_LIMITED` | Status forced `new`; source allowlisted |
| `vendors.Approve` (family: Reject/Suspend) | module 11 (admin surfaces it inside its vendor screens later) | `VendorAccountDTO` | `CONFLICT`, `VALIDATION_FAILED` (reason) | Audit-logged; only path that flips vendor status |
| `GET /admin/stats` | modules 11/12 dashboards later read their own exports; this endpoint stays the platform roll-up | `AdminStatsDTO` | `FORBIDDEN` | Revenue block stays a placeholder flag until 11/12 ship |
| `GET /vendor/state` (implicit via session + vendor lookup) | module 11 portal shell | vendor status + reason | `NOT_FOUND` | Keeps `/vendor` shell honest about access |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `auth.Authenticate` chain + session cookies + CSRF (web auth model) | 03 | Portal routes redirect to `/login`; api errors `UNAUTHENTICATED` |
| `GET /verification-requests`, `POST …/approve\|reject`, `GET /institution/users`, additive `verification.PendingCount(schoolID)` | 03 | Queue shows error state + retry; dashboard card partial flag |
| `POST/PATCH /admin/schools`, `POST /admin/cities`, picker reads (`GET /hierarchy/cities…`), `POST /institution/sections*`, `POST /institution/migrations*`, additive `hierarchy.PlatformCounts()/SchoolCounts(schoolID)` | 04 | Wizard blocked with mapped error (`CONFLICT` → field copy); stats partial |
| `GET/POST /notices`, `PATCH …/pin`, `DELETE /notices/{id}`, `POST /media/upload-url`, `POST /media/{id}/confirm`, custom-group approval endpoints, additive `chat.NoticeStats(schoolID)` | 05 | Composer/board/clubs degrade per §8; attachment retry |
| `audit.Record`, `audit_log` scoped lists, `/healthz`, error envelope + `X-Request-Id`, `leads` limiter class | 01 | Audit failure aborts the destructive action (by design) |

Additive note: the three count exports (`verification.PendingCount`, `hierarchy.PlatformCounts`/
`SchoolCounts`, `chat.NoticeStats`) are declared here so 03/04/05 include them in their Phase-1
build; until they exist, `GET /institution/stats` serves partial payloads with per-source flags
(`WEB-UT-005`), and queue/dashboard counts fall back to the existing list endpoints' metadata.

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Landing/download content deploy or copy change | `landing:content` |
| `POST/PATCH /admin/schools`, `POST /admin/cities` (04 mutations via our screens) | `admin:tenants`, `admin:stats`, `hierarchy:*` (04's tags) |
| Vendor approve/reject/suspend | `admin:vendors`, `admin:stats`, `vendor:state:{id}` |
| Lead status change | `admin:leads`, `admin:stats` |
| Notice publish/pin/delete (05 mutations via our screens) | 05's `notices:school:{id}` / `notices:section:{id}` + `school:{id}:stats` |
| Verification approve/reject (03 mutations via our screens) | `verification:queue:{schoolId}` (03's tag) + `school:{id}:stats` |
| Section create/archive; migration commit (04) | `hierarchy:school:{id}` (04's tag) + `school:{id}:stats` |

| Read | Tagged with |
| --- | --- |
| `/` + `/download` (ISR) | `landing:content` |
| `/admin/tenants`, `/admin/cities` | `admin:tenants` (no-store at the api; tag governs client routers) |
| `/admin/leads`, `/admin/vendors` | `admin:leads` · `admin:vendors` |
| `/admin/audit` | none (no-store, read-only viewer) |
| `/school` dashboard | `school:{id}:stats` |
| `/institution/notices*` | 05's `notices:*` tags (shared, never duplicated) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| None direct — N/A | — | — | — | — | The web app touches no external system: R2 (05), FCM (06), SMS/SSO (03), gateways (12) are all owned api-side; web reaches them only through `/api/v1/*` |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Pilot form / vendor inquiry | `POST /leads` · `POST /vendor/register` | §2 public create; `RATE_LIMITED` copy on flood |
| ROI calculator | none (client-side) | Deterministic formula; no api call, no tracking of values |
| `/download` buttons | `POST /leads` (`download_click`, beacon) | Fire-and-forget; never blocks navigation |
| Admin dashboard | `GET /admin/stats` | Placeholder flags for revenue (`WEB-BR-009`) |
| Create-school wizard | `GET /hierarchy/cities` → `POST /admin/schools` | 04 contract; `CONFLICT` → `hierarchy.school.name_duplicate` |
| Cities | `GET /hierarchy/cities` (admin variant) → `POST /admin/cities` | 04 contract |
| Vendor queue | `GET /admin/vendors` → `PATCH /admin/vendors/{id}/approve\|reject\|suspend` | §2 lifecycle; reason required on reject/suspend |
| Leads pipeline | `GET /admin/leads` → `PATCH /admin/leads/{id}` | Transition table enforced both sides |
| Audit viewer | `GET /admin/audit-log` | Read-only pages + filters |
| School dashboard | `GET /institution/stats` | Partial-payload flags |
| Verification queue | `GET /verification-requests` → `POST …/approve\|reject` + `GET /institution/users` | 03 contract; SLA from 03 data |
| Notice composer/board | `POST /notices`, `PATCH /notices/{id}/pin`, `DELETE /notices/{id}`, `GET /notices`, media #19/#20 | 05 contract; bn-first assembled body |
| Clubs queue | 05 custom-group approval endpoints (its §2 web-seam note) | Approve → creator owner |
| Sections manager | `POST /institution/sections`, `PATCH /institution/sections/{id}` | 04 contract |
| Migration wizard | `POST /institution/migrations` (dryRun true→false) → `POST …/commit` → `GET /institution/migrations/{id}` poll | 04 contract; commit only from PREVIEWED, zero ERROR |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. This module's additions to the shared
surface are additive: new paths (#1–#9), the `leads` rate-limit class, the three count exports and
the `landing`/`school`/`vendor` catalog namespaces. The namespace whitelist extension is agreed
with module 02 and keeps its parity gate (`DSN-UT-001`) green; any removal/rename later requires an
ADR plus migration notes in consumer modules' `07-progress.md`.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| api down entirely | Landing + `/download` (static/ISR), locale toggle, ROI calculator (client-side) | Portals: error boundary with retry + request id; lead submit: retry-safe, input kept, offline notice | Lead form resubmits; portals refetch on retry |
| 03 auth/verification down | Public pages; logged-in portals render chrome, data calls fail | Login impossible → clear outage copy; queue error state | Auto when 03 returns |
| 04 hierarchy/tenant down | Dashboards minus counts (partial flags); notices/clubs unaffected | Wizard/cities/sections blocked with mapped errors | Wizard state preserved; refetch on retry |
| 05 notices/media down | Dashboards, queue, tenants, migration | Composer publish blocked (attachment retry copy); board stale-marked; clubs error state | Notices refetch; upload retry |
| 01 audit failure mid-decision | Reads all fine | Decision **aborts** with error (no un-audited commit) | Actor retries after ops alert — by design (01 I-3) |
| R2 down (via 05 presign) | Text-only notices still publishable | Attachment chip shows failed + retry | Upload retry; cleanup job reaps orphans |
| Neon cold start | Static pages | Slower first portal load (skeletons) | Warm-up ping (module 15); caches soften reads |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `WEB-UT-001` | Lead form validation + ROI formula correctness against fixture inputs (both locales' messages) | Unit (Vitest) | shared zod schemas + `WEB-BR-002` |
| `WEB-UT-002` | Lead-status dropdown exposes only legal transitions; optimistic rollback on error | Unit | INV-001 mirror |
| `WEB-IT-001` | Route Handlers reject unauthenticated mutations; CSRF header required; role gate per portal route | Integration (web) | `WEB-BR-001`/`WEB-BR-008` |
| `WEB-IT-002` | Server-side re-validation: tampered client payload (status/source spoof) refused with field errors | Integration | `WEB-BR-003`/`WEB-BR-004` |
| `WEB-IT-003` | Middleware redirect + post-login return path for `/admin`, `/school`, `/vendor` | Integration | `WEB-BR-001` |
| `WEB-E2E-001` | Landing funnel: bn default → switch EN → fill ROI calculator → submit pilot form → success panel; axe clean | Playwright + axe | US-001/002/003, golden path |
| `WEB-E2E-002` | Admin: login → `/admin` dashboard → approve vendor (and reject-with-reject-reason path) → audit entry visible in viewer | Playwright | US-006/009/011, `WEB-BR-007` |
| `WEB-E2E-003` | School admin: login → dashboard cards → compose bn+en notice with section scope → preview → publish → pinned-first board | Playwright | US-012/014, `WEB-BR-010` |
| `WEB-E2E-004` | Migration: dry-run with a seeded ERROR item → commit disabled → clean run (fixture swap) → commit → status page COMMITTED | Playwright | US-015, `WEB-BR-011` |
| `WEB-E2E-005` | Verification queue: approve one request, reject another with reason, SLA badge renders from fixture dates | Playwright | US-013, `WEB-BR-013` |
| `WEB-E2E-006` | Degradation drill: api route handler stubbed 503 → landing still serves, portal error boundary + retry works | Playwright | §8 matrix |

## 10. Task Checklist

- [ ] `WEB-INT-001` OpenAPI paths #1–#9 + schemas merged; Go + TS clients regenerated (CI drift green)
- [ ] `WEB-INT-002` `leads` rate-limit class registered on 01's limiter (Redis + DB fallback)
- [ ] `WEB-INT-003` Additive count exports agreed + merged with 03/04/05; `GET /institution/stats` partial-flag fallback in place until merged
- [ ] `WEB-INT-004` Catalog namespaces `landing`/`school`/`vendor` added with 02; parity gate green
- [ ] `WEB-INT-005` Middleware + role layouts + CSRF wiring against 03 sessions
- [ ] `WEB-INT-006` Cache tags (`landing:content`, `admin:*`, `school:{id}:stats`) + revalidation wired per §4
- [ ] `WEB-INT-007` `/admin/audit-log` endpoint over 01's scoped list queries (read-only)
- [ ] `WEB-INT-008` `leads.Create`/`vendors.Approve` exports compiled against module 11's consumer stubs
- [ ] `WEB-INT-009` Failure-matrix drill (api 503 stub) scripted in CI
- [ ] `WEB-INT-010` Tests `WEB-UT-001`–`002`, `WEB-IT-001`–`003`, `WEB-E2E-001`–`006` green in CI (Playwright + axe)
