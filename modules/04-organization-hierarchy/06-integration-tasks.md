# Organization Hierarchy — Integration Tasks

**Module:** `04-organization-hierarchy` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

`02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
**contract**. No cross-module call, cache key or external dependency may exist in code unless it is
declared here (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `03 identity-access` | they call us | exported Go service function `hierarchy.OnUserVerified` at their verify handler | degraded — user stays VERIFIED; membership/topic back-fill via `jobs` |
| I-2 | `05 communication-engine` | we call them | exported Go service functions `chat.JoinSectionGroups` / `chat.ArchiveSectionGroups` | degraded — back-fill job; never blocks verification |
| I-3 | `06 notifications` | they call us | read our `fcm_topic_bindings` rows (we never call 06) | degraded — device subscriptions happen late, bindings are already durable |
| I-4 | `14 lms-erp-sync` | they call us | exported `hierarchy.CreateEnrollments(batch, source)` from roster ingestion | fatal per row — row-level error reported back to 14's ingestion report |
| I-5 | `01 foundations` | we call them | `jobs.Enqueue` + shared worker for `migration.run` / `hierarchy.backfill` | degraded — commit returns, apply retries via job |
| I-6 | `07 command-center-web`, `09 teacher-analytics`, `13 b2b-ads-events` | they call us | read-only exports `hierarchy.ResolveUserNodes` / `GetSection` / `PlatformCounts` / `SchoolCounts` / `AudienceCount` | degraded — empty segments; never fatal to those modules |
| I-7 | FCM (external) | indirect only | topic naming contract `city-{id}` / `school-{id}` / `section-{id}`; all FCM SDK calls live in 06 | degraded, never fatal — 04 holds no FCM credentials |
| I-8 | `03 identity-access` (owner decision 2026-10-02, ADR-2) | they call us | 03's school-request approve handler calls `hierarchy.CreateSchool` inline — approving a public school-request provisions the institution (school + `school-{id}` binding + audit in one tx); 03 then provisions the request's POC as pre-verified School Admin via its own `users.CreateProvisionedAdmin` | fatal for the approval click — 03 surfaces the error; the request stays PENDING and can be retried |

## 2. Exported Contract

```text
hierarchy.OnUserVerified(userId uuid) (EnrollmentDTO, error)
hierarchy.CreateSchool(ctx, actor Principal, in CreateSchoolInput{RequestID?, CityID, Type, NameBn, NameEn, Address?, Admin?}) (SchoolDTO, AdminProvision?, error)
hierarchy.ResolveUserNodes(userId uuid) (UserNodes{CityID, SchoolID, SectionIDs, TopicNames}, error)
hierarchy.GetSection(sectionID uuid) (SectionDTO, error)
hierarchy.CreateEnrollments(batch []EnrollmentInput, source string) ([]EnrollmentResult, error)
hierarchy.PreviewMigration(schoolID uuid, fromSessionYear int, dryRun bool) (MigrationRunDTO, error)
hierarchy.CommitMigration(runID uuid) (MigrationRunDTO, error)
hierarchy.PlatformCounts(ctx) (PlatformCountsDTO{Cities, Schools, ActiveSections, VerifiedUsersByRole}, error)
hierarchy.SchoolCounts(ctx, schoolID uuid) (SchoolCountsDTO{ActiveSections, EnrollmentsByRole, SessionYear}, error)
hierarchy.AudienceCount(ctx, filter AudienceFilter{CityIDs, SchoolIDs, ClassLevels, Streams, Roles}) (int, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `OnUserVerified(userId)` | 03 verify handler | the (idempotent) enrollment created from the registration-time section choice | `NOT_FOUND` (no selection), `VALIDATION_FAILED` | The BR-01 seam (02 §2): tx enrollment + bindings → 05 join → back-fill job on failure; safe to call repeatedly |
| `CreateSchool(ctx, actor, in)` | 03 school-request approval (I-8), 07 tenant wizard via `POST /admin/schools` | school DTO (+ provisioned admin id when `Admin` supplied) | `CONFLICT` (duplicate name / decided request race), `NOT_FOUND` (city), `FORBIDDEN`, `VALIDATION_FAILED` | Super-Admin gated; one tx: school + `school-{id}` binding + audit (`school.created` carries `requestId` for traceability — no schema change to 03) |
| `ResolveUserNodes(userId)` | 05 (rooms), 06 (topics), 09, 13 | city/school/active-section ids + topic names | `NOT_FOUND` | Read-only; powers rooms, subscriptions, analytics and ad segments |
| `GetSection(sectionID)` | 05, 09, 13 | section identity (class level, name, session, school) | `NOT_FOUND` | Cached read |
| `CreateEnrollments(batch, source)` | 14 roster ingestion | per-row result (created / exists / error) | `VALIDATION_FAILED` (whole-batch shape) | Batch, idempotent per (user, section, role, session); rows never partially silently dropped |
| `PreviewMigration(schoolID, from, dryRun)` | 07 migration wizard | run + item list (PROMOTED/GRADUATED/RETAINED/ERROR) | `VALIDATION_FAILED`, `CONFLICT` | `dryRun=true` → DRAFT, `false` → PREVIEWED; zero-ERROR required to reach PREVIEWED |
| `CommitMigration(runID)` | 07 migration wizard | run in COMMITTING→COMMITTED | `CONFLICT`, `NOT_FOUND` | Enqueues `migration.run`; tenant-claims checked inside |
| `PlatformCounts()` | 07 Super Admin dashboard | platform totals | `FORBIDDEN` (non super_admin) | Aggregate only; Redis 5-min TTL |
| `SchoolCounts(schoolID)` | 07 School Admin dashboard | per-school totals | `FORBIDDEN`/`TENANT_MISMATCH` | Tenant-scoped aggregate |
| `AudienceCount(filter)` | 13 audience estimate + dispatch | count of VERIFIED users matching the segment | `VALIDATION_FAILED` (empty filter) | Aggregate only — never user ids; counts < 20 returned as `0` with `suppressed=true` in the DTO to avoid singling out minors (`TODO: Confirm` threshold) |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `users.GetWithSelection(userID)` — VERIFIED status + `SectionID` from `verification_requests.requested_section_id` | 03 |
| `guardians.LinkedStudents(guardianID)` — which students a GUARDIAN enrollment covers | 03 | Abort `OnUserVerified` (03 decides verification; 04 never guesses) |
| `chat.JoinSectionGroups(userID, enrollment EnrollmentDTO)` — section + school + city official groups (signature owned by 05 `06` §2) | 05 | Enqueue `hierarchy.backfill`; user stays VERIFIED, membership back-filled |
| `chat.ArchiveSectionGroups(schoolID, sessionYear)` — old-session groups at migration | 05 | Job retries; archives are idempotent in 05 |
| `jobs.Enqueue(name, payload)` + worker runtime | 01 | Commit request already persisted; enqueue retried by request handler |
| `fcm_topic_bindings` read by 06 for device subscription | — (our table) | 06 owns retry of device subscription; bindings never expire |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| `POST /admin/cities`, archive/re-open city | `hierarchy:cities` |
| `POST /admin/schools`, `PATCH /admin/schools/{id}` | `hierarchy:cities` + `hierarchy:school:{schoolId}` |
| `POST /school/sections`, `PATCH /school/sections/{id}` | `hierarchy:school:{schoolId}` |
| `POST …/migrations/{id}/commit` (apply) | `hierarchy:school:{schoolId}` (new-session sections live, old archived) |

| Read | Tagged with |
| --- | --- |
| `GET /hierarchy/cities` | `hierarchy:cities` |
| `GET /hierarchy/cities/{id}/schools` | `hierarchy:cities` + `hierarchy:school:{schoolId}` per school |
| `GET /hierarchy/schools/{id}/sections` | `hierarchy:school:{schoolId}` |
| `hierarchy.GetSection` export | `hierarchy:school:{schoolId}` |

Picker data is small and stable — cache aggressively (24h TTL, Redis), invalidate by tag on every
mutation above. Admin reads are never cached.

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM | indirect via module 06 only | `FCM_SERVER_KEY` held by 06, never by 04 | n/a here | 06 owns | Bindings are durable rows; subscriptions converge when 06/FCM recover |
| (none other) | — | — | — | — | This module touches no R2, DeepSeek, payment or SMS systems |

## 6. UI ↔ Server Seam

The picker screens (module 03 onboarding) and admin screens (module 07) bind to these calls;
`hierarchy.*` strings are owned by this module in each app's `src/i18n`:

| UI element | Calls | Contract |
| --- | --- | --- |
| City picker step (03 onboarding) | `GET /api/v1/hierarchy/cities` | `CityDTO[id, nameBn, nameEn, isLaunchCity]`; empty state uses `hierarchy.city_empty` |
| School picker step (03) | `GET /api/v1/hierarchy/cities/{id}/schools` | `SchoolDTO[id, nameBn, nameEn]`; names only, no counts |
| Section picker step (03) | `GET /api/v1/hierarchy/schools/{id}/sections` | `SectionDTO[id, classLevel, name, sessionYear]`; class label via `hierarchy.class_label` |
| Tenant wizard (07 Super Admin) | `POST /api/v1/admin/schools` | School + adminUserId result; `CONFLICT` maps to `hierarchy.school.name_duplicate` |
| Sections manager + teacher assign (07) | `POST/PATCH /school/sections*`, `POST …/teachers` | `CONFLICT` → `hierarchy.section.name_duplicate` / `hierarchy.teacher_already_assigned`; `NOT_VERIFIED` → `hierarchy.teacher_not_verified` |
| Migration wizard (07) | `POST /school/migrations`, `GET /school/migrations/{id}`, `POST …/commit` | Run + items (PROMOTED/GRADUATED/RETAINED/ERROR); action labels `hierarchy.migration_action_*`; poll while COMMITTING |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. Exported Go signatures above are frozen for
Phase 1: 03/05/06/09/13/14 build against them. Additive evolution only (new optional result fields,
new exports); a breaking change requires an ADR plus a migration note in every consumer module's
`07-progress.md`.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 05 communication-engine | Verification completes; enrollment + topic bindings persist | Verified user, group membership arrives moments later | `hierarchy.backfill` job joins groups on recovery (`ORG-IT-007`) |
| 06 notifications / FCM | Everything in 04; bindings durable | Push arrives late (topics subscribed on recovery) | 06 re-reads `fcm_topic_bindings` and subscribes devices |
| 01 jobs worker | All reads + previews; commit accepted | Migration stays PREVIEWED until worker returns | Queued job runs when worker restarts; run never half-applied without checkpoints |
| Redis | All writes; pickers fall through to Postgres | Slower picker loads only | TTL cache rebuilds on return |
| Neon (Postgres) cold start | Nothing DB-backed | Slow first picker read | Warm-up ping after deploy; cache keeps subsequent reads hot |
| Duplicate `OnUserVerified` event | Idempotent path | No visible effect | Existing enrollment returned (`ORG-IT-001`) |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ORG-UT-006` | Topic naming matches `city-{id}` / `school-{id}` / `section-{id}` exactly | Unit | FCM topic contract for 06 |
| `ORG-UT-007` | `ResolveUserNodes` shape (ids + topic names) against a fixture enrollment set | Unit | 05/06/09/13 consumers |
| `ORG-IT-001` | `OnUserVerified` creates enrollment + group joins + topic bindings exactly once (doubled event) | Integration | seam idempotency (mandatory) |
| `ORG-IT-002` | Cross-tenant section read/write denied | Integration | tenant scope at the seam (mandatory) |
| `ORG-IT-003` | Migration dry-run then commit applies promotion rules | Integration | `PreviewMigration`/`CommitMigration` contract (mandatory) |
| `ORG-IT-004` | Migration commit idempotent on retry | Integration | job contract with 01 (mandatory) |
| `ORG-IT-007` | 05 down during verify → back-fill completes membership | Integration | I-1/I-2 degradation |
| `ORG-IT-008` | `CreateEnrollments` batch from 14: created/exists/error rows, tenant-scoped | Integration | I-4 contract |
| `ORG-IT-009` | City/school/section mutations invalidate `hierarchy:*` tags (cache sees fresh data) | Integration | §4 tag contract |

## 10. Task Checklist

- [ ] `ORG-INT-001` implement + export the nine §2 functions behind interface fakes for consumers — ____
- [ ] `ORG-INT-002` wire `hierarchy.backfill` job (05-outage path) into module 01 worker — ____
- [ ] `ORG-INT-003` implement `migration.run` worker with batch checkpoints + audit — ____
- [ ] `ORG-INT-004` cache tags `hierarchy:cities` / `hierarchy:school:{id}` + invalidation on mutations — ____
- [ ] `ORG-INT-005` `CreateEnrollments` batch contract test with module 14 fixtures — ____
- [ ] `ORG-INT-006` freeze `ResolveUserNodes` / `GetSection` DTOs with modules 05/06/09/13 review — ____
- [ ] `ORG-INT-007` tests `ORG-UT-006`–`007`, `ORG-IT-007`–`009` green in CI — ____
