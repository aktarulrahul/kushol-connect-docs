# Command Center Web — Technical Document

**Module:** `07-command-center-web` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Compressed from this folder's spec set — `01-user-stories.md` · `02-solution-approach.md` · `03-backend-tasks.md` · `04-frontend-tasks.md` · `05-app-tasks.md` · `06-integration-tasks.md`. On any drift, the spec files win.

---

## 1. Overview

### 1.1 Purpose

Ships the web surface of Kushol Connect: the public B2B funnel — bilingual landing (bn default, `WEB-US-001`), ROI calculator (`WEB-US-002`), pilot and vendor-inquiry leads (`WEB-US-003/004`), `/download` (`WEB-US-005`) — plus the Command Center portals: Super Admin `/admin`, School Admin `/school` and the gated `/vendor` shell. Converts the zero-CAC funnel of `brd.md` §2 Goal 1 and the dashboard duties of `prd.md` §4A into working screens on top of modules 01–05 contracts.

### 1.2 Scope

**In:** landing sections + ROI calculator + SEO suite (per-locale Metadata, OG, JSON-LD Organization, sitemap, robots) under CWV budgets; `/download` with flag-gated placeholders; `/admin` dashboard, tenants + create-school wizard, cities, vendor approvals, leads pipeline, campaigns stub, audit viewer; `/school` dashboard, verification queue, notice composer + board, clubs, sections, migration wizard; `/vendor` shell; api-side `landing_leads` + `vendor_accounts` tables, endpoints #1–#9 (`03` §2), route-guard middleware + per-role layouts, the `leads` rate-limit class.

**Out:** `/login` screen (module 03 — 07 only gates shells behind it); roster CSV upload screen (module 14; `/school/roster` stub only); ledger / AI Matrix / tutor / webhook screens (modules 12/09/10/14 — stubs); vendor portal screens (11) and campaign moderation logic (13); revenue/fee data (11/12 — placeholder empty states); chat/notice fan-out (05/06).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations | generated client, `/healthz`, `audit.Record`, scoped `audit_log` reads, error envelope + `X-Request-Id`, limiter base for the `leads` class |
| consumes | 02 design-system | tokens, web primitives, `LocaleProvider`/`t()`; namespace whitelist extended with `landing`/`school`/`vendor` (additive, parity-gated) |
| consumes | 03 identity-access | session auth (cookie + CSRF), `/login`, verification queue + `GET /school/users`, additive `verification.PendingCount(schoolID)` |
| consumes | 04 organization-hierarchy | `POST/PATCH /admin/schools`, `POST /admin/cities`, picker reads, sections CRUD, migration create/get/commit, `hierarchy.PlatformCounts()/SchoolCounts()` |
| consumes | 05 communication-engine | notices CRUD/pin, media presign/confirm, custom-group approval, additive `chat.NoticeStats(schoolID)` |
| consumed by | 11 campus-commerce | `leads.Create`, `vendors.Approve` family, `/vendor` state lookup |
| consumed by | 13 b2b-ads-events | lead-capture funnel (`leads.Create`); `/admin/campaigns` stub host |
| consumed by | 11/12 (later) | `GET /admin/stats` platform roll-up — revenue placeholder until their exports exist |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| Web framework | Next.js App Router, `output: "standalone"`, TypeScript strict | SEO-native landing + RSC portals behind a server auth gate (`02` §10 Option A; SPA rejected) | `tech-stack.md` web table |
| Styling / fonts | Tailwind CSS v4 `@theme` tokens · Hind Siliguri + Inter via `next/font` | brand tokens only from `packages/shared`; bn never rendered in Inter | light theme first; self-hosted `bengali`+`latin` subsets |
| Components | shadcn/ui on radix-ui | one visual API with module 02 primitives | hand-written into `src/components/ui/` |
| Data tables | TanStack Table + TanStack Query | keyboard-complete admin tables; client interactivity only where tables need it | ~12 kB gzip both, tree-shaken |
| Forms | react-hook-form + zod | shared schemas in `packages/shared` mirror the OpenAPI shapes | re-validated in every Route Handler |
| Testing (web) | Vitest + Testing Library · Playwright (+ axe) | golden paths + WCAG 2.2 AA gate | Lighthouse CI for CWV budgets |
| SEO | Metadata API, OG images, JSON-LD Organization, sitemap, robots | landing is the B2B acquisition funnel (`WEB-FE-008`) | per-locale |
| API (api side) | Go · chi handlers from OpenAPI 3.1 · sqlc + pgx · PostgreSQL (Neon) · Redis | spec-first; Go + TS clients regenerated (`WEB-BE-010`); `leads` rate-class counters | testcontainers-go for IT |

---

## 3. Architecture

### 3.1 Component diagram

```text
Visitor ──▶ / · /download (static + ISR, tag landing:content) · ROI calculator (client-side, ROI_ASSUMPTIONS)
Principal ─▶ PilotForm · Vendor ─▶ VendorInquiryForm ─┐
Super Admin ─▶ /admin/* · School Admin ─▶ /school/* ──┤ Route Handler / Server Action (zod re-validate, CSRF)
                                                      ▼ generated openapi-fetch client
                    applications/api (Go, chi): leads · vendors · stats · auditlog services
                    portal data via 03/04/05 exported services · audit.Record (01) when destructive
                                                      ▼
        PostgreSQL: landing_leads · vendor_accounts (+ 01/03/04/05 tables via their owners)
```

### 3.2 Boundary

**Owns (tables / services):** `landing_leads`, `vendor_accounts` + their endpoints and services (`leads`/`vendors`/`stats`/`auditlog`, `WEB-BE-001–009`); the web route tree, per-role layouts + middleware, `ROI_ASSUMPTIONS`, SEO suite, `landing`/`school`/`vendor` catalog namespaces.

**Reads (via exported service functions only):** 01 — `audit.Record`, scoped `audit_log` lists, error envelope, `/healthz`; 03 — session auth chain, verification endpoints, `verification.PendingCount`; 04 — schools/cities/pickers/sections/migrations, `PlatformCounts()/SchoolCounts()`; 05 — notices/media/club approval, `chat.NoticeStats`; 02 — tokens, primitives, `LocaleProvider`.

### 3.3 Request / data flows

```text
1. Landing (public):  visitor → static/ISR HTML (CDN, tag landing:content) → ROI runs client-side →
   PilotForm / VendorInquiryForm → Route Handler → openapi-fetch → POST /leads · /vendor/register
   → landing_leads(status=new) [+ vendor_accounts(pending), one tx]
2. Portal read:  session cookie → middleware presence check → role layout re-check → Server
   Component first paint → TanStack Query hydration → api (authenticate → claims → tenant-scope)
3. Portal mutation:  Server Action / Route Handler → zod re-validate → api with X-CSRF-Token →
   audit-logged when destructive → revalidateTag per 06 §4 (admin:*, school:{id}:stats, notices:*)
4. Migration wizard:  POST /school/migrations {dryRun:true} → DRAFT + per-item table →
   dryRun:false → PREVIEWED → commit → poll GET /school/migrations/{id} every 3 s → COMMITTED
5. Degradation:  api down → landing/download still serve; portals error boundary + retry +
   X-Request-Id; lead submit retry-safe with input preserved
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `landing_leads.status` | new · contacted · converted · archived | new → contacted → converted \| archived; `new` never re-entered (INV-001); Super Admin only, transition table, audit-logged |
| `vendor_accounts.status` | pending · approved · rejected · suspended | pending → approved / rejected(reason 10–500); approved ⇄ suspended(reason); re-approve from rejected/suspended (OQ-5 default); every decision audited |
| migration run (04-owned, wizard-driven) | DRAFT · PREVIEWED · COMMITTING · COMMITTED | DRAFT → PREVIEWED on zero-ERROR preview; PREVIEWED → COMMITTING → COMMITTED on commit; commit impossible with ERROR items; 5/hour/school |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `landing_leads` | Public funnel capture: `pilot_registration` \| `vendor_inquiry` \| `download_click` | platform-wide — public create-only (`WEB-BR-004`), Super Admin reads | `(status, created_at DESC)` · `(type, created_at DESC)` · `(city_id)` | status CHECK + service transition table; `vendor_account_id` set iff type=vendor_inquiry; source server-derived allowlist, utm captured + capped, never trusted from client |
| `vendor_accounts` | Vendor record with Super-Admin approval lifecycle | platform-wide — Super Admin lifecycle; module 11 reads after approval | `(status, created_at DESC)` · trgm `(company_name)` | reject/suspend require reason 10–500; `decided_by`/`decided_at`; `portal_user_id` linked later by module 11 |

Column detail stays in `03-backend-tasks.md` §1 (migrations `20261015090000_web_landing_leads`, `20261015091000_web_vendor_accounts`; fictional demo seed).

---

## 5. Contracts

### 5.1 REST endpoints

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST · `/api/v1/leads` | Public | Lead create (pilot / vendor / download_click) | `VALIDATION_FAILED` · `RATE_LIMITED` · `NOT_FOUND` | WEB-US-003/004/005 |
| 2 | POST · `/api/v1/vendor/register` | Public | Inquiry → lead + pending vendor account, one tx | as #1 | WEB-US-004 |
| 3 | GET · `/api/v1/admin/leads` | Super Admin | Pipeline list, `type`/`status` filter, cursor page | `FORBIDDEN` | WEB-US-010 |
| 4 | PATCH · `/api/v1/admin/leads/{id}` | Super Admin | Status transition (INV-001 table) | `CONFLICT` | WEB-US-010 |
| 5 | GET · `/api/v1/admin/vendors` | Super Admin | Vendor queue, status filter + trgm name search | `FORBIDDEN` | WEB-US-009 |
| 6 | PATCH · `/api/v1/admin/vendors/{id}/approve` · `…/reject` · `…/suspend` | Super Admin | Lifecycle decisions (reason on reject/suspend) | `CONFLICT` · `VALIDATION_FAILED` | WEB-US-009 |
| 7 | GET · `/api/v1/admin/stats` | Super Admin | Tenants/cities, leads by status/type, vendors pending, revenue placeholder flag | `FORBIDDEN` | WEB-US-006 |
| 8 | GET · `/api/v1/school/stats` | School Admin (claim-scoped) | Students/sections (04), pending verifications (03), notices 30 d (05) | `FORBIDDEN` · `TENANT_MISMATCH` | WEB-US-012 |
| 9 | GET · `/api/v1/admin/audit-log` | Super Admin | Read-only viewer over 01's `audit_log` | `FORBIDDEN` · `VALIDATION_FAILED` | WEB-US-011 |

Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` · `NOT_FOUND` · `CONFLICT` · `RATE_LIMITED` · `INTERNAL`. Rate-limit class `leads` on #1/#2 (10/h/IP, 3/min burst); default class elsewhere.

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| None — `WEB-BE-015` | — | Leads are worked manually in the pipeline in Phase 1 (OQ-6); no reminder/digest jobs | — | Any future SLA/reminder job is additive and must be declared in `03` §5 first |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `leads.Create(ctx, in LeadInput)` | module 11 (storefront signup), 13 (campaign funnel) | `LeadDTO{id, type, status}` | `VALIDATION_FAILED` · `RATE_LIMITED` — status forced `new`, source allowlisted |
| `vendors.Approve` (family: Reject/Suspend) | module 11 (admin surfaces inside vendor screens later) | `VendorAccountDTO` | `CONFLICT` · `VALIDATION_FAILED` (reason) — audit-logged; only path that flips vendor status |
| `GET /admin/stats` | modules 11/12 dashboards later | `AdminStatsDTO` | `FORBIDDEN` — revenue block stays a placeholder flag until 11/12 ship |
| `/vendor/state` (session + vendor lookup) | module 11 portal shell | vendor status + reason | `NOT_FOUND` — keeps the `/vendor` shell honest |

Exports return DTOs (never sqlc rows); admin-only exports require role claims; domain errors map to the RFC-7807 envelope at the handler.

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/` | Landing funnel — hero, For Schools + ROI calculator, For Vendors + inquiry, downloads, trust, footer; bn default + EN toggle | Static + ISR (`landing:content`) | Public |
| `/download` | App download — APK/TestFlight cards + QR placeholder, flag-gated links | Static + ISR | Public |
| `/login` | Sign-in (screen delivered by module 03; 07 gates shells behind it) | Dynamic | Public |
| `/admin` | Super Admin dashboard (`GET /admin/stats`, placeholder cards `WEB-BR-009`) | Dynamic | Super Admin |
| `/admin/tenants` | Tenants list (TanStack Table) | Dynamic | Super Admin |
| `/admin/tenants/new` | Create-school wizard — city → names → admin → review (`POST /admin/schools`) | Dynamic | Super Admin |
| `/admin/cities` | Cities management (`POST /admin/cities`) | Dynamic | Super Admin |
| `/admin/vendors` | Vendor approval queue — status tabs, detail drawer, ReasonDialog | Dynamic | Super Admin |
| `/admin/leads` | Leads pipeline — filters, legal-transition dropdown, optimistic update | Dynamic | Super Admin |
| `/admin/campaigns` | Campaign moderation stub ("ships in module 13") | Dynamic | Super Admin |
| `/admin/audit` | Audit log viewer — read-only, entity/action/school filters, pager | Dynamic | Super Admin |
| `/school` | School Admin dashboard — four StatCards, partial-payload flags | Dynamic | School Admin |
| `/school/users` | Verification queue — SLA badges (48 h amber / 72 h red), reject reason | Dynamic | School Admin |
| `/school/notices` | Notice board — pinned-first, pin/delete controls | Dynamic | School Admin |
| `/school/notices/new` | Notice composer — bn/en tabs, scope, pin, attachment (05 presign), preview, one-way banner | Dynamic | School Admin |
| `/school/clubs` · `/school/sections` | Club (custom group) approval queue (05) · sections manager create/archive + `CONFLICT` copy | Dynamic | School Admin |
| `/school/migrations` · `/new` · `/[id]` | Migration runs list · wizard (dry-run → review → commit) · status page (poll while COMMITTING) | Dynamic | School Admin |
| `/school/roster` · `/ledger` · `/matrix` · `/tutors` · `/webhooks` | Stubs → modules 14/12/09/10/14 | Dynamic | School Admin |
| `/vendor` | Vendor shell — pending / approved / rejected states from api | Dynamic | Vendor |
| `*` | Branded 404 + role-aware FORBIDDEN pages | Dynamic | All |

Bilingual bn/en everywhere (bn default), locale cookie persisted, `<html lang>` flips; motion per `04` §5 with reduced-motion variants; axe (WCAG 2.2 AA) gates every screen.

### 6.2 Mobile (detail in `05-app-tasks.md`)

N/A — module 07 covers `web` + `api` only (README row). App surfaces that consume this module's data (notices published by the composer, tenant/city picker entries, download links) belong to modules 03/05/06; no `WEB-AP-*` tasks exist. The generated OpenAPI client already covers `app` should it ever need lead/vendor paths.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| None direct — N/A | — | — | — | — | The web app touches no external system: R2 (05), FCM (06), SMS/SSO (03), payment gateways (12) are all owned api-side; web reaches them only through `/api/v1/*` (`06` §5) |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_API_URL` | Yes | `/api` (same-origin; Nginx on `kusholconnect.com` proxies `/api/*` → api) | generated `openapi-fetch` client base URL in the browser |
| `API_INTERNAL_URL` | Yes (server-only) | `http://api:8080` | Server Components / Route Handlers call the api over the Compose network, forwarding the session cookie |
| `NEXT_PUBLIC_SITE_URL` | Yes | `https://kusholconnect.com` | SEO suite — metadata, OG, JSON-LD, sitemap, robots |
| `NEXT_PUBLIC_DOWNLOAD_URLS_READY` | No | `false` | flag-gates `/download` links (`WEB-BR-012`) until module 15 publishes EAS URLs; `NEXT_PUBLIC_*` limited to site URL + this flag — no secrets in client bundles (`02` §6); no api-side env beyond module 01's shared config |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| *(Phase 1: none in-UI — dashboard/config surfaces come with modules 11–13; noted so scope does not creep)* | `ROI_ASSUMPTIONS` (minutes per notice / per fee student — single constant, `TODO: Confirm` values) |
| Launch-city flag filter is server config (04) surfaced in the admin cities list | `leads` rate limits (10/h/IP, 3/min burst) |
| Download URL readiness flag (`NEXT_PUBLIC_DOWNLOAD_URLS_READY`) | Route structure, role→layout mapping, middleware order |
| Contact email/phone in the footer (catalog keys, content change) | ROI formula shape; bn-first assembly of the notice body (`bn` + `—` + `en`) |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | Middleware checks session-cookie **presence only** for redirects (`WEB-BR-001`); every real decision runs api-side: authenticate → load role claims → tenant-scope (03 chain); mutations carry `X-CSRF-Token`; portal layouts re-check role claims per route group |
| Role matrix | Public: `/`, `/download`, POST leads + vendor-register. Super Admin: `/admin/*` (endpoints #3–#7, #9). School Admin: `/school/*` (#8, claim-scoped). Teacher: `/school/ai-matrix` only (own sections, module 09) — every other `/school/*` route returns `FORBIDDEN`. Vendor: `/vendor` shell gated on server status. Teacher/Student/Guardian: no portal |
| Tenant scope | School Admin screens send no `schoolId` — scope is claim-derived (`WEB-BR-008`); `landing_leads`/`vendor_accounts` are platform-wide (Super Admin reads); cross-tenant attempts → `TENANT_MISMATCH`/404 with request id |
| Rate limits | Class `leads` on `POST /leads` + `POST /vendor/register`: 10/h/IP, 3/min burst (Redis, DB fallback counters); default class on all other routes |
| Audit events | `vendor.approved` / `vendor.rejected` / `vendor.suspended` (actor, target, reason); `lead.status_changed`; destructive UI actions (school/city create, vendor decision, lead status, migration preview/commit) confirmed in UI naming the object and audit-logged api-side; audit failure aborts the action (01 I-3) |
| Privacy / minors | Lead data contact-minimal — no PII beyond submitted fields; utm/source derived server-side; audit viewer read-only (append-only, no mutation affordance); revenue/active-user figures never invented — explicit "connects in modules 11/12/13" empty states (`WEB-BR-009`) |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `VALIDATION_FAILED` | Per-field input rejection | All forms + Route Handlers (zod/OpenAPI parity, `01` §6 rules) | `fields` errors mapped to `validation.*` keys; input never lost |
| `RATE_LIMITED` | Public flood protection | `POST /leads` · `/vendor/register` (`leads` class) | Polite bn/en copy with cooldown; auto after window |
| `CONFLICT` | Stale row / illegal state | Illegal lead transition; vendor double decision; duplicate school/section name; archive with enrollments; run already committed | Row-level "refresh this row" copy; list auto-revalidates; field-mapped copy for `hierarchy.*.name_duplicate` |
| `TENANT_MISMATCH` (404 body) | Cross-tenant probe | Forged `schoolId`/`sectionId`; audit-log schoolId filter as School Admin (`WEB-IT-005`) | Nothing leaks; request id shown |
| `FORBIDDEN` | Wrong role | School Admin on admin routes; layout gate + api independently | Role-aware FORBIDDEN page + limited nav |
| `UNAUTHENTICATED` | No session | Protected endpoints #3–#9 | Middleware redirect `/login?next=…`, return path honoured |
| `NOT_FOUND` | Unknown/inactive resource | Bad city id on lead create; archived section refresh; unknown portal route | Branded bn/en 404 with "back to dashboard" |

All errors surface as RFC-7807 `application/problem+json`; user-visible messages resolve via `packages/shared` catalogs — every key ships in **bn + en** (Bengali default).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | api handlers slog JSON stdout with `X-Request-Id` (01 envelope); no PII beyond submitted lead fields; web error boundaries surface the request id for support |
| Metrics / counters | Leads by status/type, vendors by status, tenants/cities — the `stats` aggregates double as ops counters; `leads` rate-class trip counts |
| Health contribution | None module-specific — `/healthz` is 01's; landing + `/download` are static/ISR so an api outage never takes the funnel down |
| Jobs & retries | None owned (`WEB-BE-015` — manual pipeline in Phase 1) |
| Runbook pointers | api-503 degradation drill scripted in CI (`WEB-E2E-006`, `WEB-INT-009`); Neon cold-start warm-up ping (module 15); deploy/rollback per module 15 runbooks |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | api: lead validation parity, transition table, vendor lifecycle + atomic register, stats partial flags (`WEB-UT-001–005`, `03` §6) · web: form validation + ROI formula both locales, transition dropdown mirror (`WEB-UT-001–002`, `06` §9) | go test · Vitest |
| Integration | Rate class + auth chain, claim-scoped stats, audit atomicity, cross-tenant audit probe, seed idempotency (`03`); Route Handler CSRF/auth, server re-validation, middleware redirect (`06`) | `WEB-IT-001–006` · `WEB-IT-001–003` | testcontainers Postgres |
| E2E | Landing funnel (axe clean), admin vendor + audit, notice composer, migration wizard, verification queue, api-503 drill | `WEB-E2E-001–006` | Playwright + axe (WCAG 2.2 AA) |
| CI | — | — | `go test/vet/lint` (api) · `pnpm lint/typecheck/test/build` (web) · Lighthouse CWV on `/` + `/download` · catalog parity gate · mandatory: unauthenticated denied, cross-tenant `TENANT_MISMATCH`/404, publish guard blocks `TODO:`, public reads never return drafts |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot: 2–3 schools; public funnel reads dominate and are CDN-served; portal tables paged 25 |
| Hot paths + indexes | Admin pipeline queue `(status, created_at DESC)`; vendor trgm search; single-scan stats aggregates (`WEB-BE-013`) |
| Latency targets | CWV on 3G-fast: **LCP < 2.5 s** (static HTML, hero priority + AVIF/WebP), **CLS < 0.1** (reserved media boxes), **INP < 200 ms** (trivial calculator math, small hydration) |
| Bundle / payload impact | New deps: TanStack Table + TanStack Query ≈ 12 kB gzip total, nothing beyond module 02 primitives; no chart lib (Recharts belongs to 09/12); landing route ships no admin JS |
| Caching | `/` + `/download` static + ISR under tag `landing:content`; portals no-store (admin reads never cached); mutations revalidate tags per `06` §4; locale cookie read by RSC for first paint |

---

## 14. Risks & Open Questions

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | ROI time-saved assumptions (OQ-1) | Trust damage with principals | Rahul | Open — `TODO: Confirm` pre-launch | `minutesPerNotice = 4`, `minutesPerFeeStudent = 0.5`; estimate label + formula shown |
| 2 | Roster CSV format for the `/school/roster` stub tooltip (OQ-2) | Stub copy only | Rahul | Open | Portal-generated template (module 14); strict header validation, row-level error report |
| 3 | Final APK / TestFlight URLs (OQ-3) | Download funnel inert | Rahul | Open — `TODO: Confirm` at module 15 | Disabled placeholders; `NEXT_PUBLIC_DOWNLOAD_URLS_READY` false |
| 4 | Assembled bn-first notice body acceptable to 05/app? (OQ-4) | App readability | Rahul + 05 owner | Open | Assembled `bn\n\n—\nen`, fixed separator, per-part caps |
| 5 | Vendor reinstate path after suspension/rejection (OQ-5) | Lifecycle completeness | Rahul | Open | `PATCH …/approve` allowed again from `suspended`/`rejected`, audit-logged |
| 6 | Lead follow-up SLA / reminder jobs in Phase 1 (OQ-6) | Funnel worked slower | Rahul | Open | None — manual pipeline, no reminder jobs this module |
| 7 | 03/04/05 contracts + additive count exports land before 07 wiring (`02` §11 risks 1–2) | Portal screens stubbed; dashboard cards degrade | Rahul + 03/04/05 owners | Assumption / Open | Specs frozen at Phase-1 review; partial payloads with per-source flags; fallback to list-endpoint metadata |
| 8 | Vendor flow value depends on module 11 arriving; shared 2-vCPU VPS budget tight (`02` §11 risks 5–6) | Approved vendors sit in a shell; SSR latency spikes | Rahul / module 15 owner | Accepted | Shell explains roadmap, leads pipeline useful independently; static/ISR landing, paged tables, budgets tested in module 15 |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| §2 Goal 1 — zero-CAC funnel | §4A | WEB-US-001–005 | WEB-FE-001–008 · WEB-BE-001–004 · WEB-INT-001/002 | WEB-UT-001 · WEB-IT-001 · WEB-E2E-001 |
| BR-01 — school owns its data (migration) | §4A · §5.1 | WEB-US-015 | WEB-FE-024 · WEB-INT (04 migration endpoints) | WEB-E2E-004 |
| BR-04 — vendor accounts need approval | §4A | WEB-US-004 · WEB-US-009 | WEB-BE-002/005–006 · WEB-FE-006/013 | WEB-UT-003/004 · WEB-IT-004 · WEB-E2E-002 |
| BR-05 — hyper-targeted ads stream | §4A · §7 | WEB-US-004 · WEB-US-006 | WEB-BE-003 · WEB-FE-016 (stub) | WEB-E2E-002 |
| FND-US-008 — audit trail | §4A | WEB-US-011 | WEB-BE-009 · WEB-FE-015 · WEB-INT-007 | WEB-IT-005 |
| IDT-US-007/008 — verification | §5.1 | WEB-US-012/013 | WEB-BE-008 · WEB-FE-017/018 | WEB-E2E-005 |
| ORG-US-001/002/005/007–009 · COM-US-010/013 — hierarchy, notices, clubs | §4A · §5.1 | WEB-US-007/008/014–016 | WEB-FE-010–012/019–024 | WEB-E2E-003 · WEB-E2E-004 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: vendor portal login = 03 `vendor` role created by `users.CreateVendorLogin` on approval; exports `vendors.AccountForUser` + `RequireApprovedVendor` for 11/13; stub routes renamed to owners' names (`/school/ai-matrix` — Teacher access to own sections, `/school/integrations`), `/school/sections/[sectionId]` added; UI direction = professional SaaS landing + admin console (`docs/design-reference/README.md` §7) | Claude |
