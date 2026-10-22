# Command Center Web — Progress

**Module:** `07-command-center-web`  
**TODAY:** `2026-10-03`  
**Build status:** Stage 4 complete (agent-side) · waiting Gate 2 SQL  
**Queued next (owner 2026-10-03):** after this module finishes → build `11-campus-commerce` (depends on 07)

---

## Stages

| Stage | Status | Date | Notes |
| --- | --- | --- | --- |
| 1 Read & plan | ✅ | 2026-10-03 | Owner approved ("1" / go ahead) |
| 2 UI (`04`+`05`) | ✅ Gate 1 | 2026-10-03 | Fixture-driven landing/admin/institution/partner; app N/A. Owner said go ahead on concept |
| 3 Docs sync | ✅ | 2026-10-03 | Checklists ticked; README 🚧; gaps listed |
| 4 Backend (`03`) | ✅ code · ⏳ Gate 2 | 2026-10-03 | Migrations + leads/partners/webconsole + handlers; unit tests green |
| 5 Integration (`06`) | ⬜ | — | Swap fixtures → generated client after Gate 2 |
| 6 Gaps & verification | ⬜ | — | |

## Gates

| Gate | Status | Date | Evidence |
| --- | --- | --- | --- |
| 1 UI approval | ✅ (owner “go ahead”) | 2026-10-03 | Concept build approved in chat |
| 2 SQL run | pending | — | Owner must migrate (commands below) |
| 3 Integrated flows | pending | — | |
| Final Delivered | pending | — | |

## Defaults relied on

| Source | Default |
| --- | --- |
| OQ-1…6 | As Stage 1 plan |
| Deps 03/04/05 | Built against existing exports + fixtures; not all 🟢 |
| Dirty tree | Continued on `module/07-command-center-web` from prior WIP |

## ADRs / decisions

| ADR | Decision |
| --- | --- |
| ADR-1 | Stage 2 UI remains fixture-driven until Gate 2 + Stage 5 client swap |
| ADR-2 | `leads` rate class: 10/h/IP wired; 3/min burst deferred (G-7) |
| ADR-3 | Partner re-approve from suspended/rejected allowed (OQ-5) |

## Evidence

| Check | Result |
| --- | --- |
| web `pnpm test` | 163 passed (Stage 2) |
| api `go test -race ./internal/leads ./internal/partners ./internal/webconsole` | ok |
| api `go vet` on those + httpapi | clean |
| Dev server | **Not started by agent** — owner stack already running |

## Gate 2 — owner run (shared Neon DB)

```bash
cd /Users/rahul/Desktop/aiWorkspace/me/kushol-connect/applications/api
go run ./cmd/api migrate-status
go run ./cmd/api migrate up --confirm
```

Migrations to apply:

| Version | File | Purpose |
| --- | --- | --- |
| `20261015090000` | `web_landing_leads` | `landing_leads` + CHECKs + indexes |
| `20261015091000` | `web_vendor_accounts` | `vendor_accounts` + trgm search + portal_user unique |
| `20270312092000` | `partner_module_refinement` | `partner_leads`, `partner_kyc_documents`, `partner_verification_logs`, `partner_members`, `partner_audit_logs`, `users.role` partner constraint, `users.xp_balance` |

---

## Partner Module Global Refinement (2026-10-21)

- **Terminology Migration**: Global rename of Partner → Partner across docs, OpenAPI 3.1 contracts, DB migrations, SQLC, Go backend, Web Command Center, and Expo App.
- **Partner Self-Registration & KYC**: Landing page public registration (`/register/partner`), 100% free (`registration_fee = 0`), R2 presigned direct KYC uploads (Trade License, NID, TIN/BIN), verification preference (`PHYSICAL_VISIT` or `VIRTUAL_MEETING`), reference ID (`KUSHOL-PARTNER-XXXX`), and application status tracker.
- **Super Admin Partner Leads Pipeline**: Super Admin leads queue (`/admin/partner-leads`), statuses (`NEW_LEAD`, `UNDER_REVIEW`, `MEETING_SCHEDULED`, `VERIFICATION_COMPLETED`, `APPROVED`, `REJECTED`), KYC document inspection, physical/virtual visit logging, and atomic approval.
- **Strict Pre-Approval Login Gate**: Authentication layer returns 403 Forbidden (`PARTNER_APPROVAL_PENDING` / `PARTNER_REJECTED`) until explicitly approved.
- **Atomic Provisioning on Approval**: Marks lead approved, activates partner tenant with agreed delivery commission (15%–20%), creates applicant user with role `partner`, assigns Seat #1 (`PARTNER_ADMIN`), provisions internal chat room (`system_key = 'partner:' || partner_id`, FCM topic `partner_{partner_id}_team`), and logs audit entry.
- **Unified Partner Dashboard**: Dynamic routing (`/dashboard`), sidebar navigation (`PARTNER_ADMIN` vs `PARTNER_EXECUTIVE`), partner-led institution onboarding (`onboarded_by_partner_id`) with 100% free campaigns on own onboarded schools, 5 free team seats quota, 15%–20% delivery commission escrow, store & orders, referrals XP, and immutable audit logs matching `/admin/audit`.
- **Paid Add-On Campaign Suite & Student Mobile Volunteering**: Dual rosters (Participants & Volunteers), Volunteer Task Management with proof photo review, XP rewards ledger, and tamper-evident PDF E-Certificates. Students can explore active campaigns/events from mobile app, apply to volunteer, receive notifications, execute tasks, earn XP in their ledger (`users.xp_balance`), and verify e-certificates.

### Evidence & Checks Completed
- **`applications/api`**: `go vet ./...` (0 errors), `go build ./...` (0 errors), container-free unit tests in `internal/partners` and `internal/auth` passed.
- **`applications/web`**: `pnpm typecheck` (0 errors), `pnpm test` (44 test suites, 310 tests passed).
- **`applications/app`**: `pnpm typecheck` (0 errors), `catalog.test.ts` passed.

### Pending Owner Run
- Database migration execution:
  ```bash
  cd applications/api
  go run ./cmd/api migrate up --confirm
  ```
- Integration test suite (requires testcontainers / live DB):
  ```bash
  cd applications/api
  make test-integration
  ```

After you confirm migrate output, Stage 5 (fixture→client + IT pending) continues.

## Working-tree note

Branches: `applications/web` + `applications/api` on `module/07-command-center-web`. No commits unless you ask.

---

## Console additions (2026-10-04, fixture-seam build per owner instruction)

Built directly in the web console (one-file fixture seams; the api contracts below land additive
with this module's console-glue pass):

| Area | What exists now |
| --- | --- |
| Personas | `/admin` serves **three admin kinds** — Kushol admin (super_admin), Institution admin (institution_admin) and Partner admin (vendor_admin): role switcher in the shell, role-filtered nav per persona (platform / manage-institution / manage-store), role-aware landing for each. Fixture store `consoleRoleFlags` persists the choice; the api stays the authority (WEB-BR-008) |
| Sidebar | Kushol logo (32px) + collapse toggle in the header row; Tuition entry → `/tuition`; Cities + both onboarding entries removed (onboarding CTAs live on the institutions/partners pages); bottom user block is a **popover** (profile, role badge, Log out via the real logout seam) |
| Typography | Panel-wide scale bump (`data-admin-panel` in globals.css: text-xs 14px, text-sm ~15.6px, base 17px) + card/table polish (rounded-2xl bg-card shadow-sm, roomier cells, token-only colours) |
| Audit | `/admin/audit` on the shadcn DataTable (TanStack v9 server-mode via fixtures) with **Access-log tab** + filters for both logs (actor/entity; method/status-class). Access log is additive (no 07 schema yet — `AccessLogEntry` in the fixture) |
| Chat | `/admin/chat` — **WhatsApp-fidelity** messenger (green header, wallpaper thread, bubble tails, ✓✓ ticks, unread pills, round composer); `wa-*` colours registered as design tokens (tokens.ts → theme:generate); fixture `console-chat.ts`. All three personas reach chat from their nav |
| Leads | Requested **Institution** column, **Review** details popup, **Accept / Reject-with-reason** (`decideLead` → converted/archived; ≥5-char reason) |
| Partners | **Partner onboarding** wizard (`/admin/partners/new`, creates APPROVED + audit row), **Partner store** oversight (`/admin/partners/[id]`: storefront, order funnel, products/stock), **Review** details popup, **Item approvals** — partner registers items as pending_review; stock updates are FORBIDDEN until a Kushol admin approves (reject needs a reason) |
| Tenants | **School details** `/admin/tenants/[id]` (profile, stats, sections, recent audit) + per-school **LMS connector**: only the Kushol admin configures base URL/schedule; **Sync now** per resource (students / teachers / classes & sections); school admin is read-only (FORBIDDEN guard mirrors the api) |
| Geography | Cities removed from nav; default dataset = all 8 divisions + major cities bn/en (`fixtures/bd-geo.ts`); onboarding wizard selects **Division → City** (cascading, locale-aware) |
| Terminology | "School onboarding" renamed **Institution onboarding** (module 14 terminology) |

**Additive api contracts for the glue pass (07):** `GET /admin/access-logs`; console chat
(conversations/messages/send); `POST /admin/leads/{id}/decision`; partner onboarding + `GET
/admin/partners/{id}/store`; `GET /admin/schools/{id}` details; tenant LMS connector
(config/schedule/sync-now, kushol-admin-only); product-approval state machine (partner registers
→ kushol approves → stock unlocked); BD division/city reference data.

### Route + terminology correction (2026-10-04, owner)

- The institution portal moved from `/institution/*` to **`/institution/*`** (app routes only — the api
  contract paths `/api/v1/school/*` are unchanged); `SchoolPortalLayout` →
  `InstitutionPortalLayout`; login dashboard-path sends `school_admin` to `/institution`.
- Terminology: the panel says **institution (প্রতিষ্ঠান)** everywhere — "School dashboard" →
  "Institution dashboard", persona label "Institution admin", landing nav "For institutions";
  the tenants table labels `institution_type` values with domain terms (বিদ্যালয়/কলেজ).
- Three admin personas now share the panel: **Kushol admin, Institution admin, Partner admin** —
  each with their own nav (platform / manage-institution / manage-store) and dashboard; chat is
  reachable from all three. WhatsApp-style chat theme tokens (`wa-*`) registered in tokens.ts.

---

## Landing page redesign (2026-10-09, owner prompt)

Redesigned `/` in `applications/web` as an interactive, illustrated, feature-focused promotional funnel for pilot schools (`#pilot`), partners (`#partners`), and app downloads (`#download`).

- **Architecture:** Split into 16 modular components in `src/components/landing/`:
  - `AnnouncementBar`: Thin deep-teal dismissible announcement banner with session storage memory.
  - `LandingHeader`: Sticky header (64px → 56px on scroll), logo lockup, 4-item compact nav, switch-variant `LanguageToggle`, login, and `#pilot` CTA.
  - `HeroSection`: LCP-optimized hero (instant H1 paint, 3 fact chips) with multi-tone atmospheric gradient background, architectural grid texture, ambient glowing spotlights, and `HeroDeviceShowcase` (iPhone 18 Pro + Google Pixel emulator mockups with real app screenshot).
  - `HeroDeviceShowcase`: Dual emulator showcase featuring iPhone 18 Pro (titanium frame, Action Button, Camera Control, Dynamic Island) and Google Pixel (Pixel button layout, centered punch hole, Google G mark) with interactive platform switcher.
  - `BeforeAfterSlider`: Draggable comparison slider (WhatsApp chaos vs Kushol order) with mouse, touch, and keyboard (ArrowLeft/Right) handles.
  - `FeatureSlider`: 12-feature spotlight carousel (`framer-motion`) with 5 category filters, 6s autoplay progress bar, play/pause controls, and keyboard navigation.
  - `HowItWorks`: 3-step structured verification & auto-grouping process.
  - `RoleTabs`: 4 personas (Guardians, Teachers, Institutions, Partners) with 3 verified benefits each and role CTAs.
  - `DeskDemo`: Interactive school admin desk illustration with clickable feature hotspots (Roster, Notices, Sync).
  - `RoiCalculator`: Range sliders + number inputs with 400ms count-up payoff and comparative SMS cost visualization.
  - `TrustSafety`: Full-bleed deep-teal band with City → Institution → Section hierarchy diagram and 4 security pillars.
  - `PilotSection`: Pilot school pitch with strictly real "২–৩টি প্রতিষ্ঠান" seat limit + `PilotForm`.
  - `VendorSection`: Partner reach pitch with I-10 audience targeting illustration + `VendorInquiryForm`.
  - `AppDownloadSection`: Mobile app promo with QR code, disabled store badges, and pointer 3D tilt.
  - `FaqAccordion`: 6 real objection-resolving questions in clean accordion.
  - `FinalCtaBand`: Full-bleed deep-teal closing banner.
  - `LandingFooter`: Brand lockup, compact nav links, legal, contact, and copyright.
  - `MobileStickyCta`: Mobile-only bottom floating action bar that auto-hides when forms/footer are in viewport.
  - `Illustrations`: 14 custom inline SVG vector scenes (I-1 to I-14) using exclusively token palette.
- **Brand & Theme Compliance:**
  - Registered promotional accent `marigold` (`#F2A93B`) in `tokens.ts` and generated into `theme.css`.
  - Replaced all multi-hue Tailwind classes (`sky-`, `purple-`, `emerald-`, `amber-`) with token scales.
  - Purged all fabricated metrics, fake testimonials, and unverified AI grouping claims; seat count strictly "২–৩টি প্রতিষ্ঠান".
- **Verification:**
  - Vitest suite: 28 test files, 220 tests passing (including `feature-slider.test.tsx`, `before-after-slider.test.tsx`, and `hero-device-showcase.test.tsx`).
  - TypeScript: `pnpm typecheck` (`tsc --noEmit`) passes with 0 errors.
  - ESLint & Prettier: clean with 0 warnings or errors.

## Admin LMS pages — 2026-10-09 (owner request)

`/admin/lms` (Kushol admin only — SUPER_NAV "LMS", Blocks icon): all institutions' LMS pull
connectors (list: institution, name, base URL, schedule, enabled, last run + status), **Configure
new LMS** dialog (institution picker, name, HTTPS base URL, bearer/api-key auth + header,
credential, schedule preset) enforcing one-connection-per-institution, and per-row + **Sync all**
triggers. `/admin/lms/[id]` details page: config summary (credential masked), provisioning stats
(sections · teachers+students · enrollments · **chat groups ensured** — the official section
groups + the institution's teachers group), run history (status/trigger/counters/errors), enable/
disable + sync-now. RBAC renders by session role (use-console-role); fixture seam
(`fixtures/lms.ts` admin section) mirrors the api's `LmsConnection`/`LmsSyncRun` contract —
swap point for 14's real endpoints, documented in-file. i18n `admin.lms.*` (en+bn, catalog
parity kept); 3 new fixture tests (220/220 green).
