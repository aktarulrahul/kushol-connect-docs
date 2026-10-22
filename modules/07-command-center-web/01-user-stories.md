# Command Center Web — User Stories

**Module:** `07-command-center-web`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Module 07 ships the web surface of Kushol Connect: the public B2B funnel (bilingual landing page —
bn default — ROI calculator, pilot registration, partner campaign inquiry, download links) and the
Command Center portals: Super Admin (`/admin` — tenants, cities, partner approvals, leads, audit
log), School Admin (`/institution` — dashboard, verification queue, notice composer, clubs, sections,
migration wizard) and the gated Partner shell (`/partner`). It converts the zero-CAC funnel of
`brd.md` §2 Goal 1 and the dashboard duties of `prd.md` §4A into working screens on top of modules
01–05 contracts.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Visitor (principal, partner, parent) | Reads the landing page in bn/en, plays with the ROI calculator, follows download links |
| School Principal | Books a pilot (lead) after seeing the ROI estimate and trust explainer |
| Partner / EdTech brand | Submits a campaign inquiry (lead + pending partner account) |
| Super Admin | Runs the platform: tenants, cities, partner approvals, leads pipeline, audit log, dashboard |
| School Admin | Governs only their school: dashboard, verification queue, notices, clubs, sections, migration |
| Partner (approved) | Sees the gated `/partner` shell ("pending approval" state until module 11 builds the portal) |
| System (audit, jobs) | Receives audit entries for destructive actions; `audit_log` read back by the viewer |

The five platform roles (Super Admin / School Admin / Teacher / Student / Guardian) plus Partner are
defined by module 03; verification gates every participatory action (`prd.md` §5.1).

## 3. Scope

**In scope**

- Landing `/` (hero, For Schools + ROI calculator, For Partners + inquiry, downloads, trust, footer)
  with bn/en toggle (bn default); `/download` (APK/TestFlight placeholders + QR placeholder); SEO
  suite (per-locale Metadata, OG, JSON-LD Organization, sitemap, robots) + CWV budgets (LCP < 2.5 s,
  CLS < 0.1, INP < 200 ms on 3G-fast)
- `/admin`: dashboard, tenants + create-school wizard (04; creates first School Admin), cities,
  partner approvals (approve/reject with reason, audit-logged), leads pipeline, campaign moderation
  stub (13), audit viewer (01)
- `/school`: dashboard cards, verification queue (approve/reject + reason, SLA badge — 03
  endpoints), notice composer + board (bn+en body, scope, pin, attachment, one-way — 05), clubs
  approval (05), sections manager (04), migration wizard (04)
- `/partner`: login-gated shell with pending/approved states
- `api` side: `landing_leads` + `vendor_accounts` tables, lead/partner/stats/audit-read endpoints,
  route-guard middleware + per-role layouts

**Out of scope** (explicit — prevents scope drift)

- `/login` screen — module 03 delivers it; 07 only gates shells behind it
- Roster CSV upload screen — module 14 (07 ships the `/institution/roster` stub + nav entry only)
- Ledger / AI Matrix / tutor verification / webhooks screens — modules 12/09/10/14 (stubs)
- Partner portal inventory/orders/campaign screens — module 11; campaign moderation logic — 13;
  revenue/fee data — modules 11/12 (placeholder empty states); chat/notice fan-out — 05/06

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | Generated client, `/healthz`, `audit.Record`, `audit_log` scoped reads, error envelope + `X-Request-Id` |
| 02 design-system | Tokens, primitives, `LocaleProvider`/`t()`; adds `landing`/`school`/`partner` namespaces |
| 03 identity-access | Session auth chain, `/login`, verification queue + school users endpoints |
| 04 organization-hierarchy | `POST/PATCH /admin/schools`, `POST /admin/cities`, picker reads, sections CRUD, migration endpoints |
| 05 communication-engine | Notices CRUD/pin, media presign/confirm, custom-group approval endpoints |
| 11/12 (later) | Revenue dashboards read their exports later — placeholder states now |

---

## 4. User Stories

### `WEB-US-001` — Read the landing page in Bengali (default) or English

**Priority:** P0 · **Traces:** `brd.md` §2 Goal 1, PRD §4A · **Depends on:** 02

**Story** — As a **school principal (visitor)**, I want **the landing page in Bangla by default with an English toggle**, so that **I immediately understand the offer in my own language**.

**Acceptance criteria**

- **Given** a first visit, **when** `/` renders, **then** all copy is Bengali (`<html lang="bn">`) set in Hind Siliguri, with headline + subhead + CTA.
- **Given** the visitor taps "EN", **when** the toggle commits, **then** every string re-renders in English, `<html lang>` flips, the choice persists on `/download`, and typed calculator input is preserved.
- **Given** the page renders, **when** crawled, **then** per-locale metadata, OG image, JSON-LD Organization, sitemap and robots are served.

**Notes** — `landing.hero.headline` bn "স্কুলের সব যোগাযোগ, এখন এক ঠিকানায়" / en "Your school's communication, one organised home"; CTA `landing.hero.cta` bn "পাইলট শুরু করুন" / en "Book a pilot".

---

### `WEB-US-002` — Estimate time saved with the ROI calculator

**Priority:** P0 · **Traces:** PRD §4A, content-truth `prompt.txt` §12 · **Depends on:** 02

**Story** — As a **school principal**, I want **to enter student count, notices/month and fee cycles and see estimated hours saved per year**, so that **I can judge the value before booking a pilot**.

**Acceptance criteria**

- **Given** the calculator, **when** I adjust the three inputs, **then** the hours/year result recomputes instantly from the deterministic formula and counts up (static under reduced motion).
- **Given** any rendered result, **when** I look below it, **then** the formula and assumptions are displayed and the figure is labelled an estimate — never cited as a measured benchmark.
- **Given** out-of-range input, **when** typed, **then** inline validation shows in the active locale and the result does not update.

**Notes** — Formula: `hours ≈ (students × noticesPerMonth × 12 × minutesPerNotice + students × feeCyclesPerYear × minutesPerFeeStudent) ÷ 60`; assumptions in one `ROI_ASSUMPTIONS` constant (`TODO: Confirm` with Rahul). Labels: `landing.roi.students` bn "শিক্ষার্থী সংখ্যা" / en "Students"; `landing.roi.notices` bn "মাসে নোটিশ সংখ্যা" / en "Notices per month"; `landing.roi.feeCycles` bn "বছরে ফি সাইকেল" / en "Fee cycles per year".

---

### `WEB-US-003` — Book a pilot (registration lead)

**Priority:** P0 · **Traces:** `brd.md` §2 Goal 1, PRD §4A · **Depends on:** 02

**Story** — As a **school principal**, I want **to submit my school's details as a pilot request**, so that **the Kushol team contacts me to onboard my school**.

**Acceptance criteria**

- **Given** the pilot form, **when** I submit valid name, BD phone, school, city, students and message, **then** a `pilot_registration` lead is stored (`landing_leads`, status `new`) and a bn/en success state shows.
- **Given** the API is briefly unavailable, **when** I submit, **then** input is not lost and I can retry without retyping.
- **Given** a flood from one IP, **when** the rate limit trips, **then** a polite `RATE_LIMITED` message renders; double-submit creates no duplicate rows.

---

### `WEB-US-004` — Partner submits a campaign inquiry

**Priority:** P0 · **Traces:** BR-05 (`brd.md` §5), §7 Stream 2 · **Depends on:** 02

**Story** — As a **partner / EdTech brand**, I want **to request hyper-targeted campaign access (demographics such as "Class 12 Science, Chattogram")**, so that **the team can qualify me for a partner account**.

**Acceptance criteria**

- **Given** the For Partners section, **when** I submit company, contact, BD phone, optional email and targeting description, **then** a `vendor_inquiry` lead **and** a `vendor_accounts` row (status `pending`) are created in one transaction.
- **Given** a Super Admin later decides the account, **when** the partner logs in, **then** approved opens the `/partner` shell (module 11 builds the portal), pending shows "your account is pending approval", rejected shows the reason with no access.

---

### `WEB-US-005` — Download the app

**Priority:** P1 · **Traces:** PRD §4A/§4B · **Depends on:** 02, 15 (EAS URLs later)

**Story** — As a **student or guardian**, I want **a `/download` page with APK and TestFlight links plus a QR code**, so that **I can install Kushol on my phone**.

**Acceptance criteria**

- **Given** `/download`, **when** it renders, **then** Android APK + iOS TestFlight cards and a QR placeholder show in bn/en.
- **Given** URLs are placeholders, **when** the page builds, **then** buttons render disabled with `TODO: Confirm` tracked (module 15 EAS) — never an invented URL; enabled links fire a `download_click` lead (source/utm) without blocking navigation.

---

### `WEB-US-006` — Super Admin monitors the platform dashboard

**Priority:** P0 · **Traces:** PRD §4A, `brd.md` §7 · **Depends on:** 03, 04

**Story** — As a **Super Admin**, I want **a dashboard with tenant count, lead counts and clearly marked revenue placeholders**, so that **I see platform health and what is not wired yet**.

**Acceptance criteria**

- **Given** a Super Admin session, **when** `/admin` loads, **then** tenants, active cities, leads by status/type and pending partners render from `GET /admin/stats`.
- **Given** revenue/analytics cards, **when** modules 11/12 have not shipped, **then** they show explicit "connects in modules 11/12" empty states — no fabricated figures.
- **Given** the campaign nav entry, **when** clicked, **then** `/admin/campaigns` shows a branded empty state ("ships in module 13").

---

### `WEB-US-007` — Super Admin provisions a tenant via the create-school wizard

**Priority:** P0 · **Traces:** ORG-US-001, PRD §4A · **Depends on:** 03, 04

**Story** — As a **Super Admin**, I want **a wizard that creates a school and its first (pre-verified) School Admin**, so that **a new tenant can start onboarding immediately**.

**Acceptance criteria**

- **Given** `/admin/tenants/new`, **when** I complete city → names → admin phone/name → review, **then** `POST /admin/schools` creates tenant + admin in one tx (04) and the review step shows exactly what will be created before submit.
- **Given** a duplicate school name in the city, **when** the API returns `CONFLICT`, **then** the field maps `hierarchy.school.name_duplicate` in bn/en and input is preserved.
- **Given** success, **when** the wizard closes, **then** the tenants list revalidates with the new school; the action is audit-logged (04).

---

### `WEB-US-008` — Super Admin manages launch cities

**Priority:** P1 · **Traces:** ORG-US-009 · **Depends on:** 04

**Story** — As a **Super Admin**, I want **to list and add cities**, so that **the hierarchy stays under platform control**.

**Acceptance criteria**

- **Given** `/admin/cities`, **when** it loads, **then** cities render with bn/en names and launch flags from 04 admin reads.
- **Given** a valid new city, **when** submitted, **then** `POST /admin/cities` creates it (201) and the list revalidates; duplicates surface `CONFLICT` inline; non-Super Admins are denied by layout gate and api alike.

---

### `WEB-US-009` — Super Admin approves or rejects a partner

**Priority:** P0 · **Traces:** PRD §4A, `brd.md` BR-04 · **Depends on:** 03

**Story** — As a **Super Admin**, I want **a partner queue with detail review and approve/reject decisions (reason required on reject/suspend)**, so that **only legitimate partners get platform access**.

**Acceptance criteria**

- **Given** `/admin/partners`, **when** it loads, **then** `GET /admin/partners` lists accounts filtered by status (pending first) with company, contact and submitted date.
- **Given** a pending detail, **when** I approve, **then** a confirm dialog commits `PATCH …/approve`, status becomes `approved`, and an audit entry is written.
- **Given** reject or suspend, **when** I confirm, **then** a reason (10–500 chars) is mandatory; the decision is stored, audited, and shown to the partner at `/partner`.

---

### `WEB-US-010` — Super Admin works the leads pipeline

**Priority:** P1 · **Traces:** `brd.md` §2 Goal 1 · **Depends on:** —

**Story** — As a **Super Admin**, I want **to view leads and move them through new → contacted → converted/archived**, so that **the acquisition funnel is actually worked**.

**Acceptance criteria**

- **Given** `/admin/leads`, **when** filtered by type or status, **then** `GET /admin/leads` returns the page with contact, school/city and UTM source.
- **Given** a lead, **when** I change status, **then** `PATCH /admin/leads/{id}` applies only legal transitions and the row updates optimistically with rollback on error; a converted pilot links to the create-school wizard (US-007) as an explicit separate step.

---

### `WEB-US-011` — Super Admin inspects the audit log

**Priority:** P2 · **Traces:** FND-US-008 · **Depends on:** 01

**Story** — As a **Super Admin**, I want **a filterable viewer over the append-only audit log**, so that **I can answer "who did what" after any incident**.

**Acceptance criteria**

- **Given** `/admin/audit`, **when** it loads, **then** `GET /admin/audit-log` (Super Admin only) pages entries newest-first with actor, action, entity and timestamp.
- **Given** entity/action filters, **when** applied, **then** only matching entries render; no edit/delete affordance exists anywhere (append-only by 01).

---

### `WEB-US-012` — School Admin monitors the school dashboard

**Priority:** P0 · **Traces:** PRD §4A · **Depends on:** 03, 04, 05

**Story** — As a **School Admin**, I want **cards for students, sections, pending verifications and recent notices**, so that **I know what needs attention today**.

**Acceptance criteria**

- **Given** a School Admin session, **when** `/school` loads, **then** `GET /institution/stats` renders the four cards scoped to my school only.
- **Given** pending verifications > 0, **when** the card renders, **then** it links to `/institution/users` as the primary action; another school's admin sees only their tenant's numbers (claim-scoped).

---

### `WEB-US-013` — School Admin verifies join requests

**Priority:** P0 · **Traces:** IDT-US-007/008, `prd.md` §5.1 · **Depends on:** 03

**Story** — As a **School Admin**, I want **a verification queue to review evidence and approve or reject (with reason) each join request**, so that **only real members of my school get in**.

**Acceptance criteria**

- **Given** `/institution/users`, **when** it loads, **then** `GET /verification-requests` (03) lists pending requests with name, role, masked phone, evidence, submitted time and reminder count.
- **Given** a request older than 48 h, **when** the row renders, **then** an overdue SLA badge (amber > 48 h, red > 72 h) stands out — SLA from 03's data, never guessed.
- **Given** approve, **when** confirmed, **then** the row leaves the queue; **given** reject, **then** a reason (10–500) is mandatory; a stale row surfaces `CONFLICT` and refreshes.

---

### `WEB-US-014` — School Admin composes and publishes a one-way notice

**Priority:** P0 · **Traces:** PRD §4A/§5.1, COM-US-010 · **Depends on:** 04, 05

**Story** — As a **School Admin**, I want **a composer with bn+en body, school/section scope, pin toggle and PDF/image attachment**, so that **I can broadcast official information school-wide or to one section**.

**Acceptance criteria**

- **Given** `/institution/notices/new`, **when** I fill title + Bengali body (+ optional English), choose scope (school or section from 04 data), toggle pin and attach a PDF, **then** preview shows exactly what recipients will read.
- **Given** submit with attachment, **when** publishing, **then** the file uploads via 05's presign → R2 PUT → confirm first; `POST /notices` carries the confirmed `attachmentId`.
- **Given** the composer, **when** it opens, **then** the one-way rule ("recipients cannot reply") is visible; the board lists pinned-first with pin/delete controls.

**Notes** — Composer strings: `school.notices.title` bn "শিরোনাম" / en "Title"; `school.notices.bodyBn` bn "বিস্তারিত (বাংলা)" / en "Body (Bengali)"; `school.notices.pin` bn "শীর্ষে পিন করুন" / en "Pin to top"; `school.notices.send` bn "নোটিশ পাঠান" / en "Publish notice"; `school.notices.oneWayInfo` bn "নোটিশ একমুখী — প্রাপকরা উত্তর দিতে পারবেন না।" / en "Notices are one-way — recipients cannot reply."

---

### `WEB-US-015` — School Admin runs the year-end migration wizard

**Priority:** P0 · **Traces:** BR-01 (`brd.md` §5), ORG-US-007/008 · **Depends on:** 04

**Story** — As a **School Admin**, I want **a wizard that dry-runs the session migration, shows per-student results, and only then commits**, so that **promotion day cannot corrupt my roster**.

**Acceptance criteria**

- **Given** `/institution/migrations/new`, **when** I pick the session and start, **then** `POST /institution/migrations {dryRun:true}` returns a DRAFT run and a per-item table (PROMOTED/GRADUATED/RETAINED/ERROR) with counters.
- **Given** any ERROR item, **when** review renders, **then** commit stays disabled with row-level detail; only a zero-ERROR run reaches confirm (`dryRun:false` → PREVIEWED).
- **Given** confirmation, **when** I commit, **then** `POST …/commit` starts the run and `/institution/migrations/[id]` polls `GET /institution/migrations/{id}` until COMMITTED; audit-logged (04).

---

### `WEB-US-016` — School Admin manages sections and approves clubs

**Priority:** P1 · **Traces:** ORG-US-002/005, COM-US-013 · **Depends on:** 04, 05

**Story** — As a **School Admin**, I want **a sections manager (create/archive per session) and a club approval queue for custom groups**, so that **the hierarchy and student-led groups stay governed by the school**.

**Acceptance criteria**

- **Given** `/institution/sections`, **when** I create a section (class level, name, session), **then** `POST /institution/sections` creates it and the list revalidates; duplicates surface `hierarchy.section.name_duplicate`.
- **Given** `/institution/clubs`, **when** it loads, **then** pending custom groups list with creator; approve assigns the creator as owner (05 approval endpoints, audit-logged in 05); decline records the decision.
- **Given** a section with ACTIVE enrollments, **when** archive is attempted, **then** the 04 `CONFLICT` renders with the explanation, not a generic error.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `WEB-BR-001` | Landing + download are public, Bengali-default with persistent bn/en toggle; portals require a session (03); middleware checks cookie presence for redirects only — the api is the authority | Middleware + api auth chain |
| `WEB-BR-002` | ROI output is an ESTIMATE from a fixed deterministic formula whose assumptions are displayed; no invented benchmarks, school names, prices or counts anywhere | `ROI_ASSUMPTIONS` + catalog copy + content review |
| `WEB-BR-003` | Web never touches the database — every read/write goes through the generated `openapi-fetch` client; RFC-7807 errors map to catalog copy | ESLint boundary + CI |
| `WEB-BR-004` | Public lead endpoints are create-only: `landing_leads` always start `new`; status/source are server-derived (utm captured, never trusted from client) | api lead service |
| `WEB-BR-005` | Lead status moves are Super-Admin-only and restricted to `new → contacted → converted\|archived`; `new` is never re-entered | api transition table |
| `WEB-BR-006` | A partner inquiry creates `vendor_accounts(status=pending)` atomically with its lead; only Super Admin moves pending → approved/rejected/suspended; reject/suspend require a reason (10–500) | api partner service |
| `WEB-BR-007` | Every destructive action (school/city create, partner decision, lead status, migration preview/commit) is confirmed in the UI naming the object, and audit-logged api-side | Confirm dialogs + `audit.Record` |
| `WEB-BR-008` | School Admin surfaces are tenant-scoped by claim; the web never sends a `schoolId` it was not issued | api tenant scope |
| `WEB-BR-009` | Revenue/active-user/campaign figures are never invented — cards render explicit "connects in modules 11/12/13" empty states | Placeholder components |
| `WEB-BR-010` | Notices are one-way broadcasts: composer explains it, no reply affordance; pinned-first ordering | 05 semantics + composer copy |
| `WEB-BR-011` | Migration commit is impossible unless the run is PREVIEWED with zero ERROR items (04 guards; wizard mirrors the state) | Wizard state machine + api `CONFLICT` |
| `WEB-BR-012` | Download URLs are disabled placeholders until module 15 publishes EAS links | `NEXT_PUBLIC_DOWNLOAD_URLS_READY` flag |
| `WEB-BR-013` | Verification SLA badge uses module 03's SLA (default 48 h) computed from 03's data, never guessed | Queue component + 03 config |

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| Lead: contact name / school name | 3–120 / 3–150 chars | `validation.name.length` · `validation.school_name.length` |
| Lead: phone | BD mobile E.164 `+8801XXXXXXXXX` | `validation.phone.bd_mobile` |
| Lead: city | ACTIVE city id (04) | `validation.hierarchy.invalid` |
| Lead: students count / message | int 1–20 000 / ≤ 1000 optional | `validation.count.range` · `validation.text.too_long` |
| ROI: students / notices / fee cycles | 1–20 000 / 1–200 / 1–12 | `validation.count.range` |
| Partner: company / targeting | 3–150 / 10–1000 chars | `validation.company_name.length` · `validation.text.length` |
| School create: nameBn + nameEn | 3–150 each; unique per city (server) | `validation.required` · `hierarchy.school.name_duplicate` |
| School create: admin phone | BD mobile; becomes first School Admin | `validation.phone.bd_mobile` |
| Section: classLevel / name / sessionYear | 1–12 / 1–20 / ≥ 2026 | `validation.range` · `hierarchy.section.name_duplicate` |
| Notice: title | 3–120 chars | `validation.title.length` |
| Notice: body bn part / en part | bn required 1–2400; en optional ≤ 2400; assembled ≤ 5000 | `validation.text.length` |
| Notice: sectionId | required iff scope=`section`, must be in my school | `validation.scope.section_required` |
| Reject reason (verification / partner) | 10–500 chars, required | `validation.reason.length` |
| Migration: fromSessionYear | int ≥ 2026; open-run guard server-side | `validation.range` · `hierarchy.migration.open_run` |

Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas in
`applications/web/src/schemas`; both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated visit to `/admin`, `/school`, `/partner` | Redirect to `/login?next=…`; return path honoured; no portal chrome flashes |
| 2 | Wrong-role visit (School Admin → `/admin/tenants`) | FORBIDDEN page + limited nav; api independently returns FORBIDDEN |
| 3 | Cross-tenant attempt (forged sectionId/schoolId) | Web sends only claim-derived scope; api answers `TENANT_MISMATCH`/404 with request id |
| 4 | api down on the landing | Static/ISR page still serves; lead forms show retry-safe notice, input kept |
| 5 | api down inside a portal | Error boundary with retry + `X-Request-Id`; tables keep stale data marked |
| 6 | Double-submit (wizard/composer double-click) | Submit disabled while pending + api idempotency/conflict guard; no duplicates |
| 7 | Stale row (partner decided / run committed / request decided elsewhere) | `CONFLICT` → "refresh this row" copy; list auto-revalidates |
| 8 | Attachment upload fails (R2 presign/confirm) | Publish blocked with retry copy; text-only notice still possible |
| 9 | Reduced-motion preference | Count-up, panel transitions and shimmer render static/instant |
| 10 | Locale toggled mid-form | Values preserved; labels/messages switch; `<html lang>` + font stack update |
| 11 | Unknown portal route | Branded bn/en 404 with "back to dashboard" |
| 12 | Placeholder download click | Button disabled with "coming soon" — never navigates to an invented URL |

## 8. Reporting Needs

- `GET /admin/stats` (this module): tenants, active cities, leads by status/type, pending partners — `/admin` dashboard; revenue intentionally placeholder until modules 11/12 exports exist.
- `GET /institution/stats` (this module): students, active sections, pending verifications (03), notices last 30 days (05) — `/school` dashboard.
- `audit_log` reads (01's table, exposed here read-only) — `/admin/audit`.
- Lead-conversion figures feed future marketing dashboards (module 13+); none defined yet.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | ROI time-saved assumptions — realistic minutes per notice and per student per fee cycle? | Rahul | Open | `minutesPerNotice = 4`, `minutesPerFeeStudent = 0.5` in `ROI_ASSUMPTIONS`; labelled estimate; `TODO: Confirm` pre-launch |
| 2 | Roster CSV format (template/headers) for the `/institution/roster` stub tooltip | Rahul | Open | Template generated by the portal (module 14); strict header validation with row-level error report |
| 3 | Final APK / TestFlight URLs | Rahul | Open | Disabled placeholders; `TODO: Confirm` store URLs at module 15 (EAS) |
| 4 | Notices are single-body in 05 — is the assembled bn-first `bn\n\n—\nen` body acceptable for the composer? | Rahul + 05 owner | Open | Assembled bilingual body, bn first, fixed separator, per-part caps |
| 5 | Partner reinstate path after suspension/rejection? | Rahul | Open | `PATCH …/approve` allowed again from `suspended`/`rejected` (additive, audit-logged) |
| 6 | Lead follow-up SLA / reminder jobs in Phase 1? | Rahul | Open | None — leads worked manually in the pipeline; no reminder jobs this module |
