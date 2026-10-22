# Command Center Web — Frontend Tasks

**Module:** `07-command-center-web`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Next.js App Router (standalone) · TypeScript strict · Tailwind v4 `@theme` tokens · shadcn/ui (module 02 primitives) · TanStack Table + TanStack Query · RHF + Zod (shared schemas)
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from each app's `src/theme`, every user-facing string in Bengali + English, bn default.

> **Visual direction (owner, 2026-09-30):** professional. Landing = modern B2B SaaS marketing site;
> `/admin`, `/school`, `/partner` = dense admin console on 02's `AdminShell`/`PageHeader`/`StatCard`/`DataTable`.
> Binding rules: `docs/design-reference/README.md` §7. No fabricated logos, testimonials or numbers.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/` | Landing funnel (hero, ROI calculator, For Partners, downloads, trust, footer) | Static + ISR (`landing:content`) | Public |
| 2 | `/download` | App download (APK/TestFlight + QR placeholder) | Static + ISR | Public |
| 3 | `/login` | Sign-in (screen delivered by module 03; 07 gates shells behind it) | Dynamic | Public |
| 4 | `/admin` | Super Admin dashboard | Dynamic | Super Admin |
| 5 | `/admin/tenants` | Tenants list (TanStack Table) | Dynamic | Super Admin |
| 6 | `/admin/tenants/new` | Create-school wizard (3 steps + review) | Dynamic | Super Admin |
| 7 | `/admin/cities` | Cities management | Dynamic | Super Admin |
| 8 | `/admin/partners` | Partner approval queue (list + detail drawer) | Dynamic | Super Admin |
| 9 | `/admin/leads` | Leads pipeline | Dynamic | Super Admin |
| 10 | `/admin/campaigns` | Campaign moderation stub ("ships in module 13") | Dynamic | Super Admin |
| 11 | `/admin/audit` | Audit log viewer | Dynamic | Super Admin |
| 12 | `/school` | School Admin dashboard | Dynamic | School Admin |
| 13 | `/institution/users` | Verification queue (SLA badges) | Dynamic | School Admin |
| 14 | `/institution/notices` | Notice board (pinned-first, pin/delete) | Dynamic | School Admin |
| 15 | `/institution/notices/new` | Notice composer (bn+en, scope, pin, attachment, preview) | Dynamic | School Admin |
| 16 | `/institution/clubs` | Club (custom group) approval queue | Dynamic | School Admin |
| 17 | `/institution/sections` | Sections manager (create/archive) | Dynamic | School Admin |
| 17a | `/institution/sections/[sectionId]` | Section detail + roster + class-teacher assignment (04 `04-frontend-tasks` screen 5) | Dynamic | School Admin |
| 18 | `/institution/migrations` | Migration runs list | Dynamic | School Admin |
| 19 | `/institution/migrations/new` | Migration wizard (select → dry-run → review → commit) | Dynamic | School Admin |
| 20 | `/institution/migrations/[id]` | Migration status page (poll while COMMITTING) | Dynamic | School Admin |
| 21 | `/institution/roster` | Stub → module 14 | Dynamic | School Admin |
| 22 | `/institution/ledger` · `/institution/ai-matrix` · `/institution/tutors` · `/institution/integrations` | Stubs → modules 12/09/10/14 (route names owned by those modules) | Dynamic | School Admin (`/institution/ai-matrix` also Teacher — own sections only, 09) |
| 23 | `/partner` | Partner shell (pending/approved state) | Dynamic | Partner |
| 24 | `*` | Branded 404 + role-aware FORBIDDEN pages | Dynamic | All |

## 2. Screen Breakdown

### 2.1 Landing — `/` (Redesigned 2026-10-09 per Owner Direction)

**Layout & Funnel Rhythm**

The landing page is an illustrated, high-density promotional funnel targeting 3 actions:
1. **Schools/Colleges:** Join the pilot (`#pilot`)
2. **Partners & Education Brands:** Apply as a partner (`#partners`)
3. **Guardians & Students:** Download the app (`/download` or `#download`)

Section rhythm alternates surfaces (`Paper` `#FAFBFC` → `teal-50` `#EDF6F8` → `white` → full-bleed deep-teal `#095777` band) to eliminate dead white space.

**Modular Landing Components (`src/components/landing/`)**

| Component | Client/Server | Role & Interactions |
| --- | --- | --- |
| `AnnouncementBar` | Client | Dismissible thin deep-teal top banner with session storage memory |
| `LandingHeader` | Client | Sticky header (64px → 56px on scroll), logo lockup, compact 4-item nav, `LanguageToggle variant="switch"`, login link, `#pilot` CTA |
| `HeroSection` | Client | LCP-optimized hero (H1 + 3 verified fact chips: 0 subscription fees during pilot, CSV/Excel instant upload, 100% institution control) + I-1 illustration |
| `BeforeAfterSlider` | Client | Draggable comparison slider (WhatsApp chaos vs Kushol order) with mouse/touch/keyboard handles and 4 contrast rows |
| `FeatureSlider` | Client | 12-feature spotlight carousel (`framer-motion`) with 5 category filters, 6s autoplay progress bar, play/pause controls, keyboard navigation (ArrowLeft/Right) |
| `HowItWorks` | Client | 3-step structured process cards (Upload Roster → Auto-Group → Connect Safely) |
| `RoleTabs` | Client | 4-tab role switch (Guardians, Teachers, Institutions, Partners) with 3 verified benefits each and role-specific CTAs |
| `DeskDemo` | Client | Interactive school admin desk illustration with clickable feature hotspots (Roster, Notices, Sync) |
| `RoiCalculator` | Client | Dual range slider + number inputs, 400ms count-up payoff, instant comparison bar against traditional SMS costs |
| `TrustSafety` | Server | Full-bleed deep-teal band with City → Institution → Section hierarchy diagram and 4 security pillars |
| `PilotSection` | Client | Pilot school pitch with strictly real "২–৩টি প্রতিষ্ঠান" seat limit + `PilotForm` |
| `VendorSection` | Client | Partner pitch with I-10 audience targeting illustration + `VendorInquiryForm` |
| `AppDownloadSection` | Client | Mobile app promo with QR code, disabled store badges, and pointer 3D tilt |
| `FaqAccordion` | Client | 6 real objection-resolving questions in clean accordion |
| `FinalCtaBand` | Server | Full-bleed deep-teal closing banner with dual CTAs |
| `LandingFooter` | Client | Brand lockup, compact nav links, legal, contact, and copyright |
| `MobileStickyCta` | Client | Floating mobile bottom action bar that auto-hides when forms/footer are in viewport |
| `Illustrations` | Client/Server | 14 custom inline SVG vector scenes (I-1 to I-14) using exclusively token palette |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Static page — no skeleton needed; forms hydrate last |
| Empty | N/A (marketing content always present) |
| Error | Form-level inline errors; submit retries keep input (`WEB-US-003`) |
| Not found | Branded 404 |
| Success | Inline success panel with next-step copy (`landing.pilot.success` bn/en) |

### 2.2 Download — `/download`

**Layout** — centred column: title, two platform cards (Android APK / iOS TestFlight) with big
buttons, QR placeholder box (labelled), "how to install" collapsible, back-to-home link.

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `PlatformCard` ×2 | Server | URLs from env; disabled + tooltip until `NEXT_PUBLIC_DOWNLOAD_URLS_READY` |
| `QrPlaceholder` | Server | Marked placeholder frame, alt text in bn/en |

**States** — placeholders render disabled with "coming soon" (`landing.download.soon`); enabled
links fire a `download_click` lead via `navigator.sendBeacon` (fire-and-forget, never blocks nav).

### 2.3 Portal shells + dashboards — `/admin`, `/school`, `/partner`

**Layout**

```text
DESKTOP ≥1024                     TABLET 768–1023 (portals target ≥768)
┌────────┬─────────────────────┐  ┌──────────────────────────────┐
│ sidebar│ topbar: role·lang·  │  │ topbar (hamburger drawer)    │
│ nav    │ logout              │  ├──────────────────────────────┤
│ ·Dash  ├─────────────────────┤  │ content single-column;       │
│ ·Items │ content: cards /    │  │ tables → stacked cards <768  │
│ ·Stubs │ table / wizard      │  └──────────────────────────────┘
└────────┴─────────────────────┘
```

Nav is role-locked (`WEB-BR-001`): admin = Dashboard, Tenants, Cities, Partners, Leads, Campaigns
(stub), Audit; school = Dashboard, Users/Verification, Notices, Clubs, Sections, Migration, Roster→14,
Ledger→12, AI Matrix→09, Tutors→10, Webhooks→14; partner = single status screen.

| Component | Server/Client | Notes |
| --- | --- | --- |
| `PortalLayout` (per role) | Server | Auth gate re-checks claims; renders `FORBIDDEN` page on mismatch |
| `StatCard` | Server | Value + caption + link; placeholder variant (`WEB-BR-009`) for revenue cards |
| `DataTable` (TanStack) | Client | Keyboard-complete, paged 25, sortable columns |
| `StubRoute` | Server | Branded empty state: "এই স্ক্রিনটি মডিউল NN-এ আসছে / ships in module NN" |

**States** — Loading: skeleton matching card/table layout · Empty: explanation + primary action ·
Error: boundary with retry + `X-Request-Id` · Success: toast + revalidated data.

### 2.4 Create-school wizard — `/admin/tenants/new`

**Layout** — 3-step wizard in a centred panel: ① City + bn/en school names (city from 04 picker
data) ② first School Admin (name, BD phone) ③ review summary → confirm → success panel linking to
the tenants list. Stepper shows progress; each step validates before Next.

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `WizardShell` | Client | Focus moves to step heading; unsaved-changes guard |
| `CitySelect` | Client | Loads `GET /hierarchy/cities` |
| `ReviewPanel` | Client | Names exactly what will be created (`WEB-BR-007`) |

**States** — `CONFLICT` maps `hierarchy.school.name_duplicate` to the name field; submit disabled
while pending; success panel offers "create another".

### 2.5 Partner approval queue — `/admin/partners`

**Layout** — TanStack table (status tabs: pending/approved/rejected/suspended) → row opens detail
drawer: company, contact, targeting text, submitted date → sticky decision bar: Approve (confirm
dialog) · Reject (reason dialog) · Suspend (reason dialog).

| Component | Server/Client | Notes |
| --- | --- | --- |
| `VendorTable` / `VendorDrawer` | Client (TanStack Query) | Pending tab default |
| `ReasonDialog` | Client | Shared with verification reject; 10–500 counter |

**States** — `CONFLICT` (decided elsewhere) refreshes row; audit toast confirms decision recorded.

### 2.6 Leads pipeline — `/admin/leads`

Table with type/status filters, contact, school/city, source/utm, created; the status cell is a
restricted dropdown (only legal next states per INV-001) with optimistic update + rollback toast on
failure. Converted pilot leads surface a "create tenant" shortcut into the wizard (US-007 link).

### 2.7 Audit viewer — `/admin/campaigns`, `/admin/audit`

Campaigns: `StubRoute` (module 13). Audit: server-rendered read-only table (newest first) with
entity/action/school filters + cursor pager; every row shows actor, action, entity, timestamp; no
mutation affordance exists (append-only by 01).

### 2.8 School dashboard — `/school`

Four `StatCard`s (students, active sections, pending verifications, notices last 30 d) from
`GET /institution/stats`; pending-verification card links to `/institution/users`; revenue/ledger-style cards
use placeholder variant. Partial stats render with per-source flags ("notices count temporarily
unavailable").

### 2.9 Verification queue — `/institution/users`

**Layout** — filter tabs (pending/approved/rejected) + TanStack table: name, role badge, masked
phone, evidence link (opens in new tab), submitted (relative), reminder count, SLA badge
(`WEB-BR-013`: within 48 h → neutral; 48–72 h → amber "SLA বাকি"; > 72 h → red "SLA অতিক্রম"),
row actions Approve / Reject.

| Component | Server/Client | Notes |
| --- | --- | --- |
| `VerificationTable` | Client (TanStack Query, poll 60 s) | `GET /verification-requests` (03) |
| `RejectReasonDialog` | Client | Required reason, counter, submit disabled until valid |

**States** — approve → confirm → row leaves queue (toast); `CONFLICT` → "already decided" +
refetch; empty → "no pending requests" with dashboard link.

### 2.10 Notice board + composer — `/institution/notices`, `/institution/notices/new`

**Board layout** — pinned-first list: pin icon, title, scope badge (school/section), date,
attachment chip; row actions pin-toggle (`PATCH …/pin`) and delete (confirm). Composer layout:
title; body tabs বাংলা (required) / English (optional); audience radio (school | section → section
select from 04 data); attachment (PDF/image via 05 presign → PUT R2 → confirm, progress chip);
pin switch; one-way explainer banner; Preview dialog; Publish.

| Component | Server/Client | Notes |
| --- | --- | --- |
| `NoticeComposer` | Client (RHF) | Body assembled bn-first `bn\n\n—\nen` (OQ-4 default); caps per part |
| `AttachmentUploader` | Client | Blocks publish while upload pending; retry on failure (edge 8) |
| `NoticeBoard` | Client (TanStack Query) | Reuses 05's `notices:*` revalidation |
| `NoticePreview` | Client | Renders exactly the assembled body + attachment |

### 2.11 Clubs + sections — `/institution/clubs`, `/institution/sections`

Clubs: queue table (group name, creator, created) with Approve (creator becomes owner; 05 endpoints)
/ Decline. Sections: table grouped by session year + "new section" dialog (classLevel, name,
sessionYear); archive with `CONFLICT` explanation when enrollments exist (`hierarchy.section.*` copy).

### 2.12 Migration wizard + status — `/institution/migrations/new`, `/institution/migrations/[id]`

**Layout**

```text
Step 1            Step 2                  Step 3           Status page
┌───────────┐   ┌───────────────────┐   ┌────────────┐   ┌──────────────────┐
│ Session   │   │ Results: counters │   │ Confirm:   │   │ State: COMMITTED │
│ year pick │ → │ PROMOTED/GRADUATED│ → │ action     │ → │ counters live,   │
│ [Dry run] │   │ /RETAINED/ERROR   │   │ counts +   │   │ item table,      │
│           │   │ table (ERROR rows │   │ warning    │   │ audit note       │
│           │   │ expand detail)    │   │ [Commit]   │   │ (poll while      │
│           │   │ commit disabled   │   │            │   │  COMMITTING)     │
└───────────┘   └───────────────────┘   └────────────┘   └──────────────────┘
```

Errors in step 2 keep commit disabled with fix guidance (US-015); step 3 posts `dryRun:false`
(PREVIEWED) then commit on confirm; runs list (`/institution/migrations`) re-opens any run.

### 2.13 Stubs — `/institution/roster|ledger|matrix|tutors|webhooks`, `/partner`

`StubRoute`: icon + "ships in module NN" (bn/en) + what will live there + back link. `/partner`:
shell + status card — pending → "your account is pending approval" (`partner.state.pending`);
rejected → reason shown; approved → "portal opens with module 11" notice.

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| ROI: students / notices / fee cycles | number steppers + slider | int ranges (§6, module 01) | 500 / 20 / 3 | — |
| Pilot: contact name, phone, school, city, students, message | inputs / `CitySelect` / textarea | shared lead schema | bn locale labels | — |
| Partner: company, contact, phone, email, targeting | inputs / textarea | shared partner schema | — | email optional |
| School create: city, nameBn, nameEn, admin name + phone | select / inputs | shared school schema | current session year context | — |
| City create: nameBn, nameEn, launch flag | inputs / switch | shared city schema | launch=false | — |
| Section: classLevel, name, sessionYear | select / inputs | shared section schema | current session | — |
| Notice: title, bodyBn, bodyEn, scope, sectionId, pin, attachment | inputs / tabs / radio / switch / file | shared notice schema | scope=school, pin=false | sectionId required iff scope=section |
| Verification reject / partner reject/suspend: reason | dialog textarea | 10–500 required | — | — |
| Migration: fromSessionYear | select (≥ 2026) | shared migration schema | previous session | — |
| Lead status | row dropdown | transition table client-mirrored | current status | — |

Submission: same Zod schema on the server (Route Handler re-validation) · disable while pending ·
map `fields` errors to inputs · never lose input · unsaved-changes guard on all admin wizards and
the composer.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Public read (landing/download) | Server Component → static/ISR; no api call needed except lead POST |
| Public write (leads) | Client form → Route Handler → generated `openapi-fetch` → api → success panel |
| Portal reads | Server Component first paint → TanStack Query hydration for tables (queues, partners, leads, sections) |
| Mutation | Server Action / Route Handler → generated client → api → toast + `revalidateTag`/query invalidation |
| Migration status | Poll `GET /institution/migrations/{id}` every 3 s while COMMITTING → stop on terminal state |
| Attachment | Client → `POST /media/upload-url` → PUT R2 → `POST /media/{id}/confirm` → attach id to notice |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Hero illustration I-1 | 1.6 s SVG scene animation + ≤6px subtle idle float | page load | chaos → order transformation | static final frame |
| Feature spotlight carousel | 6 s autoplay progress bar + slide crossfade via `framer-motion` | autoplay timer / user click / arrow key | feature discovery | pause autoplay; instant slide switch |
| Draggable comparison slider | Smooth clip-path resize with mouse/touch/keyboard handles | drag / ArrowLeft / ArrowRight | contrast of WhatsApp vs Kushol | slider buttons still functional |
| ROI result | 400 ms count-up (once per change, interruptible) | inputs change | payoff attention | instant value swap |
| Admin desk demo hotspots | 250 ms fade + scale popover with highlight pulse | hotspot click | admin feature interaction | instant highlight without pulse |
| Mobile sticky CTA bar | 200 ms translate-y slide in/out | scroll past hero / form entering viewport | persistence of primary action | instant show/hide without transition |
| Wizard panel slide | 200 ms translate + fade | step change | progression | crossfade-instant |
| Dialog/sheet | scale-fade 150 ms | open/close | context switch | instant |
| Toast | slide-in 150 ms, auto-dismiss 4 s | mutation result | feedback | fade only |
| Skeleton shimmer | 1.2 s loop | loading | data arriving | static grey blocks |
| SLA badge | colour only (no pulse) | overdue | urgency without motion | same |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Landing | single column, sticky CTA, calculator stacked | 2-col hero/ROI | 3-band layout per wireframe |
| Download | stacked platform cards | centred column | centred column |
| Portals (target ≥ 768) | degraded single column: sidebar → drawer, tables → stacked cards | topbar + drawer nav, tables scroll-x | fixed sidebar + content |
| Tables | card-stack rows (label: value) | horizontal scroll with sticky first column | full table |
| Wizard | full-width steps | centred panel 560 px | centred panel 640 px |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order per screen
- [ ] Keyboard path complete; focus visible and never lost; focus moved per wizard step and into dialogs, restored on close
- [ ] TanStack tables keyboard-complete (arrow navigation, row action order, aria-rowcount)
- [ ] Labels, descriptions, error announcements (`aria-live` on form errors + toasts)
- [ ] `<html lang>` flips bn/en; Bengali never rendered in Inter; `lang` attributes correct on mixed copy
- [ ] Contrast WCAG 2.2 AA in light theme, both locales
- [ ] Motion: reduced-motion variant verified per §5
- [ ] axe (Playwright) clean on `/`, `/download`, `/admin/*`, `/institution/*`, `/partner`

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold: tokens only (no raw hex in `applications/web`),
deep-teal primary for CTAs, logo lockup 28–32 px with clear space and accessible name "Kushol
Connect — Home", Hind Siliguri for all Bengali, Inter for Latin/numerals (tabular figures in
tables/ledgers), swoosh-gray never used as text colour. Every string verified in bn + en via the
CI catalog parity gate (namespaces `landing.*`, `admin.*`, `school.*`, `partner.*`, `validation.*`
added to module 02's whitelist — additive, parity-gated).

## 9. Task Checklist

- [x] `WEB-FE-001` — 2026-10-03 Route groups + middleware (session presence → `/login?next=`), role layouts for `/admin`, `/school`, `/partner`
- [x] `WEB-FE-002` — 2026-10-03 Locale cookie + `LocaleProvider` wiring; `<html lang>` bn default; toggle preserves form state
- [x] `WEB-FE-003` — 2026-10-03 Landing: header/footer/hero/trust/partners sections (static, bn/en)
- [x] `WEB-FE-004` — 2026-10-03 `RoiCalculator` + `ROI_ASSUMPTIONS` constant + formula/disclaimer display
- [x] `WEB-FE-005` — 2026-10-03 `PilotForm` (Route Handler → `POST /leads`, retry-safe)
- [x] `WEB-FE-006` — 2026-10-03 `VendorInquiryForm` (→ `POST /partner/register`)
- [x] `WEB-FE-007` — 2026-10-03 `/download` + flag-gated `DownloadButtons` + `QrPlaceholder` + click lead
- [ ] `WEB-FE-008` SEO suite: per-locale Metadata, OG image, JSON-LD Organization, `sitemap.ts`, `robots.ts`
- [x] `WEB-FE-009` — 2026-10-03 Admin dashboard (`GET /admin/stats`) + placeholder cards (`WEB-BR-009`)
- [x] `WEB-FE-010` — 2026-10-03 Tenants list (TanStack Table)
- [x] `WEB-FE-011` — 2026-10-03 Create-school wizard (04 endpoints, review step, CONFLICT mapping)
- [x] `WEB-FE-012` — 2026-10-03 Cities management (`POST /admin/cities`)
- [x] `WEB-FE-013` — 2026-10-03 Partner queue + drawer + `ReasonDialog` (approve/reject/suspend)
- [x] `WEB-FE-014` — 2026-10-03 Leads pipeline (filters, transition dropdown, optimistic update)
- [x] `WEB-FE-015` — 2026-10-03 Audit viewer (`GET /admin/audit-log`, filters + pager)
- [x] `WEB-FE-016` — 2026-10-03 Campaigns stub route
- [x] `WEB-FE-017` — 2026-10-03 School dashboard (`GET /institution/stats`, partial-flags)
- [x] `WEB-FE-018` — 2026-10-03 Verification queue (03 endpoints, SLA badge, reject reason, poll)
- [x] `WEB-FE-019` — 2026-10-03 Notice board (pin/delete controls)
- [x] `WEB-FE-020` — 2026-10-03 Notice composer (bn/en tabs, scope picker, pin, preview, one-way banner)
- [ ] `WEB-FE-021` `AttachmentUploader` (05 presign → PUT → confirm, retry)
- [x] `WEB-FE-022` — 2026-10-03 Clubs approval queue (05 endpoints)
- [x] `WEB-FE-023` — 2026-10-03 Sections manager (create/archive + CONFLICT copy)
- [x] `WEB-FE-024` — 2026-10-03 Migration wizard (dry-run → results → PREVIEWED → commit) + runs list + status page poll
- [x] `WEB-FE-025` — 2026-10-03 Stub routes (roster/ledger/matrix/tutors/webhooks) + partner shell states
- [x] `WEB-FE-026` — 2026-10-03 Branded 404 + role-aware FORBIDDEN pages
- [ ] `WEB-FE-027` `DataTable` keyboard/aria pass; focus management lib for wizards/dialogs
- [x] `WEB-FE-028` — 2026-10-03 Motion per §5 with reduced-motion variants
- [x] `WEB-FE-029` — 2026-10-03 bn/en catalog keys (`landing.*`, `admin.*`, `school.*`, `partner.*`) + parity gate green
- [ ] `WEB-FE-030` axe Playwright suite + CWV budget check (Lighthouse CI) on `/` and `/download`
