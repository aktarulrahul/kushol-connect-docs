# Module Index — Kushol Connect (the only task queue)

Every module lives in its own folder, named `NN-<kebab-case-name>` and numbered in dependency
order. Each folder contains **five specification files**; two working files are added when its
build starts.

| File | Purpose |
| --- | --- |
| `01-user-stories.md` | Purpose · actors · scope · stories (Given/When/Then) · business & validation rules · edge cases · open questions |
| `02-solution-approach.md` | Domain model · boundary · lifecycle · rendering & caching · configuration two-list · security · failure · performance · alternatives · risks |
| `03-backend-tasks.md` | **Schema first** (tenant-scoped) · REST/WS contracts · service & repository tasks · jobs · tests · checklist |
| `04-frontend-tasks.md` | Screens · states · forms · data flow · **motion table** · responsive (360px first) · bn/en strings · a11y · checklist |
| `05-integration-tasks.md` | Integration surface · exported/consumed contracts · **cache keys** · externals (FCM, DeepSeek, gateways) · UI↔server seam · degradation · tests · checklist |
| `06-progress.md` *(at build)* | What was built, decisions taken while building, verification evidence |
| `07-gaps.md` *(at build)* | Genuine remaining gaps only — reason, impact, next action |

To add a module: copy `_TEMPLATE/` to `NN-<name>/`, fill every section ("None" / "N/A — reason"
rather than blank), and add a row below **in the same commit**.

Apps: `api` = `applications/api` (Go), `ai` = `applications/ai` (Python FastAPI, later),
`web` = `applications/web`, `app` = `applications/app`, `shared` = `packages/shared`,
`contracts` = `contracts/openapi` (OpenAPI 3.1 — generates Go server types + TS clients).

---

## This is the only task queue

There is no separate backlog. Module order is this table; task order within a module is the
checklist in `03` → `04` → `05`. A second task list always drifts from the first.

## Status legend

Spec: `📝 Spec drafted` · `✅ Spec complete` (open questions answered or defaults accepted).
Build: `⬜ Not started` · `🚧 In development` · `🟢 Delivered` (Definition of Done,
`docs/prompt/prompt-build.md` §5).

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

Suffixes: `US` story · `BR` business rule · `BE` backend task · `FE` frontend task · `INT`
integration task · `UT` unit test · `IT` integration test · `E2E` Playwright/Maestro test.

---

## Modules

| # | Module | Phase | Size | Spec | Build | Depends on | Covers (apps) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | [`foundations`](./01-foundations/) | 1 | M | ⬜ | ⬜ | — | Monorepo scaffold (pnpm+Turborepo for web/app/shared, Go module for api), OpenAPI codegen pipeline (oapi-codegen + openapi-typescript), env/config parsing, Postgres via testcontainers-go, sqlc + golang-migrate base, logging (slog), error format, headers, health, CI quality gate, test harness · `api` `shared` `contracts` |
| 02 | [`design-system`](./02-design-system/) | 1 | M | ⬜ | ⬜ | 01 | Brand tokens (deep-teal palette), Hind Siliguri + Inter, RN primitives (NativeWind) + web primitives (shadcn-style), bn/en string catalogs, app icon/splash from logo · `shared` `app` `web` |
| 03 | [`identity-access`](./03-identity-access/) | 1 | M | ⬜ | ⬜ | 01, 02 | Five roles (Super Admin/School Admin/Teacher/Student/Guardian), custom Go auth: phone OTP (local SMS gateway) + Google/GitHub SSO, registration, login (JWT mobile / session web), verification workflow (Admin or Student Ambassador), role guards · `api` `app` `web` |
| 04 | [`organization-hierarchy`](./04-organization-hierarchy/) | 1 | M | ⬜ | ⬜ | 03 | City → School → Section model, school onboarding/tenancy, auto-grouping on verification, FCM topic subscription mapping, year-end migration design · `api` `shared` |
| 05 | [`communication-engine`](./05-communication-engine/) | 1 | **L** | ⬜ | ⬜ | 04 | Group chat (official/custom/DM) over the Go WebSocket gateway (gorilla rooms + Redis pub/sub), notice boards (one-way), Message Request for out-of-network DMs, media (image/PDF/voice) with Cloudflare R2 uploads, optimistic UI · `api` `app` |
| 06 | [`notifications`](./06-notifications/) | 1 | M | ⬜ | ⬜ | 04, 05 | FCM topic fan-out, per-device push via expo-notifications, deep links into app screens, delivery tracking · `api` `app` |
| 07 | [`command-center-web`](./07-command-center-web/) | 1 | **L** | ⬜ | ⬜ | 03, 04 | Landing page (B2B funnel: school ROI calculator, vendor inquiry, download links) + Super Admin portal (tenants, vendor approval, revenue) + School Admin portal (roster, notices, migration trigger) shell · `web` `api` |
| 08 | [`ai-study-hub`](./08-ai-study-hub/) | 2 | **L** | ⬜ | ⬜ | 05 | `AIService` interface in Go (DeepSeek direct at first; FastAPI service in `applications/ai` later — clients never change), quota'd, Notes Scanner (vision tagging into searchable archive), Smart Study Hub, Auto-CT MCQ generation + in-app testing with auto-grading · `api` `ai` `app` |
| 09 | [`teacher-analytics`](./09-teacher-analytics/) | 2 | M | ⬜ | ⬜ | 08 | Pain Point Matrix: weekly per-section weakness aggregation from failed MCQs + chat queries, teacher/school-admin dashboard · `api` `web` `app` |
| 10 | [`tuition-marketplace`](./10-tuition-marketplace/) | 2 | **L** | ⬜ | ⬜ | 05 | Requirement posts (subject/budget/location), geo+skill matching to verified seniors, tutor profiles & verification, match notifications + in-app negotiation chat · `api` `app` `web` |
| 11 | [`campus-commerce`](./11-campus-commerce/) | 3 | **L** | ⬜ | ⬜ | 07 | Vendor storefronts scoped to schools, product catalog (books/uniforms/stationery), orders with pickup or third-party courier, inventory management · `api` `web` `app` |
| 12 | [`payments`](./12-payments/) | 3 | M | ⬜ | ⬜ | 07, 11 | bKash/Nagad/SSLCommerz integration, fee-payment deep links, webhook signature verification, idempotent ledger, PDF receipts · `api` `web` `app` |
| 13 | [`b2b-ads-events`](./13-b2b-ads-events/) | 3 | M | ⬜ | ⬜ | 06, 07 | Demographic-targeted campaigns (grade/section/city), sponsored push/native ads with moderation, event listings & ticketing commission · `api` `web` |
| 14 | [`lms-erp-sync`](./14-lms-erp-sync/) | 3 | M | ⬜ | ⬜ | 04, 07 | CSV/Excel roster upload (self-serve), REST webhooks for live LMS/ERP sync, idempotent ingestion, reconciliation reports · `api` `web` |
| 15 | [`deployment-operations`](./15-deployment-operations/) | all | M | ⬜ | ⬜ | 01 (A) · all (B) | Docker (api + web), Compose (Postgres/Redis/MinIO), Nginx + TLS, EAS pipelines, backups + restore drill, runbooks, `DEPLOYMENT.md` · `infra` |

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
```

---

## Build phases (brd.md §8)

| Phase | Modules | Exit criteria |
| --- | --- | --- |
| **1 · MVP Community (month 1–3)** | 01 → 02 → 03 → 04 → 05 → 06 → 07 (+15-A) | A verified student auto-joins their section group, receives a notice by push, and the School Admin can upload a roster and broadcast; **pilot-ready for 2–3 schools** on TestFlight + APK |
| **2 · AI & Marketplace (month 4–6)** | 08 → 09 → 10 | Auto-CT generates and grades a class test; teachers see a Pain Point Matrix; a guardian posts a tuition requirement and a verified senior is matched |
| **3 · Ecosystem Scale (month 7–12)** | 11 → 12 → 13 → 14 (+15-B) | Vendor sells through the platform with payment + receipt; a targeting campaign reaches exactly the chosen demographic; a school syncs rosters via webhook |
| **Post-launch** | — | Monitoring, cost reporting (DeepSeek per active user), pilot feedback loop |

Within a module: backend (`03`) → frontend (`04`) → integration (`05`). A module's exported
contract (`05` §2) is written before another module calls it.

---

## Blocked before build — questions and the defaults each module will use

| Module | Question | Default if unanswered |
| --- | --- | --- |
| 01 | *(resolved)* Backend framework | **Go** for `api` including messaging (chi + gorilla/websocket + sqlc); AI later extracted to Python FastAPI behind the `AIService` interface — update `prd.md` §6 to match |
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
| 15 | *(resolved)* VPS provider / region · DB hosting | **Hostinger KVM 2 (2 vCPU / 8 GB) + HestiaCP, shared with 2 other applications** — size the stack to fit (memory caps, images built in CI, never on-host). **Postgres on Neon free tier (ap-southeast-1)** for quick start; upgrade Neon or move back on-VPS at real pilot traffic |

## Out of scope (brd.md §4 — do not create modules until approved)

Live video classes (Zoom/Meet remain the tool) · in-house courier/delivery fleet management ·
anything targeting users outside the registered hierarchy · public open-registration social
features (all participation requires school-scoped verification).
