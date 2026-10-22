# Organization Hierarchy — User Stories

**Module:** `04-organization-hierarchy`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Provides the City → School → Section hierarchy every other module hangs from (`brd.md` §5 BR-01,
`prd.md` §5.1): school/tenant onboarding, class/section management, the public picker data behind
registration, auto-grouping of verified users into section groups and FCM topics, and the idempotent
year-end migration that promotes or graduates students.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Reads public picker data during registration (module 03 screens); cannot participate until verified |
| Student | Is auto-grouped into their section/school/city context on verification; is promoted or graduated by year-end migration |
| Guardian | Joins the student's section context (role GUARDIAN enrollment) and inherits its school/section topics |
| Teacher | Assigned to sections as TEACHER or CLASS_TEACHER; the class teacher owns the official section group (module 05) |
| School Admin | Governs only their own school (tenant): sections, enrollment roster, teacher assignment, year-end migration |
| Super Admin | Onboards tenant schools + first School Admin, manages the city list, archives schools |
| Partner / EdTech brand | No direct access — reaches hierarchy segments only through module 13 campaigns |
| System (jobs, webhooks) | Runs migration commits via module 01 `jobs`, back-fills group joins/topic bindings, receives `OnUserVerified` calls from module 03 |

## 3. Scope

**In scope**

- Data model + migrations: `cities`, `schools`, `sections`, `enrollments`, `fcm_topic_bindings`, `migration_runs`, `migration_run_items`.
- Public picker read endpoints (cities → schools → sections) consumed by module 03 onboarding screens.
- Super Admin school onboarding (tenant + pre-verified first School Admin), city management, school archiving (soft only).
- School Admin sections, class-teacher assignment, enrollment roster read API (`GET /school/enrollments`).
- Auto-grouping seam: `hierarchy.OnUserVerified(userId)` → enrollment → module 05 group join → FCM topic bindings.
- Year-end migration: dry-run preview → commit, job-driven, transactional per school, idempotent, audited (BR-01).
- bn/en i18n keys in each app's `src/i18n` (`hierarchy.*`, `validation.*`).

**Out of scope** (explicit — prevents scope drift)

- Group chat internals — module 05 (04 only calls its join/archive exports).
- Device tokens and push sending — module 06 (04 only maintains topic bindings).
- CSV/Excel roster parsing — modules 14/07 (14 creates enrollments via 04's `CreateEnrollments`).
- Campaign targeting logic (13) and analytics aggregation (09) — read-only consumers via exports.
- School self-signup via the landing funnel (Phase 3 consideration); promotion-rule changes beyond the recorded default — `TODO: Confirm` (OQ-2).

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 03 identity-access | Users, role claims, verified status, registration-time hierarchy selection; pre-verified account bootstrap; calls `OnUserVerified` |
| 01 foundations | `jobs` table + worker, RFC-7807 error envelope, config parsing, audit-log sink, migration tooling |
| 05 / 06 (interface-first) | 05: `chat.JoinSectionGroups` / `chat.ArchiveSectionGroups` exports · 06: reads `fcm_topic_bindings` (no calls from 04 to 06) |
| web + app (per app) | `hierarchy.*` / `validation.*` bn + en message catalogs |

---

## 4. User Stories

### `ORG-US-001` — Super Admin onboards a school (tenant provisioning)

**Priority:** P0 · **Traces:** BR-01 (`brd.md` §5) / PRD §5.1 · **Depends on:** 03

**Story** — As a **Super Admin**, I want **to create a school tenant under a city with its first pre-verified School Admin**, so that **the school can define its hierarchy and onboard users immediately**.

**Acceptance criteria**

- **Given** a valid city and school profile, **when** `POST /api/v1/admin/schools` is submitted, **then** the school is created ACTIVE with its `school-{id}` topic binding in the same transaction, and an audit entry records it.
- **Given** the admin phone/name in the request, **when** provisioning completes, **then** a pre-verified School Admin account (module 03) exists and can sign in.
- **Given** a duplicate school name in the city, or a non-Super-Admin caller, **when** submitted, **then** `CONFLICT` / `FORBIDDEN` — nothing created.

### `ORG-US-002` — School Admin sets up classes and sections

**Priority:** P0 · **Traces:** BR-01 / PRD §5.1 · **Depends on:** `ORG-US-001`

**Story** — As a **School Admin**, I want **to define class levels and section names (Class 6 → A/B) for my school's session year**, so that **students can pick the exact section during registration and land in the right group**.

**Acceptance criteria**

- **Given** my own school and session 2026, **when** I create section (classLevel 6, name "A") via `POST /api/v1/school/sections`, **then** it is ACTIVE and visible on the public picker for that school.
- **Given** a duplicate name for the same school + class + session, **when** submitted, **then** `CONFLICT` (`ORG-BR-002`).
- **Given** another school's resources addressed, **when** I post, **then** `TENANT_MISMATCH` — nothing created or leaked.

### `ORG-US-003` — Registration reads hierarchy picker data (public)

**Priority:** P0 · **Traces:** PRD §5.1 strict onboarding · **Depends on:** — (picker screens live in module 03; the data contract is this module's)

**Story** — As an **unauthenticated new user registering through module 03**, I want **to browse City → School → Section from public endpoints**, so that **I can state exactly where I belong before verification**.

**Acceptance criteria**

- **Given** the platform at launch, **when** `GET /api/v1/hierarchy/cities` is called, **then** only ACTIVE cities return (launch list first: Dhaka, Chattogram), each with bn + en names.
- **Given** a city or school id, **when** the schools/sections picker endpoints are called, **then** only ACTIVE nodes return — names only, no user counts or admin data (`ORG-BR-010`).
- **Given** repeated picker traffic, **when** the same city/school is read, **then** responses are served from cache tagged `hierarchy:*`.

### `ORG-US-004` — Verified student is auto-grouped (the BR-01 seam)

**Priority:** P0 · **Traces:** BR-01 / PRD §5.1 auto-grouping · **Depends on:** `ORG-US-002`, module 03 verify event

**Story** — As a **verified student**, I want **to be placed automatically in my section's official group and its city/school/section notification topics**, so that **I receive my class and school notices without anyone adding me manually**.

**Acceptance criteria**

- **Given** module 03 verifies a student whose registration selected section S, **when** `hierarchy.OnUserVerified(userId)` runs, **then** an ACTIVE STUDENT enrollment for the current session is created for S in one transaction.
- **Given** the enrollment is committed, **when** the same call proceeds, **then** module 05 `chat.JoinSectionGroups(userID, enrollment)` runs and `fcm_topic_bindings` exist for `section-{id}`, `school-{id}`, `city-{id}` (module 06 subscribes devices).
- **Given** the verify event is delivered twice, **when** the call runs again, **then** the existing enrollment is returned — no duplicate groups, joins or bindings (`ORG-BR-006`).
- **Given** module 05 is down, **when** the call runs, **then** the user stays VERIFIED with the enrollment persisted and the join queued to `jobs` and back-filled.

### `ORG-US-005` — Cross-tenant access is denied

**Priority:** P0 · **Traces:** `brd.md` §6 multi-tenant privacy · **Depends on:** `ORG-US-001`

**Story** — As a **School Admin of school A**, I want **to be unable to read or modify school B's sections, enrollments or migrations**, so that **one school's data is never visible to another**.

**Acceptance criteria**

- **Given** a School Admin carrying school A's tenant claim, **when** they call any `/api/v1/school/*` route addressed at school B's resources, **then** they get `TENANT_MISMATCH` (404 body) and nothing leaks or changes.
- **Given** a read with a forged query (`GET /api/v1/school/enrollments?schoolId=B`), **when** executed, **then** the tenant scope filters to school A regardless of the parameter (proven by `ORG-IT-002`).

### `ORG-US-006` — Class teacher is assigned to a section

**Priority:** P0 · **Traces:** BR-01 / PRD §5.1 (group managed by the Class Teacher) · **Depends on:** `ORG-US-002`, module 03 verified teacher

**Story** — As a **School Admin**, I want **to assign a verified teacher to a section as TEACHER or CLASS_TEACHER**, so that **the class teacher owns the official section group and its notices**.

**Acceptance criteria**

- **Given** a VERIFIED teacher of my school, **when** `POST /api/v1/school/sections/{id}/teachers` is called, **then** an enrollment (role CLASS_TEACHER, current session) is created and module 05 is informed for official-group ownership.
- **Given** the section already has an active CLASS_TEACHER, **when** a second assignment is attempted, **then** `CONFLICT` (`ORG-BR-007`).
- **Given** a PENDING user, **when** assigned, **then** `NOT_VERIFIED` with guidance to complete verification.

### `ORG-US-007` — Year-end migration dry-run preview

**Priority:** P0 · **Traces:** BR-01 (year-end migration) · **Depends on:** `ORG-US-002`, `ORG-US-004`

**Story** — As a **School Admin**, I want **a dry-run preview listing every student as PROMOTED, GRADUATED, RETAINED or ERROR**, so that **I can fix missing target sections (auditing the roster via `GET /school/enrollments`) before anything changes**.

**Acceptance criteria**

- **Given** my school's current session 2026, **when** `POST /api/v1/school/migrations` with `dryRun=true` is called, **then** a DRAFT run with per-student items is created and nothing else changes.
- **Given** a Class 9 student in section A, **when** the preview is computed, **then** the item is PROMOTED to the (class 10, "A") section of the same school for session 2027; Class 10/12 students are GRADUATED (ALUMNI).
- **Given** a class whose target section does not exist, **when** the preview is computed, **then** the item is ERROR naming the missing section, and commit stays blocked (`ORG-BR-008`; default rules `ORG-BR-009`, `TODO: Confirm` OQ-2).

### `ORG-US-008` — Year-end migration commit

**Priority:** P0 · **Traces:** BR-01 · **Depends on:** `ORG-US-007`

**Story** — As a **School Admin**, I want **to commit the reviewed migration so students move to their new session groups safely and verifiably**, so that **the new academic year starts with everyone in the right place**.

**Acceptance criteria**

- **Given** a PREVIEWED run with zero ERROR items, **when** `POST /api/v1/school/migrations/{id}/commit` is called, **then** the run is queued to the module 01 `jobs` worker, which applies items in transactional batches, archives the old session's section groups via module 05, and marks the run COMMITTED with an audit entry.
- **Given** the worker crashes mid-apply, **when** the job retries, **then** it resumes from the first unapplied item — applied items are skipped (idempotent, `ORG-BR-008`).
- **Given** a run already COMMITTED, **when** commit is called again, **then** `CONFLICT`; the run is unchanged.

### `ORG-US-009` — Super Admin adds a city

**Priority:** P1 · **Traces:** README module 04 default (launch cities) · **Depends on:** —

**Story** — As a **Super Admin**, I want **to add a new city to the platform**, so that **schools outside the launch cities can be onboarded as Kushol expands**.

**Acceptance criteria**

- **Given** a unique bn/en city name, **when** `POST /api/v1/admin/cities` is called, **then** the city is created (launch flag false by default) and the `hierarchy:cities` cache tag is invalidated.
- **Given** a duplicate city name, **when** submitted, **then** `CONFLICT`.

### `ORG-US-010` — Hierarchy serves ad targeting and analytics

**Priority:** P1 · **Traces:** BR-05 (`brd.md` §5) · **Depends on:** `ORG-US-004`

**Story** — As a **platform integrator (modules 13 ads and 09 analytics)**, I want **to resolve a user's city/school/section nodes and a section's identity through exported functions**, so that **campaigns and Pain Point Matrices segment by the exact hierarchy without duplicating the model**.

**Acceptance criteria**

- **Given** a verified user, **when** module 13 calls `hierarchy.ResolveUserNodes(userId)`, **then** it receives city, school, active section ids and their topic names (e.g. "Class 12 Science students in Chattogram").
- **Given** a section id, **when** module 09 calls `hierarchy.GetSection(id)`, **then** the section identity (class level, name, session, school) is returned.
- **Given** any targeting use, **when** segments are computed, **then** only aggregate counts cross the boundary — no individual-level exposure of minors (`brd.md` §6).

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `ORG-BR-001` | Tenant isolation: every school-scoped query/mutation is filtered by the caller's `schoolId` claim; other schools' rows return `TENANT_MISMATCH`/404 | Service + repository (both) |
| `ORG-BR-002` | Section names are unique per (school, class_level, session_year) | DB unique index + service |
| `ORG-BR-003` | A user has at most one ACTIVE STUDENT enrollment per session_year | DB partial unique index + service |
| `ORG-BR-004` | Schools, sections and enrollments are never hard-deleted — only `ARCHIVED`/`ENDED`/`ALUMNI` status transitions; archived schools leave the pickers but keep history readable | Repository (no DELETE statements) |
| `ORG-BR-005` | `OnUserVerified` creates enrollments only for users module 03 reports as VERIFIED, using the hierarchy selection captured at registration | Service |
| `ORG-BR-006` | Auto-grouping is idempotent: repeated verify events return the existing enrollment and re-issue no group joins or topic bindings | DB unique index + service |
| `ORG-BR-007` | Exactly one active CLASS_TEACHER per section; a second assignment is `CONFLICT` until the current one is ended | Service |
| `ORG-BR-008` | Migration commit requires a PREVIEWED run with zero ERROR items; apply is job-driven, transactional per school in batches, idempotent per item, and audited | Service + job worker |
| `ORG-BR-009` | Default promotion: every class promotes +1 within the same school; Class 10 and 12 graduate to ALUMNI. `TODO: Confirm` exact promotion rules with Rahul | Service (config constant) |
| `ORG-BR-010` | Public picker endpoints expose only ACTIVE nodes and never personal data or counts | Service |
| `ORG-BR-011` | Every hierarchy node has exactly one deterministic FCM topic binding (`city-{id}` / `school-{id}` / `section-{id}`) created in the node's transaction | DB unique index + service |
| `ORG-BR-012` | Seed/demo hierarchy content is clearly fictional ("Demo High School"), never presented as a real partner; real city names are geographic facts only (`prompt.txt` §12) | Seed review + publishing guard |

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| city `nameBn` / `nameEn` | required, 1–100 chars; `nameEn` unique (case-insensitive) | `validation.required` · `hierarchy.city.name_length` · `hierarchy.city.name_duplicate` |
| school `cityId` | must reference an ACTIVE city | `hierarchy.school.city_required` |
| school `nameBn` / `nameEn` | required, 2–150 chars; pair unique per city | `hierarchy.school.name_length` · `hierarchy.school.name_duplicate` |
| section `classLevel` | integer 1–12 | `hierarchy.section.class_range` |
| section `name` | required, 1–8 chars, unique per school+class+session | `hierarchy.section.name_invalid` · `hierarchy.section.name_duplicate` |
| section `sessionYear` | current or next calendar year | `hierarchy.section.session_invalid` |
| teacher `userId` | must be VERIFIED and carry the caller's school claim | `hierarchy.teacher_not_verified` |
| migration `fromSessionYear` / `dryRun` | session equals the school's current active session; `dryRun` boolean required | `hierarchy.migration_session_invalid` · `validation.required` |
| list `page` / `pageSize` | page ≥ 1; 1 ≤ pageSize ≤ 100 | `validation.page_invalid` |

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any `/admin/*` or `/school/*` route | `UNAUTHENTICATED`, no side effect |
| 2 | School Admin of school A reads/writes school B's sections, enrollments or migrations | `TENANT_MISMATCH` (404 body), nothing leaked (`ORG-US-005`) |
| 3 | Teacher assignment for a PENDING user | `NOT_VERIFIED` + how to get verified |
| 4 | Duplicate `OnUserVerified` delivery (retry or race) | Second call returns the existing enrollment; no duplicate groups/topics |
| 5 | Commit on a DRAFT, already-COMMITTED, or ERROR-carrying run | `CONFLICT`; run state unchanged |
| 6 | Target section missing for a promotion at preview | Item marked ERROR naming the missing section; commit blocked until created |
| 7 | City archived while schools still exist | City hidden from pickers; existing schools/enrollments keep working; re-open restores |
| 8 | Module 05 unavailable during `OnUserVerified` | User stays VERIFIED, enrollment persisted; group join queued to `jobs` and back-filled |
| 9 | Migration worker crash mid-apply | Batch checkpoints (`applied_at`); retry resumes from the first unapplied item |

## 8. Reporting Needs

- Schools per city (ACTIVE/ARCHIVED split), sections per school, active enrollments per section — Super Admin and School Admin dashboards (module 07).
- Migration run summary per school (PROMOTED / GRADUATED / RETAINED / ERROR counts) — 07 migration screens and audit.
- Aggregate segment sizes (city → class level) for ad-target reach estimates — module 13, counts only, no PII.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Which cities are live at launch? | Rahul | Open | Dhaka + Chattogram only; new cities added by Super Admin (`ORG-US-009`) |
| 2 | Exact year-end promotion rules (graduation classes, RETAINED handling, repeating students, section re-mapping when names differ)? | Rahul | Open — `TODO: Confirm` | Promote +1 within the same school; Class 10 and 12 → ALUMNI; archive old section groups (`ORG-BR-009`) |
| 3 | School onboarding flow at launch — Super Admin provisioned only, or landing-funnel self-signup? | Rahul | Open | Super Admin creates the tenant + first pre-verified School Admin; School Admin then defines sections |
| 4 | How are guardians modeled in enrollments (own rows vs links to the student)? | Rahul | Open | Guardian gets a role GUARDIAN enrollment in the student's section, from the module 03 student–guardian link |
