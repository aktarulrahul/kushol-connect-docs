# Tech Stack — Kushol Connect (কুশল)

Layout — **four isolated applications, each its own git repository** with its own toolchain,
lockfile and CI. There is **no shared package and no root workspace** (owner decision 2026-09-30):

```text
applications/
├── api/    # Backend — Go: REST + WebSocket messaging, multi-tenant PostgreSQL, Redis, FCM, DeepSeek
│   └── openapi/openapi.yaml   # API contract (OpenAPI 3.1) — owned by api; single source of truth for API types
├── ai/     # (later, Phase 2+) — Python FastAPI AI service (DeepSeek orchestration) behind an internal HTTP interface
├── web/    # Next.js — landing page + Command Center; own src/api (generated client), src/i18n, src/theme, src/schemas
└── app/    # React Native (Expo) — Students, Teachers, Guardians; own src/api, src/i18n, src/theme, src/schemas
```

Nothing is imported across application folders. `web` and `app` keep a synced copy of
`applications/api/openapi/openapi.yaml` and generate their own typed client from it; bn/en copy and
design tokens are encoded per app from the canonical values in `docs/design-reference/README.md`;
the api owns server-rendered copy (problem messages, push, email) in `applications/api/internal/i18n`.

Exact versions are pinned in each app's own lockfile (`pnpm` with `save-exact` in `web` and `app`; `go.mod` + `tools.mod` for the API).
Rows marked `verify` belong to modules not yet built. Aligned with `prd.md` §6 and `brd.md` §6
(cost efficiency), with the backend decision resolved: **Go** for `api` (messaging included),
**Python FastAPI** for the AI service later.

## applications/app — Mobile (Students, Teachers, Guardians)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Framework | **Expo SDK** (managed workflow + config plugins / CNG) | latest stable `verify` | **EAS development builds, not Expo Go** — `@react-native-firebase` needs native code; OTA updates via EAS; Android APK direct + Play Store; iOS via TestFlight (`prd.md` §4B) |
| UI runtime | React Native + React | latest stable `verify` | Hermes engine |
| Navigation | **expo-router** (file-based) | latest `verify` | Typed routes; deep links for payment/notification payloads |
| Language | TypeScript (strict) | latest `verify` | |
| Styling | **NativeWind** (Tailwind for RN) + shared tokens | latest `verify` | Tokens from each app's `src/theme` mapped to the brand system (`design-reference/README.md`) |
| Components | shadcn-style hand-written RN primitives on **zeego**/radix-primitives where useful | `verify` | |
| Icons | lucide-react-native | latest | |
| Fonts | **Hind Siliguri** (Bengali UI + display) · **Inter** (Latin) via @expo-google-fonts | bundled | Bangla glyphs are a launch requirement, not an add-on |
| State (server) | **TanStack Query** | 5.x | Chat + marketplace lists |
| State (client) | zustand | latest `verify` | Session, settings, cached roster |
| Local persistence | **react-native-mmkv** (zustand persist: offline chat queue per 05 §8, settings, cached roster) · expo-sqlite only if message caching outgrows MMKV | latest `verify` | Offline queue must survive app restarts (05 §8); tokens in **expo-secure-store** |
| Media capture | **expo-image-manipulator** (resize/compress to ~1 MB before upload) · **expo-audio** (voice notes record/play) | latest `verify` | 05 media caps: image ≤ 10 MB, voice ≤ 5 min |
| Forms | react-hook-form + zod resolver | 7.x / **zod 4.x** | Schemas imported from each app's `src/schemas` |
| Chat | Plain **WebSocket** client to the Go gateway + optimistic UI | stdlib `verify` | Offline queue, media (image/voice) compression before upload |
| Push | **@react-native-firebase/messaging** (native FCM token, Expo config plugin, EAS builds) + **expo-notifications** (permission, channels, display, taps) | latest `verify` | One FCM token serves topic subscriptions (city/school/section — `brd.md` §6) and directed sends; Expo push tokens/APNs tokens cannot join FCM topics on iOS (decision 2026-09-30, module 06 `02` §10) |
| AI capture | expo-camera / expo-image-picker | latest `verify` | Notes Scanner input for DeepSeek vision |
| Testing | **Maestro** (E2E flows) + jest-expo (unit) | latest `verify` | Onboarding → verify → join section group is the golden path |
| Build/CI | **EAS Build & Submit** | cloud | APK/TestFlight distribution per `brd.md` §8 Phase 1 |

## applications/web — Landing + Command Center

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Framework | **Next.js** (App Router) | latest stable `verify` | `output: "standalone"` for Docker |
| Language | TypeScript (strict) | latest `verify` | |
| Styling | **Tailwind CSS** + CSS-first `@theme` tokens | v4 `verify` | Semantic tokens from each app's `src/theme`; light theme first, dark optional |
| Components | shadcn/ui on radix-ui | latest `verify` | Hand-written into `src/components/ui/` to keep token control |
| Icons | lucide-react | latest | |
| Fonts | Hind Siliguri · Inter (via `next/font/google`) | bundled | `latin` + `bengali` subsets |
| Data tables | **TanStack Table** + TanStack Query | latest `verify` | Rosters, ledgers, campaign builders (School Admin / Super Admin / Vendor portals) |
| Forms | react-hook-form + zod | 7.x / 4.x | Shared schemas from each app's `src/schemas` |
| Charts | Recharts | latest `verify` | Pain Point Matrix heatmap, revenue dashboards — only where useful |
| Markdown | Not needed at launch `verify` | — | Notices are plain text + attachments |
| Testing | Vitest + Testing Library · **Playwright** (+ axe) | latest `verify` | Web golden paths: landing funnel, admin login, CSV roster upload, campaign creation |
| SEO | Metadata API, OG images, JSON-LD (Organization), sitemap | bundled | Landing page is the B2B acquisition funnel (`prd.md` §4A) |

## applications/api — Backend (Go)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Language | **Go** | 1.26.1 (`go.mod`; 1.27.1 available — upgrade by ADR) | Decision resolved: Go for the whole API, including the messaging hot path (`prd.md` §6); Docker `golang` multi-stage → `distroless/static` (or alpine) runtime |
| HTTP framework | **chi** (net/http compatible) | v5.3.2 (pinned 01, 2026-09-30) | Small, explicit, idiomatic; REST endpoints |
| Contracts | **OpenAPI 3.1** spec in `applications/api/openapi/` → `oapi-codegen` (Go types/handlers) + `openapi-typescript`/`openapi-fetch` (TS clients, generated inside web and app) | oapi-codegen v2.8.0 (OpenAPI 3.1 supported) · kin-openapi v0.149.0 · nethttp-middleware v1.2.0 (pinned 01) · TS side pinned by 02/03 | Spec is written first; request validation via the spec (`httpx.Validator`) |
| Realtime / messaging | **gorilla/websocket** (+ Redis pub/sub fan-out across instances) | latest `verify` | **Messaging lives in Go**: rooms mirror City → School → Section and custom groups; presence in Redis |
| Database | **PostgreSQL** (multi-tenant, shared-schema + tenant scoping) — hosted on **Neon** free tier (Singapore `ap-southeast-1`) for quick start | 16+ `verify` | Decision recorded 2026-09-29: Neon over Supabase (pure Postgres, DB branches fit the migration workflow; Supabase free pauses after 1 week idle). Free tier scales to zero (cold start ~hundreds of ms) — fine for dev/pilot, upgrade (Launch ~$19/mo) or move back to a Compose container when real school traffic starts. Tenant columns enforced in the repository layer; `pg_trgm` for search |
| Data access | **sqlc** (type-safe generated queries) + **pgx/v5** driver | sqlc v1.31.1 (`tools.mod`) · pgx v5.11.0 · golang-migrate v4.20.1 (pinned 01) | Migrations as plain SQL files — **golang-migrate** (pinned 2026-09-30), expand/contract; applied manually by the owner (Gate 2), never at deploy/boot |
| Cache / presence | **Redis** (go-redis) | server 7 `verify` · go-redis v9.22.0 (pinned 01) | Chat cache, online presence, rate limits, idempotency keys (`prd.md` §6) |
| Push | **Firebase Admin Go SDK** → **FCM topic subscriptions** | latest `verify` | Topic-per-node fan-out for mass notices (`brd.md` §6) |
| AI | **DeepSeek API** behind an internal `AIService` Go interface | latest `verify` | Phase 2: Go calls DeepSeek directly (vision for Notes Scanner, Auto-CT MCQs, Pain Point Matrix analytics); output validated against the OpenAPI/JSON-Schema shapes; per-user quota. **Later: extracted to `applications/ai` (Python FastAPI)** behind the same interface — clients never change |
| Auth | **Custom Go auth** — argon2id (x/crypto) · access + refresh JWTs (mobile) · http-only sessions (web) · **phone OTP via a local SMS gateway** (e.g. SSLWireless) · **social SSO: Google + GitHub** (`golang.org/x/oauth2` / `coreos/go-oidc`) | latest `verify` | Decision recorded 2026-09-29 (Clerk evaluated and rejected — see "Deliberately not used"). Five roles: Super Admin, School Admin, Teacher, Student, Guardian; tenancy + verification claims in the JWT |
| Uploads | **Cloudflare R2** (S3-compatible API, zero egress fees) + magic-byte sniffing | latest `verify` | Decision recorded 2026-09-29 — all media (chat images, voice notes, PDFs, scanned notes) and generated PDF receipts go to R2; clients upload via presigned URLs, api never proxies file bytes |
| Payments | **bKash / Nagad / SSLCommerz** via server-side HTTP integrations | `verify` | Fee payments + marketplace; webhook signature verification, idempotent ledger (`prd.md` §5.4) |
| Notifications content | Firebase Admin Go SDK per-token send (FCM HTTP v1) | — | Expo push API not used (2026-09-30) |
| Validation | Generated OpenAPI validators + per-field rules in services | — | Every entry point; same shapes as the TS clients |
| Logging | `log/slog` (JSON stdout, redacted) | stdlib | |
| Testing | `go test` unit (services) + integration against a real Postgres (testcontainers-go) | testcontainers-go v0.44.0 · golangci-lint v2.14.0 (`tools.mod`) | Tenant-isolation and webhook tests are mandatory |
| Queueing | In-DB job table + Go worker (same binary, `worker` subcommand, own container) | — | Year-end migration, AI batch analytics, receipts, email — no Kafka/RabbitMQ until measured need. Evaluate **River** (Postgres job queue for Go) in 01's Stage 1 plan before hand-building |
| Email (app) | SMTP submission to **HestiaCP Exim** as `noreply@kusholconnect.com` (Go SMTP client, 587 STARTTLS) | — | OTP codes, password reset, vendor invites, opted-in notifications (06 channel). Upgrade path: transactional provider API if deliverability suffers |
| PDF (receipts) | `verify` — chosen by module 12's Bengali-shaping spike | — | Must shape Bengali conjuncts correctly |

## applications/ai — AI service (later; Phase 2+)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Language / framework | **Python 3.12+ / FastAPI** | latest `verify` | Spun up when DeepSeek orchestration outgrows the Go interface: prompt chains, document parsing, embedding pipelines |
| Contracts | Same OpenAPI spec — `ai` exposes its internal endpoints there too | — | Web/app still never call it directly; only `api` does |
| AI | DeepSeek SDK, prompt versioning in code, structured-output validation (pydantic) | latest `verify` | Quotas enforced at the `api` boundary |
| Deploy | Own container in the Compose stack | — | Module 08 builds the Go-side interface first; the FastAPI swap is an infra change, not a client change |

## Tooling (per application — nothing shared)

| Layer | Technology | Notes |
| --- | --- | --- |
| Repositories | One git repo per application (`api`, `web`, `app`, `ai`) · no root workspace, no shared package | Each app has its own `Makefile`/`package.json` scripts, lockfile and CI workflow |
| API contracts | `applications/api/openapi/openapi.yaml` (OpenAPI 3.1, owned by api) | Generates Go server types + validators in api (oapi-codegen, `make contracts`); `web`/`app` sync a copy (`pnpm sync:api-spec`) and generate their own client (`pnpm generate:api`, openapi-typescript/openapi-fetch) into `src/api/` — never hand-write API types. A spec change in api is followed by a sync PR in each client repo |
| Per-app shared code | `src/i18n` · `src/theme` · `src/schemas` · `src/api` inside `web` and inside `app` | bn/en catalogs, design tokens (from `docs/design-reference/README.md`), zod form schemas mirroring the OpenAPI shapes, generated client — each app owns its copy |
| i18n | JSON catalogs per app: `applications/{web,app}/src/i18n` (bn default, en); server-rendered copy in `applications/api/internal/i18n` | RTL not needed; date/number via `Intl` with `bn`/`en` locales; namespace registry in 02 `02` §1.1 |
| Env validation | zod-parsed env (TS apps) · **caarlos0/env v11.4.1** for Go (picked at 01) — no viper | Never read env outside a config module |
| Lint/format | ESLint 10 (flat, type-checked; ESLint 9 is out of support as of 2026-09-30) + Prettier · golangci-lint v2 + gofmt/goimports | Per-app config. Boundary rule in web/app: the api is reached only through the app's generated client in `src/api` |
| CI | GitHub Actions — one workflow per app repo | api: gofmt/goimports, golangci-lint, `go vet`, unit + testcontainers integration, codegen drift; web/app: `pnpm lint/typecheck/test/build` + client drift; EAS build on `app` changes |

## Infrastructure

| Component | Choice | Notes |
| --- | --- | --- |
| Host | **Hostinger KVM 2 VPS** (2 vCPU / 8 GB RAM / 100 GB NVMe) — **shared with 2 other applications** | Decision recorded 2026-09-29. Postgres runs off-box on Neon and media off-box on Cloudflare R2 — the VPS only runs api + web + Redis (+ ai later); cap container memory (Compose `mem_limit`) |
| OS | Ubuntu 24.04 LTS | HestiaCP-supported release |
| Panel | **HestiaCP** | Manages Nginx, Let's Encrypt, DNS, firewall, fail2ban — single shared control plane for all apps on the VPS |
| Reverse proxy | Nginx (HestiaCP-managed, custom proxy templates) | `api.` and `web.` subdomains → containers on `127.0.0.1` ports; HestiaCP templates keep the config out of the containers |
| Containers | Docker Engine + Compose v2 (Docker's apt repo) | Multi-stage builds; api + worker + web + redis (+ ai in Phase 2+); caps api 512m / worker 256m / web 512m / redis 256m; ports bound to `127.0.0.1` only; Postgres off-box on Neon, media off-box on R2 |
| TLS | Let's Encrypt via HestiaCP | Auto-renewal |
| CI / registry | GitHub Actions + GHCR | Go and TS images built in CI and pulled by the VPS — never build images on the KVM 2 (2 vCPU is too tight, especially with other tenants) |
| Domain / DNS | `kusholconnect.com` (Hostinger registrar): apex = web (+ `/api/*` → api), `api.` = mobile API/WebSocket, `mail.`/`webmail.` = HestiaCP mail | Plan: `docs/infra/architecture-and-deployment.md` §6 |
| Email | **HestiaCP mail server** on the VPS (Exim/Dovecot) for team mailboxes; the api sends OTP codes + notifications as `noreply@kusholconnect.com` over SMTP 587 (Go `net/smtp`-class client, module 06 channel) | Owner decision 2026-09-30; transactional-provider upgrade path if deliverability suffers — plan §7 |
| Deployment method | Docker Engine + Compose over SSH behind HestiaCP Nginx — Hostinger's Docker Manager does **not** support the HestiaCP OS image | Verified via Hostinger API 2026-09-30 |
| Monitoring | External uptime checker on `/healthz` + `/readyz` (`TODO: Confirm` provider) · error tracking for api/web/app (Sentry-class free tier, `TODO: Confirm`) | Plan F12 — decide before pilot |
| Backups | Neon automated backups (point-in-time on paid) + periodic `pg_dump` + R2 bucket versioning + off-site copy | Restore drill documented in the runbook (module 15) |

## Deliberately not used (until a measured need)

| Not used | Why |
| --- | --- |
| Microservices beyond `ai`, Kubernetes | Go `api` is a single deployable; the FastAPI AI service is the one allowed split, behind an internal interface |
| Socket.IO | gorilla/websocket + Redis pub/sub covers rooms/fan-out with less machinery; the RN client speaks plain WebSocket |
| Kafka / RabbitMQ | In-DB job table + Go worker covers migration/AI batches |
| Redis Streams as primary chat store | PostgreSQL + Redis cache is enough at MVP scale |
| Auth.js / Clerk / Firebase Auth | Five-role RBAC with school-scoped permissions is explicit and small. **Clerk specifically rejected (2026-09-29):** free tier ends at 10k MAU while the BRD targets ~20k users in year 1 (~$25/mo per extra 1k MAU), Bangladesh is phone-first (local SMS gateways beat Clerk SMS on cost/routing), tenancy/verification claims would be custom code anyway |
| ORM (GORM/Ent) | sqlc gives type-safe queries from plain SQL — no reflection, reviewable migrations |
| MinIO / self-hosted S3 | Cloudflare R2 chosen (2026-09-29): S3-compatible, zero egress fees, no storage container on the shared VPS |
| Live video classes | Out of scope per `brd.md` §4 (Zoom/Meet remain) |
| In-house courier management | Third-party courier APIs only per `brd.md` §4 |
| date-fns / moment | `Intl` covers bn/en formatting |
