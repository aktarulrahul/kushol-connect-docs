# Command Center Web — Backend Tasks & Database Design

**Module:** `07-command-center-web`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms (shared schemas) · generated `openapi-fetch` client → api — web never touches the DB
**Last updated:** 2026-09-30

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `landing_leads` (model `LandingLead`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `type` | `text` | no | — | `pilot_registration` \| `vendor_inquiry` \| `download_click` (CHECK) |
| `contact_name` | `text` | yes | — | 3–120 when present (download_click has none) |
| `phone` | `text` | yes | — | E.164 `+880…` when present; UNIQUE not enforced (re-interest allowed) |
| `email` | `text` | yes | — | optional, vendor inquiries |
| `school_name` | `text` | yes | — | pilot leads |
| `city_id` | `uuid` | yes | — | Reference → 04 cities (FK-free per 01 convention); validated ACTIVE at create |
| `students_count` | `int` | yes | — | pilot leads, 1–20 000 |
| `targeting` | `text` | yes | — | vendor demographics pitch, 10–1000 |
| `message` | `text` | yes | — | ≤ 1000 |
| `status` | `text` | no | `new` | `new` \| `contacted` \| `converted` \| `archived` (CHECK; service transition table) |
| `source` | `text` | no | — | derived server-side: `landing_hero` \| `roi_calculator` \| `for_vendors` \| `download_page` \| `direct` |
| `utm_source` / `utm_medium` / `utm_campaign` | `text` | yes | — | captured from query, length-capped |
| `vendor_account_id` | `uuid` | yes | — | set iff `type='vendor_inquiry'` (1:1 with `vendor_accounts`) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK type/status; `vendor_account_id` NOT NULL iff `type='vendor_inquiry'`.
**Indexes:** `(status, created_at DESC)` → admin pipeline queue; `(type, created_at DESC)` →
filtered lists; `(city_id)` → city-filtered reporting. **Tenant rule:** platform-wide table —
writes are public (create-only, `WEB-BR-004`), reads are Super Admin only; no tenant column by
design.

#### `vendor_accounts` (model `VendorAccount`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `company_name` | `text` | no | — | 3–150 |
| `contact_name` | `text` | no | — | 3–120 |
| `phone` | `text` | no | — | E.164 BD mobile |
| `email` | `text` | yes | — | optional |
| `targeting` | `text` | no | — | requested demographics, 10–1000 |
| `status` | `text` | no | `pending` | `pending` \| `approved` \| `rejected` \| `suspended` (CHECK) |
| `decision_reason` | `text` | yes | — | required (10–500) on reject/suspend; cleared on re-approve |
| `decided_by` / `decided_at` | `uuid` / `timestamptz` | yes / yes | — | Super Admin user id (reference → 03) / decision time |
| `portal_user_id` | `uuid` | yes | — | Reference → 03 `users` (role `vendor`); set on approval by calling 03 `users.CreateVendorLogin` with the inquiry's contact email (password set via reset link). Vendor routes (11/13) resolve `vendor_account_id` from this column via 07's `vendors.AccountForUser(userID)` gate |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** status CHECK; reject/suspend without reason refused in service (10–500).
**Indexes:** `(status, created_at DESC)` → approval queue; `(company_name)` (pg_trgm) → search.
**Tenant rule:** platform-wide — Super Admin lifecycle only (`WEB-BR-006`); consumed read-only by
module 11 (campus commerce) after approval.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261015090000_web_landing_leads` (leads + CHECKs + pipeline/type indexes) | ✅ |
| 2 | `20261015091000_web_vendor_accounts` (accounts + CHECKs + queue index + trgm search) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| 3 demo leads (one per type, "Demo High School", fictional contact) | `DRAFT` (clearly fictional) | `prompt.txt` §12 |
| 2 demo vendor accounts (pending + approved, fictional companies) | `DRAFT` (clearly fictional) | `prompt.txt` §12 |

---

## 2. Server Contracts

### Endpoint summary (all Go handlers generated from the OpenAPI spec; auth chain on every protected route: authenticate → load role claims → tenant-scope)

| # | Endpoint | Purpose | Errors (beyond common) | Stories |
| --- | --- | --- | --- | --- |
| 1 | `POST /api/v1/leads` | Public lead create (pilot / vendor / download_click) | `VALIDATION_FAILED` · `RATE_LIMITED` · `NOT_FOUND` (bad city) | US-003/004/005 |
| 2 | `POST /api/v1/vendor/register` | Vendor inquiry → lead + `pending` vendor account (one tx) | same as #1 | US-004 |
| 3 | `GET /api/v1/admin/leads` | Pipeline list, filter `type`/`status`, cursor page | `FORBIDDEN` | US-010 |
| 4 | `PATCH /api/v1/admin/leads/{id}` | Status transition (service table) | `CONFLICT` (illegal transition) | US-010 |
| 5 | `GET /api/v1/admin/vendors` | Vendor queue, filter `status` + name search | `FORBIDDEN` | US-009 |
| 6 | `PATCH /api/v1/admin/vendors/{id}/approve` · `…/reject` · `…/suspend` | Lifecycle decisions (reason on reject/suspend) | `CONFLICT` (already decided) · `VALIDATION_FAILED` (reason) | US-009 |
| 7 | `GET /api/v1/admin/stats` | Tenants/cities (via 04), leads by status/type, vendors pending, revenue placeholder flags | `FORBIDDEN` | US-006 |
| 8 | `GET /api/v1/school/stats` | School-scoped counts: students/sections (04), pending verifications (03), notices 30 d (05) | `FORBIDDEN` · `TENANT_MISMATCH` | US-012 |
| 9 | `GET /api/v1/admin/audit-log` | Read-only viewer over 01's `audit_log` (scoped list queries) | `FORBIDDEN` · `VALIDATION_FAILED` | US-011 |

Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` ·
`TENANT_MISMATCH` · `NOT_FOUND` · `CONFLICT` · `RATE_LIMITED` · `INTERNAL` (RFC-7807
`application/problem+json`). New rate-limit class `leads` for #1/#2 (10/h/IP, 3/min burst); #4/#6
default class; #3/#5/#7/#8/#9 default class.

### Endpoint `POST /api/v1/leads` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | Public — no auth middleware; rate-limit class `leads` |
| **Input** | `{type, contactName?, phone?, email?, schoolName?, cityId?, studentsCount?, targeting?, message?, source, utm?}`; contract-generated validator; server re-derives `source` allowlist + caps utm lengths (never trusts client status) |
| **Result** | `201 { "data": { id, type, status: "new" } }` — no PII echo beyond submitted fields |
| **Errors** | `VALIDATION_FAILED` (per-field, mapped to `validation.*` keys) · `NOT_FOUND` (unknown/inactive city) · `RATE_LIMITED` |
| **Rate limit** | `leads`: 10/h/IP, 3/min burst (Redis, DB fallback counters) |
| **Audit** | No (public create is the event itself; pipeline changes audit) |
| **Stories** | `WEB-US-003` `WEB-US-005` |

### Endpoints `PATCH /api/v1/admin/vendors/{id}/approve|reject|suspend`

| | |
| --- | --- |
| **Auth** | authenticate → role claim `SUPER_ADMIN` |
| **Input** | path id; reject/suspend body `{reason}` (10–500, required); approve/suspend-from-rejected allowed per OQ-5 default |
| **Result** | `{ "data": { vendorAccount } }` with new status + `decidedBy/decidedAt` |
| **Errors** | `CONFLICT` (double decision) · `VALIDATION_FAILED` (missing/short reason) · `NOT_FOUND` |
| **Rate limit** | default class |
| **Audit** | Yes — `vendor.approved` / `vendor.rejected` / `vendor.suspended` (actor, target, reason) via `audit.Record` |
| **Stories** | `WEB-US-009` |

### Endpoints `GET /api/v1/admin/stats` · `GET /api/v1/school/stats`

| | |
| --- | --- |
| **Auth** | #7 `SUPER_ADMIN`; #8 `SCHOOL_ADMIN` → tenant-scope (school from claim) |
| **Input** | none (school claim scopes #8) |
| **Result** | #7 `{ tenants, activeCities, leadsByStatus, leadsByType, vendorsPending, revenue: { connected: false, connectsIn: "modules 11/12" } }` · #8 `{ students, activeSections, pendingVerifications, noticesLast30d }` |
| **Errors** | `FORBIDDEN`; #8 degrades to partial payload (flags per source) if an upstream count export is unavailable |
| **Rate limit** | default class |
| **Audit** | none (read-only) |
| **Stories** | `WEB-US-006` `WEB-US-012` |

### Web Server Action / Route Handler (Next.js)

Every web mutation is a Route Handler/Server Action in `applications/web` that calls the Go API
through the generated `openapi-fetch` client with `credentials: include` (session cookie,
`X-CSRF-Token` on mutations) — never the database directly. Same zod schemas from each app's `src/theme`
re-validate on the server; RFC-7807 codes map to `validation.*`/`errors.*` catalog keys before
reaching the client. Middleware reads cookie **presence** for redirects only (`WEB-BR-001`); portal
layouts re-check role claims server-side per route group.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `WEB-BE-001` | `leads.Create` (public) | Validate vs contract; city must be ACTIVE; `status` forced `new`; source allowlisted; utm capped; rate-limit class `leads` | `admin:leads` (no-op server cache) | No |
| `WEB-BE-002` | `vendor.Register` (public) | One tx: `landing_leads` (vendor_inquiry) + `vendor_accounts` (pending, `WEB-INV-002`); same `leads` limits | `admin:leads`, `admin:vendors` | No |
| `WEB-BE-003` | `leads.ListForAdmin` | Super Admin; filters `type`/`status`; cursor pagination 50 | — | No |
| `WEB-BE-004` | `leads.UpdateStatus` | Super Admin; transition table per INV-001 (`CONFLICT` otherwise); audit `lead.status_changed` | `admin:leads` | Yes |
| `WEB-BE-005` | `vendors.ListForAdmin` | Super Admin; status filter + trgm name search | — | No |
| `WEB-BE-006` | `vendors.Approve` / `vendors.Reject` / `vendors.Suspend` + export `vendors.AccountForUser(userID)` / `RequireApprovedVendor()` middleware for 11/13 | Super Admin; approve creates the portal login via 03 `users.CreateVendorLogin` (idempotent: reuse existing `portal_user_id`); suspend calls 03 `sessions.InvalidateForUser`; reason 10–500 on reject/suspend; `CONFLICT` on double decision; re-approve path per OQ-5; audit each | `admin:vendors` | Yes |
| `WEB-BE-007` | `stats.AdminStats` | Super Admin; own counts + additive 04 export `hierarchy.PlatformCounts()`; revenue placeholder constant | — | No |
| `WEB-BE-008` | `stats.SchoolStats` | School Admin, claim-scoped; additive exports: 04 `hierarchy.SchoolCounts(schoolID)`, 03 `verification.PendingCount(schoolID)`, 05 `chat.NoticeStats(schoolID)`; partial-payload flags on upstream failure | — | No |
| `WEB-BE-009` | `auditlog.List` (read endpoint over 01) | Super Admin; filters `entityType`/`entityId`/`schoolId`; pages 50; read-only (no write path exists) | — | No |
| `WEB-BE-010` | OpenAPI paths #1–#9 + schemas (`LeadCreate`, `VendorDecision`, `StatsDTOs`) added to `applications/api/openapi/`; Go + TS clients regenerated | Spec-first; CI drift gate | — | — |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `WEB-BE-011` | `InsertLead / ListLeads(type, status, cursor) / UpdateLeadStatus` | status transition guarded in `UPDATE … WHERE status = $expected` | `(status, created_at DESC)` · `(type, created_at DESC)` |
| `WEB-BE-012` | `InsertVendorAccount / ListVendorAccounts(status, q, cursor) / UpdateVendorStatus` | status-guarded UPDATE; trgm ILIKE search | `(status, created_at DESC)` · trgm `(company_name)` |
| `WEB-BE-013` | `CountLeadsByStatus / CountLeadsByType / CountVendorsByStatus` | single-scan aggregates for `/admin/stats` | same composite indexes |
| `WEB-BE-014` | Seed loader (demo leads + vendors, fictional-marked) | idempotent upsert by natural keys | — |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `WEB-BE-015` | None — leads are worked manually in the pipeline in Phase 1 (OQ-6); no reminder/digest jobs this module. Any future SLA/reminder job is additive and declared here first | — | — | — |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `WEB-UT-001` | Lead payload validation: per-field zod/OpenAPI parity, status forced `new`, source allowlist, utm capping | Unit | `WEB-BR-004`, US-003/004 |
| `WEB-UT-002` | Lead transition table: `new→contacted→converted` ok; `contacted→new`, `archived→*` refused | Unit | INV-001, `WEB-BR-005` |
| `WEB-UT-003` | Vendor lifecycle: reject without reason refused; double-decide → `CONFLICT`; suspend→re-approve clears reason | Unit | `WEB-BR-006`, OQ-5 default |
| `WEB-UT-004` | `vendor.Register` creates lead + account atomically (fake repo failure → neither row) | Unit | INV-002 |
| `WEB-UT-005` | `stats.SchoolStats` partial-payload flags when an upstream count export errors | Unit | §2 #8 degradation |
| `WEB-IT-001` | Unauthenticated `POST /leads` flood → `RATE_LIMITED` after class limits; valid submit → 201 `new` | Integration (testcontainers Postgres) | `leads` rate class, BR-004 |
| `WEB-IT-002` | Every protected endpoint (#3–#9) unauthenticated → `UNAUTHENTICATED`; School Admin on admin routes → `FORBIDDEN` | Integration | auth chain |
| `WEB-IT-003` | School Admin `GET /institution/stats` returns only claim-scoped counts; forged query params cannot widen scope | Integration | `WEB-BR-008` |
| `WEB-IT-004` | Vendor approve/reject writes `audit.Record` entries (actor, reason) atomically; audit failure aborts decision | Integration | `WEB-BR-007`, 01 I-3 contract |
| `WEB-IT-005` | Cross-tenant probe on `/admin/audit-log?schoolId=` as School Admin → `TENANT_MISMATCH`/404, no rows leak | Integration | scoped reads (01 pattern) |
| `WEB-IT-006` | Seed loader idempotent; public reads never expose `DRAFT` demo rows as real partners (fictional marking intact) | Integration | content-truth `prompt.txt` §12 |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
publish guard blocks `TODO:`; public reads never return drafts.

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [x] `WEB-BE-001`–`WEB-BE-002` migrations 1–2 (`landing_leads`, `vendor_accounts`) — 2026-10-03
- [x] `WEB-BE-011`–`WEB-BE-012` sqlc queries + repositories (status-guarded transitions) — 2026-10-03
- [ ] `WEB-BE-014` seed loader (fictional demo data)

### Repository · Service · Entry points · Seed · Tests

- [x] `WEB-BE-010` OpenAPI paths #1–#9 + schemas; regenerate Go + TS clients — 2026-10-03
- [x] `WEB-BE-003`/`WEB-BE-004` leads admin services + `PATCH /admin/leads/<built-in function id>` — 2026-10-03
- [x] `WEB-BE-001` public `POST /leads` (+ `leads` rate-limit class wired to 01 limiter) — 2026-10-03
- [x] `WEB-BE-002` `POST /vendor/register` atomic create — 2026-10-03
- [x] `WEB-BE-005`/`WEB-BE-006` vendor list + approve/reject/suspend with audit — 2026-10-03
- [x] `WEB-BE-007`/`WEB-BE-008` stats services + additive count exports agreed with 03/04/05 — 2026-10-03
- [x] `WEB-BE-009` `GET /admin/audit-log` over 01's scoped list queries — 2026-10-03
- [x] `WEB-BE-013` stats aggregates — 2026-10-03
- [x] Tests `WEB-UT-001`–`005` unit green — 2026-10-03; `WEB-IT-001`–`006` pending owner (containers)
