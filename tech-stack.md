# Tech Stack — Kushol Connect (কুশল)

Monorepo layout (pnpm workspaces + Turborepo for web/app/shared; Go module for the API):

```text
applications/
├── api/    # Backend — Go: REST + WebSocket messaging, multi-tenant PostgreSQL, Redis, FCM, DeepSeek
├── ai/     # (later, Phase 2+) — Python FastAPI AI service (DeepSeek orchestration) behind an internal HTTP interface
├── web/    # Next.js — public landing page (B2B funnel) + Command Center (Super Admin / School Admin / Vendor)
└── app/    # React Native (Expo) — mobile app for Students, Teachers, Guardians
packages/
└── shared/ # bn/en i18n message catalogs, design tokens; TS-side API clients generated from the OpenAPI spec
contracts/
└── openapi/ # API contract: OpenAPI 3.1 spec — generates Go server types (oapi-codegen)
             # and TS clients (openapi-typescript/openapi-fetch) for web/app — single source of truth
```

Exact versions are pinned in each app's lockfile (`pnpm` with `save-exact`; `go.mod` for the API).
Rows marked `verify` belong to modules not yet built. Aligned with `prd.md` §6 and `brd.md` §6
(cost efficiency), with the backend decision resolved: **Go** for `api` (messaging included),
**Python FastAPI** for the AI service later.

## applications/app — Mobile (Students, Teachers, Guardians)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Framework | **Expo SDK** (managed workflow) | latest stable `verify` | OTA updates via EAS; Android APK direct + Play Store; iOS via TestFlight (`prd.md` §4B) |
| UI runtime | React Native + React | latest stable `verify` | Hermes engine |
| Navigation | **expo-router** (file-based) | latest `verify` | Typed routes; deep links for payment/notification payloads |
| Language | TypeScript (strict) | latest `verify` | |
| Styling | **NativeWind** (Tailwind for RN) + shared tokens | latest `verify` | Tokens from `packages/shared` mapped to the brand system (`design-reference/README.md`) |
| Components | shadcn-style hand-written RN primitives on **zeego**/radix-primitives where useful | `verify` | |
| Icons | lucide-react-native | latest | |
| Fonts | **Hind Siliguri** (Bengali UI + display) · **Inter** (Latin) via @expo-google-fonts | bundled | Bangla glyphs are a launch requirement, not an add-on |
| State (server) | **TanStack Query** | 5.x | Chat + marketplace lists |
| State (client) | zustand | latest `verify` | Session, settings, cached roster |
| Forms | react-hook-form + zod resolver | 7.x / **zod 4.x** | Schemas imported from `packages/shared` |
| Chat | Plain **WebSocket** client to the Go gateway + optimistic UI | stdlib `verify` | Offline queue, media (image/voice) compression before upload |
| Push | **expo-notifications** → FCM topics | latest `verify` | Topic subscriptions mirror the hierarchy (city/school/section — `brd.md` §6) |
| AI capture | expo-camera / expo-image-picker | latest `verify` | Notes Scanner input for DeepSeek vision |
| Testing | **Maestro** (E2E flows) + jest-expo (unit) | latest `verify` | Onboarding → verify → join section group is the golden path |
| Build/CI | **EAS Build & Submit** | cloud | APK/TestFlight distribution per `brd.md` §8 Phase 1 |

## applications/web — Landing + Command Center

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Framework | **Next.js** (App Router) | latest stable `verify` | `output: "standalone"` for Docker |
| Language | TypeScript (strict) | latest `verify` | |
| Styling | **Tailwind CSS** + CSS-first `@theme` tokens | v4 `verify` | Semantic tokens from `packages/shared`; light theme first, dark optional |
| Components | shadcn/ui on radix-ui | latest `verify` | Hand-written into `src/components/ui/` to keep token control |
| Icons | lucide-react | latest | |
| Fonts | Hind Siliguri · Inter (via `next/font/google`) | bundled | `latin` + `bengali` subsets |
| Data tables | **TanStack Table** + TanStack Query | latest `verify` | Rosters, ledgers, campaign builders (School Admin / Super Admin / Vendor portals) |
| Forms | react-hook-form + zod | 7.x / 4.x | Shared schemas from `packages/shared` |
| Charts | Recharts | latest `verify` | Pain Point Matrix heatmap, revenue dashboards — only where useful |
| Markdown | Not needed at launch `verify` | — | Notices are plain text + attachments |
| Testing | Vitest + Testing Library · **Playwright** (+ axe) | latest `verify` | Web golden paths: landing funnel, admin login, CSV roster upload, campaign creation |
| SEO | Metadata API, OG images, JSON-LD (Organization), sitemap | bundled | Landing page is the B2B acquisition funnel (`prd.md` §4A) |

## applications/api — Backend (Go)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Language | **Go** | 1.24+ (`.go-version`) | Decision resolved: Go for the whole API, including the messaging hot path (`prd.md` §6); Docker `golang` multi-stage → `distroless/static` (or alpine) runtime |
| HTTP framework | **chi** (net/http compatible) | latest `verify` | Small, explicit, idiomatic; REST endpoints |
| Contracts | **OpenAPI 3.1** spec in `contracts/openapi/` → `oapi-codegen` (Go types/handlers) + `openapi-typescript`/`openapi-fetch` (TS clients for web/app) | latest `verify` | Spec is written first; request/response validation generated from it |
| Realtime / messaging | **gorilla/websocket** (+ Redis pub/sub fan-out across instances) | latest `verify` | **Messaging lives in Go**: rooms mirror City → School → Section and custom groups; presence in Redis |
| Database | **PostgreSQL** (multi-tenant, shared-schema + tenant scoping) — hosted on **Neon** free tier (Singapore `ap-southeast-1`) for quick start | 16+ `verify` | Decision recorded 2026-09-29: Neon over Supabase (pure Postgres, DB branches fit the migration workflow; Supabase free pauses after 1 week idle). Free tier scales to zero (cold start ~hundreds of ms) — fine for dev/pilot, upgrade (Launch ~$19/mo) or move back to a Compose container when real school traffic starts. Tenant columns enforced in the repository layer; `pg_trgm` for search |
| Data access | **sqlc** (type-safe generated queries) + **pgx/v5** driver | latest `verify` | Migrations as plain SQL files (golang-migrate or goose), expand/contract |
| Cache / presence | **Redis** (go-redis) | 7 `verify` | Chat cache, online presence, rate limits, idempotency keys (`prd.md` §6) |
| Push | **Firebase Admin Go SDK** → **FCM topic subscriptions** | latest `verify` | Topic-per-node fan-out for mass notices (`brd.md` §6) |
| AI | **DeepSeek API** behind an internal `AIService` Go interface | latest `verify` | Phase 2: Go calls DeepSeek directly (vision for Notes Scanner, Auto-CT MCQs, Pain Point Matrix analytics); output validated against the OpenAPI/JSON-Schema shapes; per-user quota. **Later: extracted to `applications/ai` (Python FastAPI)** behind the same interface — clients never change |
| Auth | **Custom Go auth** — argon2id (x/crypto) · access + refresh JWTs (mobile) · http-only sessions (web) · **phone OTP via a local SMS gateway** (e.g. SSLWireless) · **social SSO: Google + GitHub** (`golang.org/x/oauth2` / `coreos/go-oidc`) | latest `verify` | Decision recorded 2026-09-29 (Clerk evaluated and rejected — see "Deliberately not used"). Five roles: Super Admin, School Admin, Teacher, Student, Guardian; tenancy + verification claims in the JWT |
| Uploads | **Cloudflare R2** (S3-compatible API, zero egress fees) + magic-byte sniffing | latest `verify` | Decision recorded 2026-09-29 — all media (chat images, voice notes, PDFs, scanned notes) and generated PDF receipts go to R2; clients upload via presigned URLs, api never proxies file bytes |
| Payments | **bKash / Nagad / SSLCommerz** via server-side HTTP integrations | `verify` | Fee payments + marketplace; webhook signature verification, idempotent ledger (`prd.md` §5.4) |
| Notifications content | expo-server-sdk equivalent (plain HTTPS push API) | — | |
| Validation | Generated OpenAPI validators + per-field rules in services | — | Every entry point; same shapes as the TS clients |
| Logging | `log/slog` (JSON stdout, redacted) | stdlib | |
| Testing | `go test` unit (services) + integration against a real Postgres (testcontainers-go) | stdlib `verify` | Tenant-isolation and webhook tests are mandatory |
| Queueing | In-DB job table + Go worker process `verify` | — | Year-end migration, AI batch analytics, receipt generation — no Kafka/RabbitMQ until measured need |

## applications/ai — AI service (later; Phase 2+)

| Layer | Technology | Version | Notes |
| --- | --- | --- | --- |
| Language / framework | **Python 3.12+ / FastAPI** | latest `verify` | Spun up when DeepSeek orchestration outgrows the Go interface: prompt chains, document parsing, embedding pipelines |
| Contracts | Same OpenAPI spec — `ai` exposes its internal endpoints there too | — | Web/app still never call it directly; only `api` does |
| AI | DeepSeek SDK, prompt versioning in code, structured-output validation (pydantic) | latest `verify` | Quotas enforced at the `api` boundary |
| Deploy | Own container in the Compose stack | — | Module 08 builds the Go-side interface first; the FastAPI swap is an infra change, not a client change |

## Shared & tooling

| Layer | Technology | Notes |
| --- | --- | --- |
| Monorepo | pnpm workspaces + **Turborepo** (web/app/shared) · Go module for `api` | One lockfile discipline per app; shared tasks cached; `Makefile`/`task` entry points per app |
| API contracts | `contracts/openapi/` OpenAPI 3.1 spec | Generates Go server types + validators (oapi-codegen) and TS clients (openapi-typescript/openapi-fetch) — web/app never hand-write API types |
| Shared package | `packages/shared` | bn/en message catalogs, design tokens — the single source for TS-side non-API concerns; **Zod schemas stay for web/app forms**, mirroring the OpenAPI shapes |
| i18n | JSON catalogs in `packages/shared` (bn default, en) | RTL not needed; date/number via `Intl` with `bn`/`en` locales |
| Env validation | zod-parsed env (TS apps) · `envconfig`/viper-style parsed config (Go) | Never read env outside a config module |
| Lint/format | ESLint 9 (flat, type-checked) + Prettier · golangci-lint + gofmt/goimports · Husky + lint-staged | Boundary rule: app/web → api only through the generated OpenAPI client |
| CI | GitHub Actions | Quality gate per app (`go test/vet/lint` for api; `pnpm lint/typecheck/test/build` for web/app); EAS build on `app` changes |

## Infrastructure

| Component | Choice | Notes |
| --- | --- | --- |
| Host | **Hostinger KVM 2 VPS** (2 vCPU / 8 GB RAM / 100 GB NVMe) — **shared with 2 other applications** | Decision recorded 2026-09-29. Postgres runs off-box on Neon and media off-box on Cloudflare R2 — the VPS only runs api + web + Redis (+ ai later); cap container memory (Compose `mem_limit`) |
| OS | Ubuntu 24.04 LTS | HestiaCP-supported release |
| Panel | **HestiaCP** | Manages Nginx, Let's Encrypt, DNS, firewall, fail2ban — single shared control plane for all apps on the VPS |
| Reverse proxy | Nginx (HestiaCP-managed, custom proxy templates) | `api.` and `web.` subdomains → containers on `127.0.0.1` ports; HestiaCP templates keep the config out of the containers |
| Containers | Docker Engine + Compose v2 | Multi-stage builds; api + web + redis (+ ai in Phase 2+); Postgres off-box on Neon, media off-box on R2 |
| TLS | Let's Encrypt via HestiaCP | Auto-renewal |
| CI / registry | GitHub Actions + GHCR | Go and TS images built in CI and pulled by the VPS — never build images on the KVM 2 (2 vCPU is too tight, especially with other tenants) |
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
