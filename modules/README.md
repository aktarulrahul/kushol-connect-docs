# Module Index — Kushol Connect (the only task queue)

Every module lives in its own folder, named `NN-<kebab-case-name>` and numbered in dependency
order. Each folder contains **six specification files** (copied from `_TEMPLATE/`) plus a
consolidated **technical document**; two working files are added when its build starts.

| File | Purpose |
| --- | --- |
| `01-user-stories.md` | Purpose · actors · scope · stories (Given/When/Then) · business & validation rules · edge cases · open questions |
| `02-solution-approach.md` | Domain model · boundary · lifecycle · rendering & caching · configuration two-list · security · failure · performance · alternatives · risks |
| `03-backend-tasks.md` | **Schema first** (tenant-scoped) · REST/WS contracts · service & repository tasks · jobs · tests · checklist |
| `04-frontend-tasks.md` | **Web** screens · states · forms · data flow · **motion table** · responsive · bn/en strings · a11y · checklist |
| `05-app-tasks.md` | **Mobile app** screens (expo-router) · states incl. offline · media upload flow · motion · 360px-first · bn/en · a11y · checklist |
| `06-integration-tasks.md` | Integration surface · exported/consumed contracts · **cache keys** · externals (FCM, R2, DeepSeek, gateways, SMS) · UI↔server seam · degradation · tests · checklist |
| `technical-document.md` | Single engineer-facing reference compressing `01`–`06`: stack · architecture · data · contracts · surfaces · config · security · errors · ops · tests · traceability (must agree with the spec files — specs win on drift) |
| `07-progress.md` *(at build)* | What was built, decisions taken while building, verification evidence |
| `08-gaps.md` *(at build)* | Genuine remaining gaps only — reason, impact, next action |

To add a module: copy `_TEMPLATE/` to `NN-<name>/`, fill every section ("None" / "N/A — reason"
rather than blank), and add a row below **in the same commit**.

Apps: `api` = `applications/api` (Go), `ai` = `applications/ai` (Python FastAPI, later),
`web` = `applications/web`, `app` = `applications/app`. **Each app is its own git repository; there
is no shared package and no root workspace** (owner decision 2026-09-30). `web` and `app` each own
`src/api` (client generated from the api's spec), `src/i18n`, `src/theme` and `src/schemas`.
`contracts` = `applications/api/openapi/openapi.yaml` (OpenAPI 3.1, owned by api — generates the Go
server types; web/app sync a copy and generate their own TS client).

---

## This is the only task queue

There is no separate backlog. Module order is this table; task order within a module is the
checklist in `03` → `04` → `05`. A second task list always drifts from the first.

## Status legend

Spec: `📝 Spec drafted` · `✅ Spec complete` (open questions answered or defaults accepted).
Build: `⬜ Not started` · `🚧 In development` · `🟢 Delivered` (Definition of Done,
`docs/prompt/prompt-build.md` §5).

A 🚧 module passes three **manual gates** before it can turn 🟢: Gate 1 — owner approves the
mock-driven UI (`04`+`05`) · Gate 2 — owner runs the `03` SQL migration script against the
shared database and confirms · Gate 3 — owner approves the integrated web/app↔api flows.
Gate outcomes are recorded in the module's `07-progress.md`; gaps from the final check go to
`08-gaps.md`.

A module is **ready to build** when its spec is ✅ and every dependency is 🟢.

## ID prefixes

| Module | Prefix | Example |
| --- | --- | --- |
| 01 foundations | `FND` | `FND-BE-004` |
| 02 design-system | `DSN` | `DSN-FE-010` |
| 03 identity-access | `IDT` | `IDT-US-007` |
| 04 organization-hierarchy | `ORG` | `ORG-BE-003` |
| 05 communication-engine | `COM` | `COM-FE-021` |
| 06 notifications | `NTF` | `NTF-BE-002` |
| 07 command-center-web | `WEB` | `WEB-FE-005` |
| 08 ai-study-hub | `AIH` | `AIH-US-001` |
| 09 teacher-analytics | `ANL` | `ANL-BE-004` |
| 10 tuition-marketplace | `TUT` | `TUT-FE-012` |
| 11 campus-commerce | `CMP` | `CMP-BE-006` |
| 12 payments | `PAY` | `PAY-IT-003` |
| 13 b2b-ads-events | `ADS` | `ADS-FE-002` |
| 14 lms-erp-sync | `LMS` | `LMS-BE-001` |
| 15 deployment-operations | `OPS` | `OPS-E2E-001` |
| 16 guardian-experience | `GRD` | `GRD-AP-004` |

Suffixes: `US` story · `BR` business rule · `BE` backend task · `FE` web-frontend task · `AP`
mobile-app task · `INT` integration task · `UT` unit test · `IT` integration test · `E2E`
Playwright (web) / Maestro (app) test.

---

## Modules

| # | Module | Phase | Size | Spec | Build | Depends on | Covers (apps) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | [`foundations`](./01-foundations/) | 1 | M | 📝 | 🚧 | — | Go `api` scaffold (own repo), OpenAPI 3.1 contract owned by api + Go codegen (oapi-codegen), env/config parsing, Postgres via testcontainers-go, sqlc + golang-migrate base, logging (slog), error format, headers, health, CI quality gate, test harness; **web and app repo scaffolds** (Next.js / Expo, generated openapi-fetch client, zod env, lint boundaries, CI) · `api` `web` `app` `contracts` |
| 02 | [`design-system`](./02-design-system/) | 1 | M | 📝 | 🚧 | 01 | Brand tokens (deep-teal palette), Hind Siliguri + Inter, RN primitives (NativeWind) + web primitives (shadcn-style), bn/en string catalogs, app icon/splash from logo — tokens/catalogs encoded separately in each app (repos scaffolded by 01) · `app` `web` |
| 03 | [`identity-access`](./03-identity-access/) | 1 | M | 📝 | 🚧 | 01, 02 | Five roles (Super Admin/School Admin/Teacher/Student/Guardian), custom Go auth: phone OTP (local SMS gateway) + Google/GitHub SSO, registration, login (JWT mobile / session web), verification workflow (Admin or Student Ambassador), role guards · `api` `app` `web` |
| 04 | [`organization-hierarchy`](./04-organization-hierarchy/) | 1 | M | 📝 | 🚧 | 03 | City → School → Section model, school onboarding/tenancy (request-approval path, owner 2026-10-02), auto-grouping on verification, FCM topic subscription mapping, year-end migration design · `api` |
| 05 | [`communication-engine`](./05-communication-engine/) | 1 | **L** | 📝 | 🚧 | 04 | Group chat (official/custom/DM) over the Go WebSocket gateway (gorilla rooms + Redis pub/sub), notice boards (one-way), Message Request for out-of-network DMs, media (image/PDF/voice) with Cloudflare R2 uploads, optimistic UI · `api` `app` — build notes: endpoints #21 download-url + #22 club-approve added (ADR in module docs); env `R2_ACCOUNT_ID/R2_ACCESS_KEY_ID/R2_SECRET_KEY/R2_BUCKET` (server-only); `KLIPY_APP_KEY` (client key handed to signed-in users for GIFs/stickers, 2026-10-18; migration `20270308090000`); @mentions + private starred messages (owner 2026-10-18; endpoints #23–#25, migration `20270309090000`, mention pushes via 06 `SendToUser` type `chat_mention`); jobs `chat.request_expiry`, `media.archival`, `media.pending_cleanup` |
| 06 | [`notifications`](./06-notifications/) | 1 | M | 📝 | 🚧 | 04, 05 | FCM topic fan-out, per-device push via expo-notifications, deep links into app screens, delivery tracking · `api` `app` — build notes: env `FCM_SERVICE_ACCOUNT_JSON`/`FCM_PROJECT_ID` (server-only; degraded without); jobs `fanout.send`, `tokens.prune`, `topics.backfill`; binds 05's `chat.Broadcaster` (05 G-2 closed); Stage 5 app integration done 2026-10-03 (live `openapi-fetch` client behind the session-token selector; native FCM token via `getDevicePushTokenAsync` — needs the owner's Firebase config, 06 G-6) |
| 07 | [`command-center-web`](./07-command-center-web/) | 1 | **L** | 📝 | 🚧 | 03, 04 | Landing page (B2B funnel: school ROI calculator, vendor inquiry, download links) + Super Admin portal (tenants, vendor approval, revenue) + School Admin portal (roster, notices, migration trigger) shell · `web` `api` — build notes: 2026-10-04 console additions on fixture seams: three admin personas (Kushol / Institution / Vendor) with role-aware nav + per-persona dashboards, WhatsApp-style admin chat, audit+access logs (DataTable), lead decisions (review/accept/reject-with-reason), vendor onboarding + store oversight + item approvals, institution details + per-institution LMS connector (kushol-admin-only), BD division→city onboarding, user popover + typography scale; institution portal at /institution/*; contracts listed in 07-progress |
| 08 | [`ai-study-hub`](./08-ai-study-hub/) | 2 | **L** | 📝 | ⬜ | 05 | `AIService` interface in Go (DeepSeek direct at first; FastAPI service in `applications/ai` later — clients never change), quota'd, Notes Scanner (vision tagging into searchable archive), Smart Study Hub, Auto-CT MCQ generation + in-app testing with auto-grading · `api` `ai` `app` |
| 09 | [`teacher-analytics`](./09-teacher-analytics/) | 2 | M | 📝 | ⬜ | 08 | Pain Point Matrix: weekly per-section weakness aggregation from failed MCQs + chat queries, teacher/school-admin dashboard · `api` `web` `app` |
| 10 | [`tuition-marketplace`](./10-tuition-marketplace/) | 2 | **L** | 📝 | 🚧 | 05 | Requirement posts (subject/budget/location), geo+skill matching to verified seniors, tutor profiles & verification, match notifications + in-app negotiation chat · `api` `app` `web` — build notes: OpenAPI paths #1–#15 + `Tuition*` schemas landed 2026-10-03 (contract-first; both clients synced); jobs `tuition.match`, `tuition.expiry`, `tuition.verification-reminder`; cache tags `tuition:tutors:{area}` / `tuition:tutor:{id}` / `tuition:tutorcount:{schoolId}`; migrations `20261120090000–093000` pending owner (Gate 2); app live client behind the session-token selector, web fixture seam until 07's console glue (10 G-8); **2026-10-04 scope correction: tuitions are INDEPENDENT of institutions** — public `/tuition` marketplace (post requirement · tutor registration with auto-match + notify · interview calls physical-meet/online · tutor ratings 1–5), institution oversight stays at `/school/tuitions` |
| 11 | [`campus-commerce`](./11-campus-commerce/) | 3 | **L** | 📝 | 🚧 | 07 | Vendor storefronts scoped to schools, product catalog (books/uniforms/stationery), orders with pickup or third-party courier, inventory management · `api` `web` `app` — build notes: 20 REST endpoints + `OUT_OF_STOCK` code; jobs `commerce.auto-cancel`/`commerce.low-stock-digest`; cache tags `commerce:stores:school:{id}` / `commerce:store:{id}` / `commerce:product:{id}`; payment seam `commerce.OrderAmount`/`AttachPaymentTransaction` dormant until 12; migrations `20270201090000–093000` pending owner (Gate 2); app live client behind the session-token selector, web fixture seam until 07's console glue (11 G-3) |
| 12 | [`payments`](./12-payments/) | 3 | M | 📝 | 🚧 | 07, 11 | bKash/Nagad/SSLCommerz integration, fee-payment deep links, webhook signature verification, idempotent ledger, PDF receipts · `api` `web` `app` — build notes: webhook route is the signature-verified auth exception (`security: []`); `SandboxGateway` adapter until merchant docs confirm real schemes (G-2); jobs `receipt.generate`/`payments.expire`/`payments.overdue_sweep`; ledger append-only trigger; env `PAYMENTS_WEBHOOK_SECRET` (server-only); migrations `20270210090000–093000` pending owner (Gate 2) |
| 13 | [`b2b-ads-events`](./13-b2b-ads-events/) | 3 | M | 📝 | 🚧 | 06, 07 | Demographic-targeted campaigns (grade/section/city), sponsored push/native ads with moderation, event listings & ticketing commission · `api` `web` — build notes: moderation-before-serving (campaigns + events, reject-reason audited); dispatch job expands targeting→06 topics with server-injected sponsored label, 7-day cap + budget auto-pause; aggregate-only analytics (daily-rotating pseudized refs); 10% ticket commission + 12 seam; migrations `20270220100000–101000` pending owner (Gate 2); web fixture seam until 07's console glue (13 G-3) |
| 14 | [`lms-erp-sync`](./14-lms-erp-sync/) | 3 | M | 📝 | 🚧 | 04, 07 | CSV/Excel roster upload; **LMS pull connector** for **educational institutions** (Institution Admin configures LMS base URL + Bearer/API key, schedule + Sync now → teachers/students/classes/sections + section chat groups; vendor `institution_type`); inbound HMAC webhooks; reconciliation · terminology [`terminology-institution.md`](./14-lms-erp-sync/terminology-institution.md) · vendor brief [`vendor-lms-api-spec.md`](./14-lms-erp-sync/vendor-lms-api-spec.md) · GET samples [`vendor-lms-api-response-examples.md`](./14-lms-erp-sync/vendor-lms-api-response-examples.md) · OpenAPI [`lms-vendor-api.yaml`](../contracts/lms-vendor-api.yaml) · plan [`lms-pull-integration-plan.md`](./14-lms-erp-sync/lms-pull-integration-plan.md) · `api` `web` — build notes: 22 operations + 28 `Lms*` schemas; HMAC webhook exception (module 12 pattern) with AES-256-GCM versioned secrets (`ERP_SECRET_KEY`, required env); dry-run-first imports with content-hash no-op + chunked commits via 03 `UpsertRosterUser` (PENDING creates) + 04 `CreateEnrollments`; LMS pull connector (encrypted connection, interval schedule presets, one running sync per institution, external-id map, additive 04 export `EnsureExternalSection`); licence flag `schools.sync_licence_enabled` (enable via SQL for pilots, 14 G-4); migrations `20270301090001–090003` pending owner (Gate 2); web fixture seam until 07's console glue (14 G-3) |
| 15 | [`deployment-operations`](./15-deployment-operations/) | all | M | 📝 | 🚧 Part A | 01 (A) · all (B) | Docker (api + web), Compose (api/worker/web/Redis — Postgres on Neon, media on R2), Nginx + TLS, EAS pipelines, backups + restore drill, runbooks, `DEPLOYMENT.md` · `infra` |
| 16 | [`guardian-experience`](./16-guardian-experience/) | 3 (G0 first) | **L** | 📝 | ⬜ planned | 03, 04, 05, 06, 07, 10, 12, 14 | Guardian (অভিভাবক) experience end to end. Covers: guardian accounts linked to 1..n children (many-to-many `guardian_links` v2 with relation, primary and revocation); every link verified by the institution (link requests with student-code matching; school-vouched invites in G2); a versioned guardian privacy consent; app guardian home, child switcher and child hub (notices, fees, chat; attendance/results slot hidden until a future module); institution console `/institution/guardians` (links, requests, invites) · `api` `web` `app` — **planning notes (2026-10-19, owner "also plan for student's guardian"): planned, not built.** G0 hardening comes first and lives inside 03/04/05/07/12 (`GRD-INT-001…006`): the `GET /school/invoices` role gate plus a payer list, guardian fee-due fan-out, web approval with a student picker, guardian enrollments that follow the child, the guardian DM policy, and no ambassador guardian decisions. `grd_*` migration versions are provisional and get stamped at build |

## Dependency graph

```text
01 foundations
  └─► 02 design-system
       └─► 03 identity-access
            └─► 04 organization-hierarchy
                 ├─► 05 communication-engine ──► 06 notifications
                 │         └─► 08 ai-study-hub ──► 09 teacher-analytics
                 │         └─► 10 tuition-marketplace
                 └─► 07 command-center-web ──► 11 campus-commerce ──► 12 payments
                                          ├─► 13 b2b-ads-events (needs 06)
                                          └─► 14 lms-erp-sync
01 ─► 15 deployment-operations (A: walking skeleton after 02 … B: production after 14)
03 · 04 · 05 · 06 · 07 · 10 · 12 · 14 ─► 16 guardian-experience (planned; G0 hardening lands inside 03/04/05/07/12 first)
```

---

## Build phases (brd.md §8)

| Phase | Modules | Exit criteria |
| --- | --- | --- |
| **1 · MVP Community (month 1–3)** | 01 → 02 → 03 → 04 → 05 → 06 → 07 (+15-A) | A verified student auto-joins their section group, receives a notice by push, and the School Admin can upload a roster and broadcast; **pilot-ready for 2–3 schools** on TestFlight + APK |
| **2 · AI & Marketplace (month 4–6)** | 08 → 09 → 10 | Auto-CT generates and grades a class test; teachers see a Pain Point Matrix; a guardian posts a tuition requirement and a verified senior is matched |
| **3 · Ecosystem Scale (month 7–12)** | 11 → 12 → 13 → 14 (+15-B) | Vendor sells through the platform with payment + receipt; a targeting campaign reaches exactly the chosen demographic; a school syncs rosters via webhook |
| **Post-launch** | — | Monitoring, cost reporting (DeepSeek per active user), pilot feedback loop |

Within a module: **UI first** (`04` web + `05` app, mock-driven) → **manual UI approval** →
docs sync → **backend** (`03`, schema first; the SQL migration script is delivered for the owner
to **run manually**) → **integration** (`06`; mocks swapped for the generated client) →
**manual approval of integrated flows** → gap check + final verification. A module's exported
contract (`06` §2) is still written before another module calls it. Full stage/gate detail:
`docs/prompt/prompt-build.md` §3–§4.

---

## Cross-module registries (binding — added 2026-09-30 consistency pass)

These registries exist because the drafted specs collided. Before a module invents a name, it
checks here; in its Stage 3 docs sync it updates the relevant row.

### Migration versions

golang-migrate records only the highest applied version, so **a file whose version is lower than
the database's current version is silently skipped**. Versions therefore increase in **build
order**, not in module number. If a module is built out of the order below, re-stamp its files
with the build date before the owner runs them (and note it in `07-progress.md`).

| Build order | Module | Version block | Notes |
| --- | --- | --- | --- |
| 1 | 01 | `20260930000001–000003` | extensions, `audit_log`, `jobs` |
| 2 | 03 | `20261001090000–090030` | no FKs to 04 tables (04 not built yet). 2026-10-17: data migration `20270307090000_set_kushol_admin_phone` (Aktarul Islam's phone), stamped after the highest applied version. 2026-10-19: `20270311090000_plt_access` (platform roles/permissions/grants — owner instruction, Kushol admins only; system roles super_admin + viewer seeded; modules/actions stay a static registry in `internal/platformaccess`) |
| 3 | 04 | `20261002090001–090007` | `…090007` adds FKs from 03 tables to `schools`/`sections` |
| 4 | 05 | `20261003090000–094000` | 2026-10-17: later 05 changes are stamped after the highest applied version — `20270305090000` (re-stamp of the skipped `20261016090000` rich-messages file) `20270305091000` (system groups, Office/CSV media kinds, file names) and `20270306090000` (delivered/read receipts, one reaction per person, forward hops); 2026-10-18: `20270308090000` (KLIPY GIFs/stickers, group photo) and `20270309090000` (@mentions + starred messages, owner instruction) |
| 5 | 06 | `20261006090001–090002` | 2+3 combined: `…090002_create_notification_deliveries_preferences` |
| 6 | 07 | `20261015090000–091000` | |
| 7 | 08 | `20261101090000–093000` | |
| 8 | 09 | `20261110090001` | |
| 9 | 10 | `20261120090000–093000` | |
| 10 | 11 | `20270201090000–093000` | |
| 11 | 12 | `20270210090000–093000` | after 11 (order payments reference orders) |
| 12 | 13 | `20270220100000–101000` | |
| 13 | 14 | `20270301090001–090003` | spec's 4 migrations consolidated to 3 (imports+rows, endpoints+events) + pull tables; also adds `schools.sync_licence_enabled` and media kind `roster` |

(02 and 15 own no tables.)

### Names that must stay unique

| Registry | Source of truth |
| --- | --- |
| Error codes (RFC-7807 `code`) | `01-foundations/technical-document.md` §10 (core + module-specific table) |
| i18n catalog namespaces | `02-design-system/02-solution-approach.md` §1.1 |
| Go export packages | `audit` `jobs` `principal` `i18n` (01; `i18n` = api-side bn/en copy for problem/push/email text) · `auth` `sessions` `verification` `users` `guardians` (03; extended by 16, planned) · `hierarchy` (04) · `chat` `media` (05) · `notify` (06) · `vendors` (07) · `ai` `aiquota` (08; `ai.AttemptStats` lives in `ai` because `analytics` is 09's package) · `analytics` (09) · each module's `06` §2 is the signature source |
| Web routes | 07 owns the `/admin`, `/school`, `/vendor` route tree and stub names; feature modules fill stubs under the same name (`/school/ai-matrix` 09 · `/school/tutors` 10 · `/school/ledger`, `/school/payments/*` 12 · `/school/roster/*`, `/school/integrations` 14). 05 owns **`/chat`** (console messenger, owner 2026-10-17; `/admin/chat` redirects) |
| API paths | One owner per path; shared-sounding reports are namespaced by owner (`/school/payments/reconciliation` 12 vs `/school/roster/reconciliation` 14) |
| Env variables | Each module's `technical-document.md` §8.1; full inventory in `prompt.txt` §11 and 15's `.env.example` |

Infrastructure, domain and email plan: `docs/infra/architecture-and-deployment.md` (findings F1–F17, owner actions; §9 spec edits applied 2026-09-30).

### Resolved cross-module decisions (2026-09-30)

| Decision | Where recorded |
| --- | --- |
| `vendor` is a 03 user role (platform-scoped), created only by 07 vendor approval | 03 `03` §1.1, 07 `03` |
| Durable guardian ↔ student link = 03 `guardian_links` (written in the guardian approve tx) | 03 `03` §1.1 |
| Kushol Pro = `users.plan` + `plan_expires_at` (03), read by 08 via `users.PlanOf` | 03, 08 |
| Registration section choice = `verification_requests.requested_section_id`; no `classes` table (class level lives on `sections`) | 03, 04 |
| `sections.stream` (science / business_studies / humanities) for BR-05 targeting | 04, 13 |
| Push = FCM only (topics + directed), one native FCM token per device; Expo push API not used | 06 `02` §10, `tech-stack.md` |
| ERP webhook secrets encrypted (AES-256-GCM, `ERP_SECRET_KEY`), not hashed | 14 |
| Org product noun = **educational institution** (UI **Institution** / **প্রতিষ্ঠান**); `institution_type` ∈ `primary_school` \| `high_school` \| `college` (bn: প্রাইমারি স্কুল, হাই স্কুল, কলেজ). FCM `school-{id}` → `institution-{id}` is a deferred 06 gap | 14 terminology + LMS vendor API (2026-10-03); full path/DB/role rename deferred |
| Convenience fee default BDT 0 (`brd.md` §7 supersedes `prd.md` §7) | 12, `prd.md` |
| Payment success needs server-to-server status confirmation; gateway webhook schemes `TODO: Confirm` | 12 `02` §6 |
| Teachers may use `/school/ai-matrix` (own sections) on web; no other web portal | 07, 09 |
| UI: mobile = CircleUp layout + WhatsApp chat in Kushol teal; web = professional SaaS | `docs/design-reference/README.md` §6–§7 |
| **Isolated applications** (owner, 2026-09-30): each app is its own git repo; no `packages/shared`, no root pnpm/Turborepo workspace. The api owns `applications/api/openapi/openapi.yaml` and server-rendered bn/en copy (`internal/i18n`); `web`/`app` each own `src/api` (generated client from a synced spec copy), `src/i18n`, `src/theme`, `src/schemas`. Cross-repo drift is caught by each client's spec-sync check. Web/app repo scaffolds are built by 01 (`FND-FE-001`/`FND-AP-001`, owner 2026-09-30) | `prompt.txt` §1, `tech-stack.md`, 01, 02 |

## Blocked before build — questions and the defaults each module will use

| Module | Question | Default if unanswered |
| --- | --- | --- |
| 01 | *(resolved 2026-09-29; layout revised 2026-09-30)* Repositories + toolchain | One git repo per app, no shared package; Go module for `api` (chi + gorilla/websocket + sqlc + pgx + golang-migrate); `web`/`app` each with their own pnpm toolchain; OpenAPI 3.1 spec in `applications/api/openapi/` generating Go server types (clients generate their own TS client); Postgres on Neon free (ap-southeast-1); media on Cloudflare R2; VPS = Hostinger KVM 2 + HestiaCP |
| 02 | Logo vector files | Typographic fallback ("কুশল CONNECT") + supplied PNG for mockups; recorded as a gap |
| 03 | Student Ambassador criteria / verification SLA | Any verified Student Ambassador of the same school may verify same-school join requests; SLA 48h, auto-reminder |
| 04 | City list at launch | Dhaka + Chattogram only; new cities added by Super Admin |
| 05 | Chat retention / media TTL | Messages retained indefinitely per tenant; media 90 days on hot storage then archived |
| 06 | Android notification channel strategy | One channel per notice class (notices / chat / campaigns) |
| 07 | School Admin roster CSV format | Template generated by the portal; strict header validation with row-level error report |
| 08 | DeepSeek model tier + weekly free quota | Flash-class cheapest vision+chat models; 5 Auto-CTs/week free (brd.md §7), Kushol Pro unlimited |
| 09 | Matrix granularity | Weekly, per section, per topic tag; teacher sees own sections, School Admin sees whole school |
| 10 | Tutor verification standard | University/senior student + national ID + subject evidence; verified by School Admin or platform ops |
| 11 | Courier integration | Manual third-party courier (no API) at launch; tracking number stored on the order |
| 12 | Primary gateway | SSLCommerz first (cards+banks), bKash/Nagad wallets next; sandbox keys until module 15 |
| 13 | Ad moderation rule | All campaigns Super-Admin-approved; no individual-level targeting of minors, only section/grade/city demographics |
| 14 | Webhook auth | Per-school HMAC secret, rotating; replay window 5 minutes |
| 14 | LMS pull vs push default for partners | **Pull** (Kushol GETs vendor LMS API) for v1; inbound HMAC webhooks remain supported; see `14-lms-erp-sync/vendor-lms-api-spec.md` |
| 14 | Org noun / `institution_type` | **Educational institution** (UI Institution / প্রতিষ্ঠান); enum `primary_school` \| `high_school` \| `college` with bn labels in `terminology-institution.md`. FCM `school-{id}` rename deferred (06) |
| 15 | *(resolved)* VPS provider / region · DB hosting | **Hostinger KVM 2 (2 vCPU / 8 GB) + HestiaCP, shared with 2 other applications** — size the stack to fit (memory caps, images built in CI, never on-host). **Postgres on Neon free tier (ap-southeast-1)** for quick start; upgrade Neon or move back on-VPS at real pilot traffic |
| 16 | Who decides guardian links? Do invites auto-verify? Where do guardians chat? (`16-guardian-experience/01-user-stories.md` §9, OQ-1…18) | school_admin or super_admin only (ambassadors excluded). Invites auto-link only after OTP proof of the phone. Guardians stay in the student group until G2, then move to a `section_guardians:{sectionId}` group. Attendance and results are out of scope. |

## Out of scope (brd.md §4 — do not create modules until approved)

Live video classes (Zoom/Meet remain the tool) · in-house courier/delivery fleet management ·
anything targeting users outside the registered hierarchy · public open-registration social
features (all participation requires school-scoped verification).
