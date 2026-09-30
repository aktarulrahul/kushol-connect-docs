# Organization Hierarchy — Backend Tasks & Database Design

**Module:** `04-organization-hierarchy`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below is designed until the schema is settled. Every table states its
tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `cities` (model `City`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `name_bn` | `text` | no | — | Bengali name (ঢাকা) |
| `name_en` | `text` | no | — | English name (Dhaka) |
| `is_launch_city` | `boolean` | no | `false` | Launch two-list (02 §5): Dhaka + Chattogram `true` |
| `status` | `text` | no | `'ACTIVE'` | `ACTIVE` / `ARCHIVED` (soft only, `ORG-BR-004`) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** unique `(name_en)`, unique `(name_bn)`. **Tenant scope:** platform table — public read is names-only.
**Indexes:** `(status, is_launch_city)` → picker list.

#### `schools` (model `School`) — tenant root

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK; = tenant id used in JWT claims |
| `city_id` | `uuid` | no | — | FK → `cities` |
| `name_bn` / `name_en` | `text` | no | — | Display names; `created_by` records the provisioning Super Admin (module 03) |
| `status` | `text` | no | `'ACTIVE'` | `ACTIVE` / `ARCHIVED` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FK `city_id`; unique `(city_id, name_en)` and `(city_id, name_bn)`.
**Tenant scope:** `id` IS the tenant — all child tables carry `school_id`.
**Indexes:** `(city_id, status)` → picker; PK → claim lookups.

#### `sections` (model `Section`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK → `schools`; **tenant column** |
| `class_level` | `int` | no | — | 1–12 (Class 6 → A/B pattern). The only "class" concept — there is no `classes` table |
| `stream` | `text` | null | — | CHECK ∈ science/business_studies/humanities; NULL for general sections (typically classes 1–8). Enables BR-05 targeting such as "Class 12 Science in Chattogram" (13) |
| `name` | `text` | no | — | Short label: A, B, … |
| `session_year` | `int` | no | — | e.g. 2026 — drives migration |
| `status` | `text` | no | `'ACTIVE'` | `ACTIVE` / `ARCHIVED` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | `created_by` records the creating School Admin |

**Constraints:** FK `school_id`; `CHECK (class_level BETWEEN 1 AND 12)`; unique `(school_id, class_level, name, session_year)` (`ORG-BR-002`); CHECK `stream` enum. Migration carries `stream` forward on PROMOTED rows.
**Indexes:** `(school_id, session_year, status)` → picker + migration scan; `(school_id, class_level)` → promotion mapping.

#### `enrollments` (model `Enrollment`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → module 03 `users` |
| `school_id` | `uuid` | no | — | FK → `schools`; **tenant column** |
| `section_id` | `uuid` | no | — | FK → `sections` |
| `role` | `text` | no | — | `STUDENT` / `TEACHER` / `CLASS_TEACHER` / `GUARDIAN` |
| `session_year` | `int` | no | — | e.g. 2026 |
| `status` | `text` | no | `'ACTIVE'` | `ACTIVE` / `ENDED` / `ALUMNI` |
| `source` | `text` | no | `'SELF'` | `SELF` / `ROSTER` (module 14) / `MIGRATION` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FKs; `CHECK`s on `role`/`status`/`source`; partial unique `(user_id, session_year) WHERE role='STUDENT' AND status='ACTIVE'` (`ORG-INV-001`); unique `(user_id, section_id, role, session_year)` (idempotency).
**Indexes:** `(section_id, role, status)` → roster; `(school_id, session_year, status)` → migration candidates; `(user_id, session_year)` → `OnUserVerified`/`ResolveUserNodes`.

#### `fcm_topic_bindings` (model `TopicBinding`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `node_type` | `text` | no | — | `CITY` / `SCHOOL` / `SECTION` |
| `node_id` | `uuid` | no | — | Polymorphic node ref |
| `topic_name` | `text` | no | — | `city-{id}` / `school-{id}` / `section-{id}` (`ORG-BR-011`) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** unique `(node_type, node_id)`; unique `(topic_name)`; `CHECK` on `node_type`.
**Tenant scope:** node id resolves to a tenant; module 06 reads by `topic_name`/node.
**Indexes:** `(topic_name)` unique → reverse lookup by 06; `(node_type, node_id)`.

#### `migration_runs` (model `MigrationRun`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK → `schools`; **tenant column** |
| `from_session_year` / `to_session_year` | `int` | no | — | e.g. 2026 → 2027; `CHECK (to = from + 1)` |
| `state` | `text` | no | `'DRAFT'` | `DRAFT` / `PREVIEWED` / `COMMITTED` (`ORG-INV-005`) |
| `total_items` / `promoted` / `graduated` / `retained` / `errors` | `int` | no | `0` | Preview/apply counters |
| `created_by` | `uuid` | no | — | School Admin |
| `committed_at` | `timestamptz` | yes | — | Set when the worker finishes |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FK; partial unique `(school_id, from_session_year) WHERE state <> 'DRAFT'` — one live run per session per school.
**Indexes:** `(school_id, from_session_year)` → tenant-scoped run lookup.

#### `migration_run_items` (model `MigrationRunItem`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `run_id` | `uuid` | no | — | FK → `migration_runs`; tenant via run |
| `enrollment_id` | `uuid` | no | — | FK → `enrollments` |
| `user_id` | `uuid` | no | — | Denormalized for reporting |
| `action` | `text` | no | — | `PROMOTED` / `GRADUATED` / `RETAINED` / `ERROR` |
| `from_section_id` | `uuid` | no | — | FK → `sections` |
| `to_section_id` | `uuid` | yes | — | Null for GRADUATED/RETAINED |
| `detail` | `text` | yes | — | Error reason, e.g. missing target section |
| `applied_at` | `timestamptz` | yes | — | Batch checkpoint for resume (`ORG-BR-008`) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** unique `(run_id, enrollment_id)`; FKs; `CHECK` on `action`.
**Indexes:** `(run_id, applied_at)` → resume scan; `(run_id, action)` → summary counts.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261002090001_create_cities` | ✅ |
| 2 | `20261002090002_create_schools` | ✅ |
| 3 | `20261002090003_create_sections` | ✅ |
| 4 | `20261002090004_create_enrollments` | ✅ |
| 5 | `20261002090005_create_fcm_topic_bindings` | ✅ |
| 6 | `20261002090006_create_migration_runs_and_items` | ✅ |
| 7 | `20261002090007_add_identity_hierarchy_fks` — adds FKs from 03's `users.school_id`, `verification_requests.school_id`, `verification_requests.requested_section_id`, `guardian_links.school_id` to `schools`/`sections` (03 is migrated before 04 exists) | ✅ (drop constraints) |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| Cities: Dhaka (ঢাকা), Chattogram (চট্টগ্রাম) — `is_launch_city=true`, ACTIVE | Active seed (real geographic names only) | README module 04 default (OQ-1) |
| "Demo High School" (Dhaka) + Super-Admin-provisioned demo tenant | `DRAFT` — clearly fictional, marked as demo | `prompt.txt` §12 / `ORG-BR-012` |
| Demo sections: Class 6 A/B, session 2026 + demo enrollments | `DRAFT` — fictional | `prd.md` §5.1; never shown as a real partner |

---

## 2. Server Contracts

All routes live under `/api/v1`; errors use the shared RFC-7807 envelope.

### `GET /api/v1/hierarchy/cities` · `GET /api/v1/hierarchy/cities/{cityId}/schools` · `GET /api/v1/hierarchy/schools/{schoolId}/sections` (public picker reads)

| | |
| --- | --- |
| **Auth** | Public — no auth middleware |
| **Input** | query `launch` (bool, default from config `HIERARCHY_LAUNCH_ONLY=true`, cities only); path uuids; `sessionYear` (sections, default current); contract-generated validators |
| **Result** | `{ "data": [...] }` — ACTIVE nodes only, bn + en names, launch cities first: `[ { id, nameBn, nameEn, isLaunchCity } ]` → `[ { id, nameBn, nameEn } ]` → `[ { id, classLevel, name, sessionYear } ]` |
| **Errors** | `NOT_FOUND` · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class (public read, Redis token bucket) |
| **Audit** | none (read-only) |
| **Stories** | `ORG-US-003`, `ORG-US-009` |

### `POST /api/v1/admin/cities`

| | |
| --- | --- |
| **Auth** | authenticate → role claim `SUPER_ADMIN` |
| **Input** | `{ nameBn, nameEn, isLaunchCity? }`; validator |
| **Result** | `{ "data": { id, … } }` — 201 |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `CONFLICT` (duplicate name) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | yes — city created |
| **Stories** | `ORG-US-009` |

### `POST /api/v1/admin/schools` · `PATCH /api/v1/admin/schools/{schoolId}`

| | |
| --- | --- |
| **Auth** | authenticate → role claim `SUPER_ADMIN` |
| **Input** | POST `{ cityId, nameBn, nameEn, admin: { phone, name } }` · PATCH `{ nameBn?, nameEn?, status? }` (rename / archive / re-open, soft only per `ORG-BR-004`) |
| **Result** | POST `{ "data": { school: {…}, adminUserId } }` — 201; one tx: school + `school-{id}` topic binding + pre-verified School Admin (module 03) · PATCH `{ "data": { school } }` |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `CONFLICT` · `NOT_FOUND` (city/school) · `INTERNAL` |
| **Rate limit** | 5/hour per Super Admin (POST) · default class (PATCH) |
| **Audit** | yes — tenant provisioned / renamed / archived |
| **Stories** | `ORG-US-001` |

### `POST /api/v1/school/sections` · `PATCH /api/v1/school/sections/{sectionId}`

| | |
| --- | --- |
| **Auth** | authenticate → role claim `SCHOOL_ADMIN` → tenant-scope (school from claim) |
| **Input** | POST `{ classLevel, name, sessionYear }` · PATCH `{ name?, status? }` — archive blocked while ACTIVE enrollments exist (except migration) |
| **Result** | `{ "data": { section } }` — 201 on POST; `section-{id}` topic binding in the same tx |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND`/`TENANT_MISMATCH` (other school) · `CONFLICT` (`ORG-BR-002`) · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | yes — archive (PATCH) |
| **Stories** | `ORG-US-002`, `ORG-US-005` |

### `POST /api/v1/school/sections/{sectionId}/teachers`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope |
| **Input** | `{ userId, role: TEACHER \| CLASS_TEACHER }` |
| **Result** | `{ "data": { enrollment } }` — 201; module 05 informed for official-group ownership |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND`/`TENANT_MISMATCH` · `NOT_VERIFIED` · `CONFLICT` (`ORG-BR-007`) · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | yes — class-teacher assignment |
| **Stories** | `ORG-US-006` |

### `GET /api/v1/school/enrollments`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` or `TEACHER` → tenant-scope; teachers limited to their assigned sections |
| **Input** | query `sectionId?`, `role?`, `sessionYear?`, `status?`, `page`, `pageSize` |
| **Result** | `{ "data": [ { id, userId, userName, role, sectionId, sessionYear, status } ], "page": {…} }` — paged, max 100 |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none (read-only) |
| **Stories** | `ORG-US-005` (scope), `ORG-US-007` (migration pre-check) |

### `POST /api/v1/school/migrations` (dry-run=true|false) · `GET /api/v1/school/migrations/{runId}` · `POST /api/v1/school/migrations/{runId}/commit`

| | |
| --- | --- |
| **Auth** | authenticate → `SCHOOL_ADMIN` → tenant-scope (run lookup joined to the caller's school) |
| **Input** | POST create `{ fromSessionYear, dryRun }` — `dryRun=true` → DRAFT run, `false` → PREVIEWED run (requires zero ERROR items) · GET path `runId` · POST commit takes no body — run must be PREVIEWED with zero ERROR items |
| **Result** | create/commit `{ "data": { run, items: [ { enrollmentId, action, fromSectionId, toSectionId, detail? } ] } }` — 201, nothing applied on create; commit returns the run COMMITTING→COMMITTED via the `jobs` worker · GET returns run + items with live counters |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND`/`TENANT_MISMATCH` · `VALIDATION_FAILED` · `CONFLICT` (open run exists / wrong state / ERROR items / already committed) · `INTERNAL` |
| **Rate limit** | create + commit 5/hour per school · GET default class |
| **Audit** | yes — preview created, migration committed |
| **Stories** | `ORG-US-007`, `ORG-US-008` |

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web code. Module 07 (`command-center-web`) consumes every endpoint above
through the generated `openapi-fetch` client — never the database directly. Same auth + zod-validated
input (mirrors the `validation.*` keys) + result rows apply there.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `ORG-BE-001` | `CreateCity` / `ArchiveCity` / `ListCities` | Super Admin (mutations); unique bn/en names; launch-flag filter; ACTIVE only in public reads | `hierarchy:cities` | yes |
| `ORG-BE-002` | `CreateSchool` | Super Admin; city ACTIVE; unique per city; tx: school + `school-{id}` binding + pre-verified School Admin via 03 | `hierarchy:cities`, `hierarchy:school:{id}` | yes |
| `ORG-BE-003` | `UpdateSchool` / `ListSchoolsByCity` | Super Admin (mutations); rename/archive/re-open (`ORG-BR-004`); public reads ACTIVE-only | `hierarchy:cities`, `hierarchy:school:{id}` | yes |
| `ORG-BE-004` | `CreateSection` / `UpdateSection` / `ListSectionsBySchool` | School Admin claim; unique per class+session (`ORG-BR-002`); archive blocked while ACTIVE enrollments (except migration); `section-{id}` binding in tx | `hierarchy:school:{id}` | yes (archive) |
| `ORG-BE-005` | `AssignClassTeacher` | user VERIFIED + same school claim; one CLASS_TEACHER (`ORG-BR-007`); calls 05 for group ownership | — | yes |
| `ORG-BE-006` | `ListEnrollments` | claim-scoped paging; teacher → own sections only | — | no |
| `ORG-BE-007` | `OnUserVerified` | 03 reports VERIFIED (`ORG-BR-005`); idempotent (`ORG-BR-006`); tx: enrollment + bindings; calls 05 join; back-fill job on 05 failure | — | no |
| `ORG-BE-008` | `ResolveUserNodes` / `GetSection` | active enrollments → city/school/sections + topic names (for 05/06/09/13); public section identity DTO | — | no |
| `ORG-BE-009` | `CreateEnrollments(batch, source)` | module 14 ingestion; per-row validation; idempotent per (user, section, role, session) | `hierarchy:school:{id}` | no |
| `ORG-BE-010` | `PreviewMigration(dryRun)` | promotion engine (`ORG-BR-009`); zero ERROR required for PREVIEWED; `CONFLICT` if open run | — | yes |
| `ORG-BE-011` | `CommitMigration` / `GetMigrationRun` | PREVIEWED + zero ERROR; enqueue `migration.run` job; run reads tenant-scoped | `hierarchy:school:{id}` | yes |
| `ORG-BE-012` | Promotion engine (pure function) | class → action mapping incl. graduation at 10/12 and missing-target ERROR; unit-testable constant config | — | no |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `ORG-BE-013` | `InsertCity` / `UpdateCityStatus` / `ListCities` | filtered by `status` + `is_launch_city` | `(status, is_launch_city)` |
| `ORG-BE-014` | `InsertSchool` / `GetSchool` / `UpdateSchool` / `ListSchoolsByCity` | `WHERE city_id=$1 AND status='ACTIVE'` | `(city_id, status)` |
| `ORG-BE-015` | `InsertSection` / `GetSection` / `ListSectionsBySchool` / `UpdateSectionStatus` | `WHERE school_id=$1 AND session_year=$2 AND status='ACTIVE'` | `(school_id, session_year, status)` |
| `ORG-BE-016` | `InsertEnrollment` (ON CONFLICT DO NOTHING + RETURN) | idempotent on `(user_id, section_id, role, session_year)` | unique index |
| `ORG-BE-017` | `GetActiveStudentEnrollment` | `WHERE user_id=$1 AND session_year=$2 AND role='STUDENT' AND status='ACTIVE'` | `(user_id, session_year)` |
| `ORG-BE-018` | `ListEnrollments` / `ListEnrollmentsByTeacher` | tenant-forced `WHERE school_id=$claim` + filters + paging | `(section_id, role, status)` |
| `ORG-BE-019` | `UpsertTopicBinding` / `GetTopicBindingsByNodes` | unique `(node_type, node_id)`; lookup by `topic_name` | unique indexes |
| `ORG-BE-020` | `InsertMigrationRun` / `GetRun` / `UpdateRunState` | `WHERE school_id=$claim AND from_session_year=$1` | `(school_id, from_session_year)` |
| `ORG-BE-021` | `BulkInsertRunItems` / `MarkRunItemsApplied` / `ListUnappliedItems` | `WHERE run_id=$1 AND applied_at IS NULL`; batch insert `ON CONFLICT DO NOTHING` | `(run_id, applied_at)` |
| `ORG-BE-022` | `SelectPromotionCandidates` | `WHERE school_id=$claim AND session_year=$from AND role='STUDENT' AND status='ACTIVE'` | `(school_id, session_year, status)` |
| `ORG-BE-023` | `ApplyMigrationItem` / `CountRunItemsByAction` | tx: end old enrollment + insert new + refresh bindings; `GROUP BY action` per run | unique partial index · `(run_id, action)` |

Every query is tenant-scoped at the repository layer (`ORG-BR-001`, `ORG-INV-006`) — no method
accepts a caller-supplied `school_id`.

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `ORG-BE-024` | `migration.run` worker | `POST …/commit` enqueues via module 01 `jobs` | Yes — batch checkpoints (`applied_at`), unique `(run_id, enrollment_id)` | Retry with backoff; resumes from first unapplied item; alert + run stays PREVIEWED after N failures |
| `ORG-BE-025` | `hierarchy.backfill` | Enqueued when the 05 join (or topic refresh) fails inside `OnUserVerified` | Yes — idempotent joins + unique enrollment index | ×5 backoff → dead-letter + admin report; user remains VERIFIED throughout |

Apply is transactional per school in 500-item batches; each batch commits its checkpoints, so a
crash between batches is resumed, never re-applied (`ORG-BR-008`).

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ORG-UT-001` | Promotion engine mapping (each class level → PROMOTED/GRADUATED/RETAINED/ERROR) | Unit | `ORG-BR-009` incl. graduation at 10/12 and missing-target ERROR |
| `ORG-UT-002` | Topic name determinism + binding uniqueness; launch-city filter (config on/off) | Unit | `ORG-BR-011`; two-list config (02 §5) |
| `ORG-UT-003` | Run state guard: DRAFT→PREVIEWED→COMMITTED; illegal transitions rejected | Unit | `ORG-INV-005` |
| `ORG-UT-004` | `OnUserVerified` idempotency with fake 03/05/06 | Unit | `ORG-BR-006` |
| `ORG-UT-005` | Section/migration payload validation → `validation.*` keys | Unit | §6 of `01-user-stories.md` |
| `ORG-IT-001` | `OnUserVerified` creates enrollment + group joins + topic bindings exactly once under a doubled event | Integration (testcontainers Postgres) | `ORG-US-004`, `ORG-BR-006` |
| `ORG-IT-002` | Cross-tenant section read/write denied (School Admin A → school B: sections, enrollments, migrations) | Integration | `ORG-US-005`, `ORG-BR-001` |
| `ORG-IT-003` | Migration dry-run → preview → commit applies PROMOTED/GRADUATED/RETAINED and blocks commit on ERROR items | Integration | `ORG-US-007`, `ORG-US-008`, `ORG-BR-008` |
| `ORG-IT-004` | Migration commit idempotent on retry (crash between batches) | Integration | `ORG-BR-008`, `ORG-INV-005` |
| `ORG-IT-005` | Public pickers hide ARCHIVED nodes and respect the launch filter | Integration | `ORG-BR-010` |
| `ORG-IT-006` | Auth chain on every protected route: unauthenticated → `UNAUTHENTICATED`; wrong role → `FORBIDDEN`; bad input → `VALIDATION_FAILED` | Integration | 02 §6 security |
| `ORG-IT-007` | 05 outage during verify → enrollment persists, back-fill job completes membership on recovery | Integration | `ORG-US-004` failure path |

Always included: unauthenticated call denied for every protected entry point; validation rejects bad
input; cross-tenant read/write returns `TENANT_MISMATCH`/404 for every tenant-scoped table; public
reads never return drafts, archived nodes, or personal data.

## 7. Task Checklist

### Schema

- [ ] Migrations 1–6 (§1.2) — prerequisite for every `ORG-BE-*` task below — ____

### Repository · Service · Entry points · Seed · Tests

- [ ] `ORG-BE-013`–`015` sqlc: cities, schools, sections — ____
- [ ] `ORG-BE-016`–`019` sqlc: enrollments + topic bindings — ____
- [ ] `ORG-BE-020`–`023` sqlc: migration runs + items — ____
- [ ] `ORG-BE-001`–`003` services: city + school management — ____
- [ ] `ORG-BE-004`–`006` services: sections, teacher assignment, roster — ____
- [ ] `ORG-BE-007`, `ORG-BE-012` services: `OnUserVerified` seam + promotion engine — ____
- [ ] `ORG-BE-008`–`009` services: exports for 05/06/09/13/14 — ____
- [ ] `ORG-BE-010`–`011` services: migration preview/commit/get — ____
- [ ] Entry points: 13 endpoints per §2 (handlers over `ORG-BE-001`–`011`) + OpenAPI spec entries + contract regen — ____
- [ ] `ORG-BE-024`–`025` jobs: `migration.run` + `hierarchy.backfill` workers · seed per §1.3 (`ORG-BR-012`) — ____
- [ ] `ORG-BE-026` migration `20261002090007_add_identity_hierarchy_fks` + `sections.stream` · `ORG-BE-027` count exports `PlatformCounts`/`SchoolCounts`/`AudienceCount` (aggregate-only, small-count suppression) — ____
- [ ] Tests: `ORG-UT-001`–`005` · `ORG-IT-001`–`007` green in CI — ____
