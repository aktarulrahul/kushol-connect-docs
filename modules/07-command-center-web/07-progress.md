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

``bash
cd /Users/rahul/Desktop/aiWorkspace/me/kushol-connect/applications/api
go run ./cmd/api migrate-status
go run ./cmd/api migrate up --confirm
``

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
  ``bash
  cd applications/api
  go run ./cmd/api migrate up --confirm
  ``
- Integration test suite (requires testcontainers / live DB):
  ``bash
  cd applications/api
  make test-integration
  ``

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

## Live institution & partner directory — 2026-10-23 (owner request)

Owner: "remove all mock institutions and partner … institutions can be onboarded directly from
/institution, from a partner's LMS, or by a partner from its details page". The console's
institutions and partners now read the database through new Kushol-admin endpoints
(`internal/directory`, contract tag `console`):

| Surface | Now |
| --- | --- |
| `/institution` (Kushol admin) | `GET /api/v1/admin/institutions` — city, students, **Onboarded via** (direct · partner · partner's LMS) with filters; **Onboard institution** → `POST /api/v1/admin/institutions` (live city list, EIIN, address, optional first admin — verified, OTP sign-in) |
| `/institution/[id]` | `GET /api/v1/admin/institutions/{id}` — Overview (stats, contact, how it joined), Teachers, Students, Classes, **LMS** (its own LMS; hidden when it came from a partner's LMS), LLM placeholder, Audit |
| `/admin/partners` | `GET /api/v1/admin/vendors` + institution counts; **Add partner** → `POST /api/v1/admin/partners` (approved) |
| `/admin/partners/[id]` | `GET /api/v1/admin/partners/{id}` — Overview (address, office hours, description, commission), Institutions (+ **Onboard institution** for this partner), **LMS** tab; approve/suspend live. Fixture Campaigns/Store/Activity tabs removed |
| `/admin` dashboard, `/admin/cities`, `/admin/applications` | Stats, institutions, partners and partner approvals live; vendor persona home reads `/vendor/dashboard/metrics` |
| Removed | `/admin/lms` (LMS lives inside partners/institutions — module 14), fixture `SCHOOLS`/`VENDORS`/store/school-details/school-LMS seams and the admin-LMS fixture section |

Data: migration `20270313090002` **deletes** the demo tenant (2 demo institutions + everything
under them, their accounts, the demo partner) — irreversible, owner choice; `20270313090003` seeds
partner **e-jonaki** (+ its LMS); `20270313090001` adds partner address/office hours and
institution address. Evidence: web `tsc` clean, eslint clean on changed files, vitest 315/315;
api `internal/directory` tests (onboarded-via rules, phone masking, Kushol-admin gate, validation
before the database). Gate 1 (owner UI review) pending.

### Partner human ids and more partner tabs — 2026-10-23 (owner request)

- **Readable partner URLs:** every partner has a `human_id` (slug of the company name, numbered on
  collision; filled by a `vendor_accounts` insert trigger so every sign-up/approval path gets one;
  backfilled in `20270313090001`). e-jonaki is `ejonaki` → `/admin/partners/ejonaki`. The api
  accepts a human id or a uuid on `/api/v1/admin/partners/{partnerId}*`; an old uuid link redirects
  to the readable URL. Approve/suspend still send the uuid.
- **New partner tabs (live, read-only):** Access (`…/access` — owner login, both team tables, seats),
  Store (`…/store` — storefronts, orders by status, completed sales + commission, latest 20 orders),
  Campaigns (`…/campaigns` — ad campaigns and events with tickets), Logs (`…/logs` — the partner's
  own portal audit tables plus Kushol-admin `audit_log` actions on it or its LMS, newest 100).
- Evidence: api build/vet/tests/contracts-check clean (new: active-seat count, partner tabs refuse
  non-Kushol-admins); web tsc + eslint clean, vitest 317/317.


### Full vendor → partner rename — 2026-10-23 (owner: "there will no vendor, it will be partner")

- **Scope:** the product noun is now `partner` everywhere — DB (`vendor_accounts` → `partner_accounts`,
  `vendor_storefronts` → `partner_storefronts`, ledger/payouts/XP/audit/members renamed; the lean
  `partner_members`/`partner_audit_logs` twins and `schools.onboarded_by_vendor_id` were **merged**
  into the richer renamed tables), value vocabularies (`users.role='partner'`, `PARTNER_ADMIN`,
  `partner_inquiry`, chat key `partner:`, referral prefix `KUS-PART-`, RBAC module `partners`),
  API paths/operationIds/schemas (`/api/v1/partner/*`, `/api/v1/admin/partners` with the approval
  queue folded in), Go (`internal/vendors` merged into `internal/partners` as `Lifecycle`), web
  (`/vendor/*` shims and `/admin/vendors` redirects deleted; fixtures, i18n keys, landing ids),
  and the app (schema fields, session roles). `internal/sync` "vendor" (the LMS vendor) and the
  SMS-gateway "vendor" comments are a different noun — intentionally untouched.
- **Migration:** `20270313090004_partner_rename.up.sql` (+ down, name-restoring; data merges are
  best-effort). **Pending owner run together with `20270313090000`–`090003`** (Owner Rule 1) —
  these were not yet applied, which is what produced the `human_id` 500s in the api log (G-24).
- **Evidence (agent-side, no app run):** api `go build`/`go vet`/`go test -race ./...` green,
  `make contracts` regenerated with no drift, `TestSpecValidates` green (three pre-existing
  unquoted-flow-description YAML bugs fixed along the way); web vitest 317/317 + `tsc` clean;
  app jest 419/419. `make lint` (api) and web eslint still report their pre-existing findings
  (unchanged by the rename); `pnpm contracts:check` has a pre-existing Windows spawn bug.

### Dev-DB repair migration — 2026-10-24 (owner report: `/admin/partners` + `/admin/institutions` 500)

- **Diagnosis (from logs only — no database session, Owner Rule 1):** `migrate.log` reported
  `database_version=20270313090004 … dirty=false`, yet Postgres rejected the directory queries with
  `column pv.human_id does not exist` / `column "human_id" does not exist` (42703). No sequential
  application of today's migration set can produce that state: `090003` seeds `human_id`, which only
  `090001` adds, so a clean `090004` marker reached through `090003` implies the column existed.
  Conclusion: the schema_migrations marker ran ahead of the applied content — `090001`–`090003`
  never executed, and golang-migrate never applies versions below the recorded one (`migrate up` is
  a permanent no-op there, so dev-start keeps printing "local schema up to date").
- **Fix forward** (applied files are never edited): `20270313090005_partner_human_id_repair`
  re-applies `090001`–`090003`'s effects idempotently on top of the renamed schema — `human_id`
  column + trigger + backfill + NOT NULL + check + unique index, `address`/`office_hours` on
  `partner_accounts`, `schools.address`, the demo-tenant purge (no-op when its targets are gone)
  and the e-jonaki seed (fixed ids, `ON CONFLICT DO NOTHING`). No-op on a fully-migrated database.
- **Evidence:** api `go build ./...` green; `TestExpectedVersionIsHighestUpFile` green with the new
  file as the embedded maximum. Gate 2 (owner migration run) pending.
- **Owner:** `cd applications/api && go run ./cmd/api migrate up --confirm` — or restart
  `dev-start.sh` — then reload `/admin/partners` and `/admin/institutions`.

### Add partner member from the Access tab — 2026-10-24 (owner request)

Owner: "in /admin/partners/e-jonaki, in access tab, add an option to add member … once member
added, both partner POC and new member will get mail", with the letter logo fixed to
`docs/logo/kusholConnect.png` for every email template.

- **Contract:** `POST /api/v1/admin/partners/{partnerId}/members` (Kushol admin, CSRF-checked;
  human id or uuid) with `AdminPartnerMemberInput` — firstName, lastName, email, phone (BD),
  designation, `modulePermissions` (`PartnerModulePermission` enum: event/store/campaign/
  institution × admin/contributor), optional notes. Returns the created `AdminPartnerMember`
  (now also carrying designation, notes, modulePermissions on reads).
- **Service** (`internal/directory/members.go`): Kushol-admin gate → validation before the
  database (name/email/phone/designation/notes lengths; permission vocabulary mirrored by the new
  `partner_members_module_permissions_chk` CHECK) → approved partners only (CONFLICT otherwise)
  → find-or-create the `partner` user by email (existing **non-partner** accounts are a CONFLICT
  — a school login never gains a partner seat; new accounts are VERIFIED for OTP sign-in) →
  duplicate membership is a CONFLICT → seat billable past `free_seat_quota` (portal rule) →
  seat + audit row (`partner.member_added`, shows in the partner's Logs tab) in one transaction.
- **Emails:** typed job `partner.member_added_email` (`internal/smsout`) sends two letters —
  the member's welcome and the POC's notice (partner name, designation, permission chips; **notes
  are never emailed**). POC = the partner account's email, else the portal owner's; duplicate
  addresses get one letter. Enqueueing is best-effort after commit (degraded SMTP logs + retries).
- **Logo:** every email template now embeds `docs/logo/kusholConnect.png` (869×287 wordmark;
  `smsout/email-logo.png` replaced, both letter templates sized 180×59). Hash-verified copy.
- **Web:** the Access tab gains **Add member** (approved partners only, title explains why it is
  disabled) opening `PartnerMemberDialog` — all owner fields incl. the permission multi-select
  grouped module × Admin/Contributor, seat hint (free vs billable), bn/en copy, aria-invalid
  states, success toast; the tab list refreshes and now shows each member's designation and
  permission badges.
- **Decisions:** new members sit at `PARTNER_EXECUTIVE` (the granular grants live in
  module_permissions; PARTNER_ADMIN stays the partner's own admin role); permission modules are
  the partner portal's surfaces (event, store, campaign, institution) × (admin, contributor).
- **Evidence (agent-side, no app run — Owner Rule 1):** api `go build`/`go vet`/`golangci-lint`
  clean on touched packages, `go test -race ./...` green (new: permission normalizer, validation
  matrix, admin-only gate, both-letters handler, degraded mode, duplicate-POC skip, permission
  labels), `make contracts` no drift, `TestSpecValidates` green (fixed two pre-existing
  unquoted-description YAML bugs in `LmsInstitutionSyncReport`); web `tsc` clean, prettier
  clean on touched files, vitest 322/322 (new: permission catalog, form validation, request-body
  builder), spec copy synced + TS client regenerated; eslint still reports its pre-existing
  findings elsewhere (G-21 pattern).
- **Pending owner:** migration `20270313090006_partner_member_details` (G-27) —
  `cd applications/api && go run ./cmd/api migrate up --confirm` — then click-through:
  /admin/partners/ejonaki → Access → Add member → verify the member row, both inboxes, and the
  Logs tab entry.

### Institution human-id URLs + chat oversight — 2026-10-24 (owner request)

Owner: "instead of show uuid in the url, show institution human id … add one more tab to see the
chat groups for this institution … in overview show the chat stats".

- **Readable URLs:** every school now carries `schools.human_id` (slug of `name_en`, numbered
  on collision, trigger-filled, backfilled; migration `20270313090007_school_human_id`, G-28).
  `GET /admin/institutions/{institutionId}` accepts the human id **or** uuid; the console links
  by human id (`institutionHref`) and old uuid links redirect. Partners set the pattern; the
  institution list/detail and the partner page's institution links all moved over.
- **Chat endpoints (Kushol admin, read-only):** the institution detail now embeds
  `chatStats` (total/active groups, messages total + today (Asia/Dhaka days), attachment count
  and storage bytes, last activity, incidents) and two new paths serve the Chat tab:
  `GET /admin/institutions/{institutionId}/chat-groups` (per-group numbers, busiest first) and
  `.../chat-groups/{groupId}` (roster, 14-day daily counts). DMs carry no school, so they are
  out of scope by definition.
- **Web:** new Chat tab — groups table (name/section, members, messages, today, attachment
  storage, last activity, incident badges: moderated (tombstoned) messages and uploads that never
  confirmed on R2); clicking a group opens the popup with its roster (group admin first, teacher
  badge), storage, daily volume bars and incidents. The Overview tab gained a Chat section
  (groups, today's messages across all groups, attachment storage, last activity).
- **Evidence:** api `go build`/`go vet`/`golangci-lint`/`go test -race` green (spec
  validates; one self-inflicted unquoted-YAML description fixed forward), `make contracts` no
  drift; web `tsc` clean, prettier clean, vitest 324/324 (new: institutionHref fallback,
  formatBytes).
- **Pending owner:** migration `20270313090007_school_human_id` (G-28) — URLs fall back to
  uuids until it runs; then verify /institution/<human-id> opens, the Chat tab lists e.g. the
  section groups of 01a169fa-a56d-79ab-8953-1f4ae424be90, and the popup shows the class teacher
  as group admin.

### Popups: fixed header/footer, scrollable body — 2026-10-24 (owner request)

- **Primitive:** `DialogContent` is now a `max-h-[90dvh]` flex column; `DialogHeader` and
  `DialogFooter` pin via `shrink-0`; new **`DialogBody`** (`grid min-h-0 flex-1
  content-start gap-4 overflow-y-auto`) is the scrollable middle.
- **Sweep:** the console + feature popups put their middle content in `DialogBody` — onboarding
  (institution/partner), partner add-member, institution chat-group, tuition-market pair, LMS sync
  report, messenger poll + group settings, admin leads (review + partner review), partner suite
  tabs, tuition market page, partner orders, moderation, applications, ads-ops. Small confirm
  popups and dialogs without footers stay on the primitive (nothing to scroll). Per-usage
  `max-h-* overflow-y-auto` classes on `DialogContent` were removed — the primitive owns the
  cap now.
- **Evidence:** web `tsc` clean, prettier clean on touched files, vitest 324/324; eslint on the
  touched files reports only pre-existing findings (unused imports, raw colors, fetch).

### Partner footprint stats (admin overview + portal dashboard) — 2026-10-24 (owner request)

Owner: "in overview tab, i need the all status(institution, chat group, total message, storage
used, event managed, store stock, order summary). also in partner loggedin dashboard, show same
stats".

- **One aggregate, two surfaces:** `GetPartnerFootprintStats` (`partner_accounts.sql`) computes
  the block in a single statement — institutions the partner brought (directly or through its LMS,
  the directory's definition), their chat groups / total messages / today's messages (Dhaka day) /
  attachment storage, campaigns managed (`ad_campaigns`), storefront products + stock units on
  hand (`inventory_items`), and the order summary (total / active = placed..shipped / completed /
  cancelled).
- **Contract:** new `PartnerFootprintStats` schema; `GET /api/v1/admin/partners/{partnerId}/stats`
  (Kushol admin) serves it, and `PartnerMetrics` gains a required `footprint` block so the
  partner's own dashboard gets the identical numbers from the live metrics endpoint.
- **Web:** the admin partner Overview tab opens with an "Activity at a glance" card row (plus total
  orders line); the partner portal home (`/partner`) now queries the live
  `/partner/dashboard/metrics` and renders the same footprint row under its existing cards.
  Storage sizes via `formatBytes`; bn/en copy under `admin.partners.footprint_*`.
- **Evidence:** api `go build`/`go vet`/`goimports`/`go test -race` green (partners,
  directory, smsout, gen/api; spec validates), `make contracts` no drift; web `tsc` clean,
  prettier clean, vitest 324/324, eslint clean on the touched files.
- **Pending owner:** none beyond the standing G-27/G-28 migrations (the stats read live tables and
  work without them); verify on /admin/partners/ejonaki → Overview and on /partner after login.

### Stat cards unified + Latin digits in Bangla — 2026-10-24 (owner request)

Owner: "make 4 stats in one row … big icon in left side and count in right side and in next line
some info … with some hover animation … create a common stats component for it. use it across the
application", and "in all bangla number not visible properly. english number is okay".

- **New primitive** `components/ui/metric-card.tsx` — `MetricCard` (icon tile left, count on
  the right of the same row, name + optional info line under it; hover lifts the card, tints the
  border and fills the icon tile) and `MetricGrid` (4 per row on wide screens). The DSN KPI
  `StatCard` (sparkline/delta, stat-card.tsx) is untouched and stays for period-comparison KPIs.
- **Used across the app:** partner footprint rows (admin overview + portal dashboard), institution
  detail Overview stat rows (counts + chat section), partner Access tab (seats/members), partner
  store totals (tone via `valueClassName`), portal home fixture stat cards.
- **Latin digits:** Bangla numeral glyphs (০–৯) render unreliably in our font stack, so every
  number now formats with `bn-BD-u-nu-latn` — `intlLocale` (i18n) and all hardcoded
  `"bn-BD"` Intl tags across 32 files now emit Latin digits in the Bangla UI (dates, prices,
  counts). Catalog tests updated to the new expectation (owner decision recorded).
- **Evidence:** web `tsc` clean, prettier clean on touched files, vitest 324/324 (i18n,
  primitives and auth-form suites updated to Latin-digit expectations), eslint clean on touched
  files (incl. two findings fixed in files being touched: raw `text-[11px]` length, redundant
  `??`).
- **Pending owner:** visual review only.
- **Light backgrounds:** MetricCard gained a tone prop (primary/success/warning/info) that paints the card with the theme soft tokens and matches the icon tile, filling with the tone solid on hover; footprint rows rotate all four tones (4 per row), Access/store/institution cards use semantic tones (pending=warning, awaiting delivery=warning, completed=success).

### Partner-member login fix + admin partner edit — 2026-10-24 (owner request)

Owner: "this user has been added to e-jonaki partner by kushol admin, why can't login this user"
and "add edit option so that kushol admin can update the partner information".

- **Login bugfix:** the OTP gate resolved the partner account only through
  `partner_accounts.portal_user_id` (the account owner), so every **team member** — portal
  invited or admin added — failed with the misleading 403 "UNDER_REVIEW" (the default status text
  when no lead matches the phone). `GetPartnerAccountForUser` now resolves via ownership **or
  active `partner_members` membership** (`status = 'active'`; removed seats excluded), and an
  approved partnership wins when a user belongs to more than one. Query-only fix — the gate
  itself still blocks non-approved accounts. Affects the auth module's flow (03 owns the
  handler; root cause and fix live in the shared partner query).
- **Admin partner edit:** `PATCH /api/v1/admin/partners/{partnerId}`
  (`AdminPartnerUpdateInput`, PATCH semantics — provided fields only) with validation
  (BD phone, email, commission 15–20%, name/description lengths), audited as `partner.updated`
  with the provided-field list, then re-reads the full `AdminPartner` view. Web: an **Edit**
  button in the partner header opens the prefilled dialog (company en/bn, contact, phone, email,
  commission %, address, office hours, description) with bn/en copy and inline validation; save
  refreshes the detail + list.
- **Evidence:** api `go build`/`goimports`/`go vet`/`go test -race` green (directory,
  partners, auth, smsout, gen/api), `make contracts` no drift, spec validates; web `tsc`
  clean, prettier + eslint clean on touched files, vitest 324/324.
- **Pending owner:** the login fix is query-only — no migration. Re-run OTP login as the member
  (aktarul.i1708@gmail.com) on /login — should issue tokens now. Then try Edit on
  /admin/partners/e-jonaki.
- Interactive footprint cards: institutions/events/store cards navigate to their tabs (partner page tabs are now state-controlled), and the chat-groups / messages / storage cards open popups backed by a new ListPartnerChatGroups query embedded in the stats payload (PartnerFootprintStats.groups). The chat-groups popup lists institutions with a group-count button that deep-links to /institution/<human-id>?tab=chat (the institution page reads the tab param under Suspense and keeps it through the human-id redirect).
- FIXED 500 on the institution detail page (found in applications/.dev/logs/api.log): GetInstitutionChatStats/ListInstitutionChatGroups/GetInstitutionChatGroup crashed with cannot scan NULL into *time.Time for institutions or groups with no chat activity. The last_activity_at aggregate is now COALESCEd to the epoch timestamptz sentinel and rendered as null by activityTime() in the directory handler.
- Member management (owner 2026-10-24): the Access tab team table gains per-row actions (edit, permissions, remove). API: PATCH/PUT/DELETE /api/v1/admin/partners/{partnerId}/members/{memberUserId} with AdminMemberUpdateInput (name, phone, designation, notes; PATCH semantics) and AdminMemberPermissionsInput (full set replace); remove is a soft-delete (status removed, seat freed, history kept) — all audited (partner.member_updated / partner.member_permissions_updated / partner.member_removed). Web: PartnerMemberActions with three dialogs, masked-phone hint (re-enter to change; email is the login and cannot change), removed rows show their badge with actions disabled.
- Institution-requests rename (owner 2026-10-24): the four school-requests endpoints moved to institution-requests paths — GET/POST /api/v1/admin/institution-requests (list, approve, reject) and POST /api/v1/institution-requests (public registration submit). Tag renamed to institution-requests; operation ids/schema names unchanged (internal only). Spec copies + TS clients regenerated for web and the mobile app; httpx + it_identity route tests updated; no live web/mobile call sites existed yet (both register flows are fixture-mode).
- FIXED 500 (owner report, found in api.log): the same NULL-scan crash had also been serving 500s on /admin/institutions/e-jonaki-lms through a stale pre-restart api process; after the watcher restart the fixed binary answers 401/200 correctly (verified by probe).
- R2 organized keys (owner 2026-10-24): uploads can declare a context (contextType/contextId on uploadMedia query params and the presign body) and land under readable prefixes — institution group chat {institution_human_id}/{group_name}/, kushol/partner group chat {partner_human_id}/{group_name}/ (kushol groups use a kushol prefix; the actor partner context names it), and user/event/campaign/lead/institution/partner files {entity_human_id}/. Omitted context keeps the legacy {kind}s/{owner}/{asset}.{ext} layout, so existing clients are unaffected.
- Supporting changes: migration 20270313090008 adds human_id to users + events (slug triggers + backfill; partner_leads uses its reference_code); new internal/mediakeys package implements media.ScopeResolver with membership/ownership checks (group membership for chat, partner membership for campaign/event/partner, school staff or onboarding partner for institutions, kushol admin for leads); media.New gains the resolver param; the api merges it in cmd wiring.
- Clickable institution stat cards (owner 2026-10-24): the Overview rows now jump like the partner page — students/pending → Students tab, teachers → Teachers, sections → Classes, and all four chat stats → the Chat tab (tabs are state-controlled; the ?tab= deep link still wins on load).
- LLM tab removed from the institution detail page (owner 2026-10-24): every institution now shows the LMS (Learning Management System) tab — own-LMS institutions get the connector form/workspace, partner-LMS institutions (e.g. e-jonaki-lms) get a card naming the partner LMS that syncs them with a jump to the partner LMS tab. Unused llm i18n keys removed.
- LMS tab hidden again for partner-synced institutions (owner 2026-10-24): after the LLM tab removal, the LMS tab shows only for institutions with their own LMS; partner-synced ones (e-jonaki-lms) stay managed on the partner page, so their detail page has no LMS/LLM tab at all.
### Partner plans + capabilities ("Manage Capabilities") — 2026-10-24 (owner request)

Owner: add a "Manage Capabilities" button on the partner page where a Kushol admin configures partner modules (institution, store, event, member quotas) — what is enabled is what the partner can use — plus the free/pro plan contract and a pro bill estimator.

- **Plan contract (free, the default):** max 5 team members (a common chat group named after the partner is provisioned); 1 event/month with 20 volunteers (a volunteers chat group is auto-created) and 150 participants (an event chat group named after the event is auto-created — partner member as admin, volunteers as contributors, participants as members); 170 registrations per event with event tasks assignable to volunteers; unlimited institution onboarding through LMS or manual; the store is pro-only. After an event closes, participants and volunteers keep their login, can explore nearby events and use find-tutor/tuition. Privacy: users never see another user's phone number or email — discovery is by name search only.
- **Pro plan:** the store unlocks (product listings become a billed quota) and the monthly bill is estimated from the quota numbers — rate card: ৳500/event/month, ৳50/member above the first 5, ৳20/product listing, ৳10/volunteer/event, ৳2/participant/event. The partner inputs the numbers; the estimated amount renders live.
- **Storage + api:** migration `20270313090010` adds plan, store/events/institutions/event-task toggles and the quota columns to partner_accounts (member quota rides `free_seat_quota`). `GET/PUT /api/v1/admin/partners/{partnerId}/capabilities` (Kushol admin) reads/writes the snapshot — the server forces free-plan values regardless of the payload; pro bills are computed from the rate card (`directory/capabilities.go`). Add-member now hard-caps the free plan at the member quota (CONFLICT beyond 5).
- **Web:** "Manage Capabilities" button + plan badge (Free/Pro) in the partner header; the dialog edits plan, toggles and quotas with a live pro bill preview and locks the free-plan values (server re-forces them).
- **Evidence:** api build/goimports/vet/golangci-lint (0 issues) + `go test -race` green; web typecheck/eslint/vitest 324/324; contracts no-drift.
- **Pending owner:** migration `20270313090010` (G-29). Event-runtime auto group/task creation and store/commerce gating are plan-contract behaviors for their owning modules (05 chat groups exist; 14 events/commerce wiring is the follow-up) — the quotas and flags this feature stores are the inputs those modules enforce.
