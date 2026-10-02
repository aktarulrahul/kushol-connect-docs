# Organization Hierarchy — Technical Document

**Module:** `04-organization-hierarchy` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Overview

### 1.1 Purpose

Provides the City → School → Section hierarchy every other module hangs from (`brd.md` §5 BR-01,
`prd.md` §5.1): school/tenant onboarding, class/section management, the public picker data behind
registration, auto-grouping of verified users into section groups and FCM topics, and the idempotent
year-end migration that promotes or graduates students.

### 1.2 Scope

**In:** data model + migrations (`cities`, `schools`, `sections`, `enrollments`, `fcm_topic_bindings`,
`migration_runs`, `migration_run_items`) · public picker reads · Super Admin onboarding (tenant +
pre-verified first School Admin), city management, soft-only archiving · School Admin sections,
teacher assignment, roster read API · auto-grouping seam `OnUserVerified` → enrollment → 05 join →
topic bindings · year-end migration (preview → job-driven, idempotent, audited commit) · bn/en keys
`hierarchy.*` / `validation.*`.
**Out:** chat internals (05) · device tokens/push (06) · roster parsing (14/07) · campaign/analytics
logic (13/09, read-only exports) · landing-funnel self-signup (Phase 3) · promotion-rule changes —
`TODO: Confirm` (OQ-2).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes / consumed by | 03 identity-access | We consume `users.GetWithSelection` (VERIFIED status + registration-time section choice) + pre-verified School Admin bootstrap; 03 calls `hierarchy.OnUserVerified` at its verify handler |
| consumes | 01 foundations | `jobs` table + worker (`migration.run`, `hierarchy.backfill`), RFC-7807 envelope, config parsing, audit-log sink |
| consumes | 05 communication-engine (interface-first) | `chat.JoinSectionGroups(userID, enrollment)` · `chat.ArchiveSectionGroups(schoolId, sessionYear)` |
| consumed by | 05 / 06 | 05 calls `hierarchy.ResolveUserNodes` (WS room resolution, notice scoping); 06 reads `fcm_topic_bindings` + `ResolveUserNodes` (04 never calls 06) |
| consumed by | 07 / 09 / 13 / 14 | 07 admin screens via REST; 09/13 read-only exports (`ResolveUserNodes` / `GetSection`, aggregates only); 14 `CreateEnrollments(batch, source)` |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| Contracts / API runtime | OpenAPI 3.1 → oapi-codegen · Go 1.24+ · chi REST · `log/slog` | Generated handlers + validators; resolved stack (`docs/tech-stack.md`) | No WebSocket in this module |
| Data access | sqlc + pgx/v5 · PostgreSQL 16 on Neon (ap-southeast-1) | Plain tenant-scoped SQL; testcontainers-go for ITs | Fixed 3-level FK model (ADR in `07-progress.md`) |
| Cache | Redis (go-redis) | Picker reads cached 24 h with tag invalidation | Down → read-through to Postgres, degraded never fatal |
| Queueing | In-DB `jobs` table + Go worker (01) | `migration.run` + `hierarchy.backfill`; no Kafka/RabbitMQ | 500-item batches |
| i18n (per app) | each app's `src/i18n` — `hierarchy.*` / `validation.*` | bn + en names in every payload | ~1 KB gzip per app |
| Web / App / Realtime | None — API-only module (README row: `api` + `shared`) | Web surfaces are 07; picker UI is 03; push is 06 | `ORG-FE-*` / `ORG-AP-*` do not exist |

---

## 3. Architecture

### 3.1 Component diagram

```text
03 verify handler       07 Command Center (web)       03 onboarding pickers (public)
  │ OnUserVerified           │ REST (openapi-fetch)         │ GET /api/v1/hierarchy/*
  ▼                          ▼                               ▼
[chi handlers] ──► [hierarchy services] ──► [tenant-scoped repositories] ──► sqlc ──► PostgreSQL (Neon)
                         │            ▲
                         │            └─ Redis cache (24 h TTL; tags hierarchy:cities, hierarchy:school:{id})
                         ├─► 05: chat.JoinSectionGroups / chat.ArchiveSectionGroups
                         ├─► 01 jobs.Enqueue → worker: migration.run · hierarchy.backfill
                         └─► 03: users.GetWithSelection       06 reads fcm_topic_bindings (one-way)
```

### 3.2 Boundary

**Owns (tables / services):** `cities`, `schools`, `sections`, `enrollments`, `fcm_topic_bindings`,
`migration_runs`, `migration_run_items` — plus the promotion engine (pure function, `ORG-BE-012`).
**Reads (via exported service functions only):** 03 `users.GetWithSelection` · 05
`chat.JoinSectionGroups` / `chat.ArchiveSectionGroups` · 01 `jobs.Enqueue` + worker runtime.
Cache-tag contract: `06-integration-tasks.md` §4.

### 3.3 Request / data flows

```text
1. Picker read: handler → ListCities/ListSchoolsByCity/ListSectionsBySchool → Redis (24h TTL)
   → Postgres on miss → ACTIVE nodes only, bn+en names
2. Provisioning: POST /admin/schools → 1 tx: school + school-{id} binding + pre-verified
   School Admin (03) → audit + cache invalidation
3. Auto-grouping (BR-01): 03 verify → OnUserVerified → users.GetWithSelection (03)
   → tx: enrollment (idempotent) + bindings (section-/school-/city-{id})
   → 05 JoinSectionGroups → on failure jobs hierarchy.backfill (user stays VERIFIED)
   → 06 reads bindings, subscribes devices
4. Migration: dryRun → promotion engine → commit → jobs migration.run → 500-item tx batches
   (end + insert + re-bind; applied_at checkpoints) → 05 archives old groups → COMMITTED + audit
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `migration_runs.state` | DRAFT → PREVIEWED → COMMITTED | DRAFT→PREVIEWED on re-preview `dry_run=false` with zero ERROR items; PREVIEWED→COMMITTED on commit (job applies all items, terminal); apply failure stays PREVIEWED — job retries from first unapplied item; any other commit → `CONFLICT` (`ORG-INV-005`) |
| `enrollments.status` | ACTIVE → ENDED / ALUMNI | migration apply (RETAINED stays ACTIVE); graduation at Class 10/12 (`ORG-BR-009`) |
| `schools.status` | ACTIVE ↔ ARCHIVED | Super Admin archive / re-open; soft only (`ORG-BR-004`) |
| `sections.status` | ACTIVE → ARCHIVED | archive blocked while ACTIVE enrollments (except migration); old-session sections archived at migration |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `cities` | Platform geography (Dhaka + Chattogram launch) | Platform table — public read is names-only | `(status, is_launch_city)` | Unique `name_en`/`name_bn`; soft `ACTIVE/ARCHIVED` |
| `schools` | Tenant root; `id` = tenant id in JWT claims | `id` IS the tenant — children carry `school_id` | `(city_id, status)` | Unique name pair per city; `created_by` Super Admin |
| `sections` | Class + section per session (Class 6 → A/B) | `school_id` tenant column | `(school_id, session_year, status)` · `(school_id, class_level)` | CHECK class 1–12; unique `(school_id, class_level, name, session_year)` |
| `enrollments` | user ↔ section with role + session + source | `school_id` tenant column | `(section_id, role, status)` · `(school_id, session_year, status)` · `(user_id, session_year)` | Partial unique `(user_id, session_year) WHERE role='STUDENT' AND status='ACTIVE'`; idempotency unique `(user_id, section_id, role, session_year)` |
| `fcm_topic_bindings` | Node → deterministic topic (`city-{id}` / `school-{id}` / `section-{id}`) | Node id resolves to a tenant | unique `(node_type, node_id)` · unique `(topic_name)` | Created in the node's transaction (`ORG-BR-011`); read by 06 |
| `migration_runs` | One year-end migration per school per session | `school_id` tenant column | `(school_id, from_session_year)` | Partial unique `(school_id, from_session_year) WHERE state <> 'DRAFT'`; `CHECK to = from + 1` |
| `migration_run_items` | Per-enrollment result + applied checkpoint | Tenant via run | `(run_id, applied_at)` · `(run_id, action)` | unique `(run_id, enrollment_id)`; `applied_at` = resume checkpoint |

---

## 5. Contracts

### 5.1 REST endpoints

All under `/api/v1`; RFC-7807 errors; full shapes in `03-backend-tasks.md` §2. Rate limits: default
class; school creation and migration create/commit 5/hour.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | GET `/hierarchy/cities` · GET `/hierarchy/cities/{cityId}/schools` · GET `/hierarchy/schools/{schoolId}/sections` | Public | Picker: ACTIVE nodes only, bn+en, launch cities first, no counts | `NOT_FOUND`, `VALIDATION_FAILED` | ORG-US-003/009 |
| 2 | POST `/admin/cities` | Super Admin | Add city (+ launch flag); invalidates `hierarchy:cities` | `CONFLICT` dup, `FORBIDDEN` | ORG-US-009 |
| 3 | POST `/admin/schools` · PATCH `/admin/schools/{schoolId}` | Super Admin | Tenant + `school-{id}` binding + pre-verified School Admin (1 tx); rename/archive/re-open (soft only) | `CONFLICT`, `NOT_FOUND` | ORG-US-001 |
| 4 | POST `/school/sections` · PATCH `/school/sections/{sectionId}` | School Admin | Create section (+ `section-{id}` binding in tx) / rename / archive (blocked with ACTIVE enrollments) | `CONFLICT` (`ORG-BR-002`), `TENANT_MISMATCH` | ORG-US-002/005 |
| 5 | POST `/school/sections/{sectionId}/teachers` | School Admin | Assign TEACHER / CLASS_TEACHER; informs 05 for group ownership | `NOT_VERIFIED`, `CONFLICT` (`ORG-BR-007`) | ORG-US-006 |
| 6 | GET `/school/enrollments` | School Admin / Teacher (own sections) | Paged roster (max 100) — migration pre-check | `VALIDATION_FAILED`, `FORBIDDEN` | ORG-US-005/007 |
| 7 | POST `/school/migrations` (dryRun) · GET `/{runId}` · POST `/{runId}/commit` | School Admin | Dry-run (DRAFT) / preview (PREVIEWED, zero ERROR) / commit → `migration.run` job | `CONFLICT` wrong state / ERROR items / open run, `TENANT_MISMATCH` | ORG-US-007/008 |

### 5.2 Realtime / jobs

No WebSocket in this module — jobs and cache tags below (`03` §5, `06` §4).

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `migration.run` (`ORG-BE-024`) | `POST …/commit` enqueues via 01 `jobs` | 500-item transactional batches: end old enrollment + insert new + refresh bindings; archive old-session groups via 05 | `migration_run_items.applied_at` checkpoints; 07 wizard polls run | Retry with backoff; resumes from first unapplied item; alert + run stays PREVIEWED after N failures |
| `hierarchy.backfill` (`ORG-BE-025`) | 05 join (or topic refresh) fails inside `OnUserVerified` | Idempotent group joins via `chat.JoinSectionGroups` | 05 membership; user stays VERIFIED throughout | ×5 backoff → dead-letter + admin report |
| cache tags `hierarchy:cities` · `hierarchy:school:{id}` | city/school/section mutations; migration apply | Invalidate 24 h picker cache + `GetSection` export reads | pickers; 05/06/09/13 exports | Redis down → read-through to Postgres (slower, never fatal) |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — frozen for Phase 1; DTOs only, domain errors only.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `hierarchy.OnUserVerified(userId)` | 03 verify handler | The (idempotent) enrollment from the registration-time section choice | `NOT_FOUND` (no selection), `VALIDATION_FAILED` |
| `hierarchy.ResolveUserNodes(userId)` | 05 (rooms), 06 (topics), 09, 13 | city/school/active-section ids + topic names | `NOT_FOUND` |
| `hierarchy.GetSection(sectionID)` | 05, 09, 13 | Section identity (class level, name, session, school); cached read | `NOT_FOUND` |
| `hierarchy.CreateEnrollments(batch, source)` | 14 roster ingestion | Per-row result (created / exists / error); idempotent batch, rows never silently dropped | `VALIDATION_FAILED` (whole-batch shape) |
| `hierarchy.PreviewMigration(schoolID, from, dryRun)` | 07 migration wizard | Run + items (PROMOTED/GRADUATED/RETAINED/ERROR); `dryRun=true` → DRAFT, `false` → PREVIEWED | `VALIDATION_FAILED`, `CONFLICT` |
| `hierarchy.CommitMigration(runID)` | 07 migration wizard | Run COMMITTING→COMMITTED; tenant claims checked inside | `CONFLICT`, `NOT_FOUND` |
| `hierarchy.PlatformCounts()` / `SchoolCounts(schoolID)` | 07 dashboards | aggregate counts | `FORBIDDEN` / `TENANT_MISMATCH` |
| `hierarchy.AudienceCount(filter)` | 13 | VERIFIED-user count for a city/school/class/stream/role segment; small counts suppressed | `VALIDATION_FAILED` |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

N/A — no web screens (`ORG-FE-*` does not exist; apps `api` + `shared` only). Module 07 builds the
admin surfaces against this module's endpoints: `/admin/tenants`, `/admin/tenants/new`,
`/admin/cities` (Super Admin) and `/school/sections`, `/school/sections/[sectionId]`,
`/school/migrations/new` (School Admin). This module guarantees bn + en names and stable ids in every
payload so 07's screens stay accessible.

### 6.2 Mobile (detail in `05-app-tasks.md`)

N/A — no mobile app screens (`ORG-AP-*` does not exist). The City → School → Section picker UI is
module 03 onboarding (`IDT-AP-*`); this module owns only the data contract (three public picker
endpoints + bn/en strings). Auto-grouping is server-side at verification — no client call; migration
and tenant management are Command Center (web, 07) surfaces, never in-app.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM | Indirect only — the topic naming contract `city-{id}` / `school-{id}` / `section-{id}`; all FCM SDK calls live in module 06 | n/a (no SDK here) | `FCM_SERVER_KEY` held by 06, never by 04 | n/a here; 06 owns retry | Degraded, never fatal — bindings are durable rows; device subscriptions converge when 06/FCM recover |
| (none other) | This module touches no R2, DeepSeek, payment or SMS systems (`06-integration-tasks.md` §5) | — | — | — | — |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None — no env vars declared for this module (`03-backend-tasks.md` §2) | — | The picker `launch` default (`HIERARCHY_LAUNCH_ONLY=true`) and migration batch size 500 are config-module constants (`02` §5/§9), not env vars | — |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| City list (add/archive; launch flag) | Topic naming scheme `city-{id}` / `school-{id}` / `section-{id}` |
| School tenants + first School Admin onboarding | Promotion class order (+1; graduation at 10/12) — `TODO: Confirm` (constant until confirmed) |
| Classes/sections per session year | Role→endpoint permission matrix (Super Admin / School Admin / Teacher) |
| Class-teacher assignments per section | Public-read exposure set (names only, no counts) |
| Migration `fromSessionYear` per school (one open run per session) | Launch-city filter default (`launch=true`) and migration batch size (500) |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope (02 §6); the three public picker reads are the only no-auth surface |
| Role matrix | Super Admin: `/admin/*` (cities, schools, archive) · School Admin: `/school/*` (sections, teachers, roster, migrations) · Teacher: roster read limited to assigned sections · Student/Guardian: none (auto-grouping is server-side) |
| Tenant scope | Every school-scoped query filtered by the caller's `schoolId` claim; repositories accept no caller-supplied `school_id` (`ORG-BR-001`, `ORG-INV-006`); cross-tenant attempts → `TENANT_MISMATCH`/404 (proven by `ORG-IT-002`, incl. forged `?schoolId=`) |
| Rate limits | Default class everywhere; school creation and migration create/commit 5/hour (per admin / per school) |
| Audit events | city created; tenant provisioned / renamed / archived; section archived; class-teacher assignment; migration preview created; migration committed |
| Privacy / minors | Public endpoints expose ACTIVE nodes, names only — never enrollments, counts or admin identity (`ORG-BR-010`); minors' data never leaves tenant scope (`brd.md` §6); 09/13 get aggregate counts only; strict `TENANT_MISMATCH` on every cross-tenant path |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `UNAUTHENTICATED` / `FORBIDDEN` | No credentials / wrong role | Any `/admin/*` or `/school/*` route without JWT; non-Super-Admin on `/admin/*`; teacher outside own sections | Route to login (03); hide action |
| `TENANT_MISMATCH` (404 body) | Cross-tenant access | School Admin A addressing school B's sections/enrollments/migrations; request-supplied school ids ignored | Never reveal existence; not-found state |
| `NOT_VERIFIED` | Target user pending | Teacher assignment for a PENDING user | "How to get verified" guidance |
| `CONFLICT` | Duplicate / illegal transition | Duplicate school/section/city names; second CLASS_TEACHER; commit on DRAFT/COMMITTED/ERROR run; open run exists | Surface `hierarchy.*.name_duplicate`; fix run state, re-preview |
| `VALIDATION_FAILED` | Bad input | OpenAPI validators + `01` §6 rules (class 1–12, session year, name lengths, paging) | Inline field errors from `validation.*` / `hierarchy.*` keys |
| `NOT_FOUND` / `INTERNAL` | Missing node / unexpected | Unknown city/school/section/run; no registration selection in `OnUserVerified` / unhandled errors | Empty/404 state; generic error + support path |
| `RATE_LIMITED` | Bucket exceeded | 5/hour school creation, migration create/commit | Retry-later toast |

All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via
each app's `src/i18n` catalogs — every key ships in **bn + en** (Bengali default); namespaces
`hierarchy.*`, `validation.*`.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | `slog` JSON stdout (shared base); audit rows for every admin mutation (§9); no PII beyond ids |
| Metrics / counters | Picker cache hit ratio; `jobs` lag for `migration.run` / `hierarchy.backfill`; migration batch failures; run summary counts (PROMOTED/GRADUATED/RETAINED/ERROR) |
| Health contribution | Shared `/readyz` (01) covers DB; deploy-time cache warm-up pings `hierarchy:cities` to absorb Neon cold start (02 §8 #7) |
| Jobs & retries | `migration.run`: retry with backoff, resumes from first unapplied item, alert + run stays PREVIEWED after N failures · `hierarchy.backfill`: ×5 backoff → dead-letter + admin report; user remains VERIFIED |
| Runbook pointers | Redis down → pickers fall through to Postgres (degraded, never fatal) · Neon cold start → warm-up ping + 24 h TTL · migration re-run is safe (idempotent batches) · deploy/rollback/backup drills in module 15 |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Promotion engine mapping (graduation at 10/12, missing-target ERROR); topic-name determinism + launch filter; run state guard; `OnUserVerified` idempotency; validation keys; topic naming contract; `ResolveUserNodes` shape | `ORG-UT-001`–`007` | `go test ./...` |
| Integration | Doubled verify event exactly-once; cross-tenant deny; dry-run→commit applies rules + blocks on ERROR; commit idempotent on retry (crash between batches); pickers hide archived + launch filter; auth chain on every route; 05-outage back-fill; `CreateEnrollments` batch (14); cache-tag invalidation | `ORG-IT-001`–`009` (testcontainers Postgres) | green in CI |
| E2E | None in this module — the Maestro golden path "onboarding → verified → auto-join section group → receive notice" asserts 04's behaviour end-to-end; owned by modules 03/05/06 app specs | — | via those modules |
| CI | api quality gate | — | `go test` / `go vet` / `golangci-lint` |

Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; cross-tenant
attempts return `TENANT_MISMATCH`/404; public reads never return drafts/archived/personal data.

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | 2 launch cities → 10+ schools (year 1) → ~100–300 sections/school-year → ~2,000 enrollments/school; hierarchy metadata low thousands of rows, `enrollments` tens of thousands |
| Hot paths + indexes | Picker reads (cached, tag-invalidated) · enrollment-by-user+session `(user_id, session_year)` · roster `(section_id, role, status)` paged · migration scan `(school_id, session_year, status)` · unique `sections(school_id, class_level, name, session_year)` · unique `fcm_topic_bindings(topic_name)` |
| Latency targets | Picker reads served from Redis (24 h TTL); Neon cold start absorbed by warm-up ping; migration apply in 500-item batches — a 2,000-student school = 4 transactions, inside the `jobs` worker budget |
| Bundle / payload impact | None for apps (API-only); each app's `src/i18n` gains `hierarchy.*` (~1 KB gzip) |
| Caching | Redis, 24 h TTL, tag invalidation on every mutation (`06` §4); admin reads never cached |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the readiness-check table; unconfirmed items keep `TODO: Confirm`.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Which cities are live at launch (OQ-1) | Registration funnel coverage | Rahul | Open | Dhaka + Chattogram only; new cities by Super Admin |
| 2 | Exact promotion rules — graduation classes, RETAINED handling, repeating students, section re-mapping; calendar-year session assumption (`TODO: Confirm`, OQ-2 + 02 §11.1/§11.4) | Wrong students moved at year end; name changes break (class+1, same name) mapping | Rahul | Open — `TODO: Confirm` | +1 within same school; Class 10/12 → ALUMNI; archive old groups; preview ERROR names unmapped students; `fromSessionYear` per-school input, rules in one tested config constant, dry-run mandatory |
| 3 | School onboarding at launch — Super Admin only vs landing self-signup (OQ-3) | Phase-3 scope | Rahul | Open | Super Admin provisions tenant + first pre-verified School Admin |
| 4 | Guardian modeling in enrollments (OQ-4) | Rows vs links | Rahul | Open | Role GUARDIAN enrollment in the student's section |
| 5 | One school per student; guardians 1-to-n; all schools migrate Dec–Jan (02 §11.2/§11.3) | `ORG-INV-001` hit by multi-school students; `jobs` contention in migration weeks | Rahul | Assumption | END old enrollment via roster tooling before re-enrolling; 500-item batches, per-school enqueue, scalable worker |
| 6 | Neon free tier cold starts delay first picker read (02 §11.5) | Funnel feels slow | Rahul | Assumption | Cache warm-up after deploy + 24 h TTL |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-01 — hierarchy, onboarding, auto-grouping, year-end migration | §5.1 | `ORG-US-001`–`008` | `ORG-BE-001`–`007`, `010`–`025`, `ORG-INT-001`–`004` | `ORG-UT-001`–`006`, `ORG-IT-001`–`007` |
| BR-05 — ads/analytics segmentation | — (`brd.md` §5) | `ORG-US-010` | `ORG-BE-008`, `ORG-INT-006` | `ORG-UT-007` |
| `brd.md` §6 — multi-tenant privacy | — | `ORG-US-005` | `ORG-BE-013`–`023` (tenant-scoped repos) | `ORG-IT-002` |
| README 04 defaults + module 14 ingestion + cache-tag contract (`06` §4) | — | `ORG-US-003`, `ORG-US-009` | `ORG-BE-001`, `ORG-BE-009`, `ORG-BE-013`, `ORG-INT-004`–`005` | `ORG-UT-002`, `ORG-IT-005`, `ORG-IT-008`–`009` |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migrations re-versioned `20261002…` (build order); `20261002090007` adds deferred FKs onto 03 tables; `sections.stream`; exports `PlatformCounts`/`SchoolCounts`/`AudienceCount`; `JoinSectionGroups(userID, enrollment)` aligned with 05; guardian enrollments read 03 `guardian_links` | Claude |
| 2026-10-02 | Build start (owner-approved plan). ADR-2: onboarding runs through 03's school-request approval calling the new `CreateSchool` export (I-8 in `06` §1/§2); the request's POC becomes the first pre-verified School Admin via 03 `users.CreateProvisionedAdmin`. ADR-3: `schools.type` (`school\|college`, default `school`) added to migration `…090002`. `sections.stream` ships inside `…090003` (covers `ORG-BE-026`). Picker DTO keeps `classLevel` as string (03 client compatibility); admin DTOs use integer | Kilo |
