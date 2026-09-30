# Organization Hierarchy — Solution Approach

**Module:** `04-organization-hierarchy` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Settled here first — before any task list and any code — per the module workflow
(`docs/modules/README.md`, `docs/prompt/prompt-build.md` §4 step 1). 📝 Spec drafted 2026-09-30.

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `cities` | Launch platform geography (Dhaka + Chattogram at launch); `is_launch_city` flag; ACTIVE/ARCHIVED | Yes |
| `schools` | The tenant root; belongs to a city; ACTIVE/ARCHIVED (soft only) | Yes |
| `sections` | Class + section tree under a school (Class 6 → A/B) with `session_year`; ACTIVE/ARCHIVED | Yes |
| `enrollments` | user ↔ section with role context (STUDENT/TEACHER/CLASS_TEACHER/GUARDIAN), `session_year`, status, source (SELF/ROSTER/MIGRATION) | Yes |
| `fcm_topic_bindings` | Hierarchy node → deterministic topic name (`city-{id}` / `school-{id}` / `section-{id}`) | Yes |
| `migration_runs` | One year-end migration per school per session: DRAFT → PREVIEWED → COMMITTED | Yes |
| `migration_run_items` | Per-enrollment result: PROMOTED / GRADUATED / RETAINED / ERROR + applied checkpoint | Yes |
| `users` | Verified status + registration-time hierarchy selection | No — module 03 |
| `chat_groups` / `chat_group_members` | Official section groups; 04 calls 05's join/archive functions | No — module 05 |
| `device_tokens` | Push targets subscribed to topics | No — module 06 |
| `jobs` | Durable in-DB queue driving migration apply + auto-group back-fill | No — module 01 |

### 1.2 Relationships

```text
cities 1 ──── n schools 1 ──── n sections 1 ──── n enrollments n ──── 1 users (module 03)

schools 1 ──── n migration_runs 1 ──── n migration_run_items n ──── 1 enrollments

cities    1 ──── 1 fcm_topic_bindings (node_type = CITY)
schools   1 ──── 1 fcm_topic_bindings (node_type = SCHOOL)
sections  1 ──── 1 fcm_topic_bindings (node_type = SECTION)
```

Fixed depth of three levels — no recursive tree. Class grouping is an attribute of `sections`
(`class_level`, `name`, `session_year`), not a node, so no self-referencing table is needed.

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `ORG-INV-001` | A user has at most one ACTIVE STUDENT enrollment per `session_year` | Partial unique index `(user_id, session_year) WHERE role='STUDENT' AND status='ACTIVE'` |
| `ORG-INV-002` | Section names unique per (school, class_level, session_year) | Unique index + service check |
| `ORG-INV-003` | No hard deletes: schools/sections/enrollments transition status only | Repository — no DELETE statements |
| `ORG-INV-004` | Every node has exactly one topic binding; topic names deterministic | Unique indexes `(node_type, node_id)` and `(topic_name)` |
| `ORG-INV-005` | Run lifecycle moves forward only: DRAFT → PREVIEWED → COMMITTED; commit only from PREVIEWED; items immutable once applied | Service state guard + `applied_at` checkpoints |
| `ORG-INV-006` | Public reads expose only ACTIVE nodes with no personal data; every tenant-scoped query filters by the caller's `schoolId` claim | Service filters (public queries) + repository scoping — no unscoped query exists |

## 2. Module Boundary

**Owns (writes):** `cities`, `schools`, `sections`, `enrollments`, `fcm_topic_bindings`, `migration_runs`, `migration_run_items`.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | `users.GetWithSelection(userId)` — VERIFIED status + registered section choice | Identity and verification are 03's domain; 04 never decides verification |
| 05 | `chat.JoinSectionGroups(userID, enrollment)` · `chat.ArchiveSectionGroups(schoolId, sessionYear)` | Groups are 05's; 04 only triggers membership lifecycle |
| 01 | `jobs.Enqueue(name, payload)` + worker runtime | Migration apply and back-fill run on the shared queue, not a bespoke scheduler |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

**The auto-grouping seam (exact chain, declared once here and in `06` §2/§3):**

```text
03 verify handler
  └─► hierarchy.OnUserVerified(userId)                 (exported by 04)
        ├─ tx: insert enrollment (idempotent) + upsert fcm_topic_bindings (section, school, city)
        ├─► 05 chat.JoinSectionGroups(userID, enrollment)           (05 owns groups; join failure is non-fatal)
        │     └─ on failure: enqueue jobs `hierarchy.backfill` → retried; user stays VERIFIED
        └─► 06 reads fcm_topic_bindings and subscribes the user's device tokens (06 owns devices)
```

Synchronous because it is cheap (two inserts + one in-process call); the job fallback covers 05
outages without blocking verification.

## 3. Lifecycle

```text
migration run:  DRAFT ──dry_run=false──▶ PREVIEWED ──commit (job applies all items)──▶ COMMITTED
                  │                        │                                             (terminal)
                  └─ discard               └─ apply failure: stays PREVIEWED; job retries,
                                              resuming from the first unapplied item
                                              (batch checkpoints via applied_at)

enrollment:  ACTIVE ──migration──▶ ENDED (promoted) · ALUMNI (graduated Class 10/12) · RETAINED stays ACTIVE
school:      ACTIVE ◀──re-open──▶ ARCHIVED            (soft only — ORG-BR-004)
section:     ACTIVE ──migration/archive──▶ ARCHIVED   (old-session sections archived; groups archived via 05)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| (none) | create school | school ACTIVE | Super Admin; city ACTIVE; unique name | topic binding; audit; first School Admin via 03 |
| school ACTIVE | archive / re-open | ARCHIVED / ACTIVE | Super Admin | pickers hide/show; cache invalidation; audit |
| (none) | create section | section ACTIVE | School Admin; unique per class+session | cache invalidation |
| enrollment ACTIVE | migration apply | ENDED / ALUMNI | run PREVIEWED + zero ERROR items | new-session enrollment; 05 group refresh; topic re-bind |
| run DRAFT | re-preview with dry_run=false | PREVIEWED | zero ERROR items | audited preview record |
| run PREVIEWED | commit | COMMITTED | caller owns school; no ERROR items | `jobs` enqueue; per-school batched apply; audit |

## 4. Rendering & Caching

No UI in this module — the surfaces below are API reads consumed by module 03 pickers and module 07
screens; caching is Redis (go-redis) with tag invalidation in front of Postgres. bn/en names ship in
every payload so clients never re-fetch per language.

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `GET /hierarchy/cities` | Stateless API read | Redis, 24h TTL | `hierarchy:cities` |
| `GET /hierarchy/cities/{id}/schools` | Stateless API read | Redis, 24h TTL | `hierarchy:school:{schoolId}` + `hierarchy:cities` |
| `GET /hierarchy/schools/{id}/sections` | Stateless API read | Redis, 24h TTL | `hierarchy:school:{schoolId}` |
| `GET /school/enrollments` (admin) | Stateless API read | Not cached — live data | — |

Hierarchy data is small and rarely changes → cache aggressively, invalidate on every mutation
(`06` §4).

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| City list (add/archive; launch flag) | Topic naming scheme `city-{id}` / `school-{id}` / `section-{id}` |
| School tenants + first School Admin onboarding | Promotion class order (+1; graduation at Class 10 and 12) — `TODO: Confirm` (constant until confirmed) |
| Classes/sections per session year | Role→endpoint permission matrix (Super Admin / School Admin / Teacher) |
| Class-teacher assignments per section | Public-read exposure set (names only, no counts) |
| Migration `fromSessionYear` per school (one open run per session) | Launch-city filter default (`launch=true`) and batch size (500) for migration apply |

## 6. Security

Every protected entry point runs the chain **authenticate → load role claims → tenant-scope**.
Errors use the shared RFC-7807 envelope (`UNAUTHENTICATED`, `FORBIDDEN`, `VALIDATION_FAILED`,
`TENANT_MISMATCH`, `NOT_FOUND`, `NOT_VERIFIED`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL`).

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| `GET /hierarchy/*` (3 picker reads) | Public, no auth | Read only ACTIVE nodes; response carries no user data — safe to expose by design |
| `POST /admin/schools`, `PATCH /admin/schools/{id}`, `POST /admin/cities` | Super Admin role claim | Platform-wide; audit every mutation |
| `POST/PATCH /school/sections*`, `…/teachers`, `GET /school/enrollments` | School Admin / Teacher claims | Repository queries forced to `school_id` from the JWT claim — request-supplied school ids are ignored (ORG-BR-001) |
| `POST /school/migrations`, `GET …/{id}`, `POST …/{id}/commit` | School Admin claim | Run lookup joined to the caller's school; other schools' runs → `TENANT_MISMATCH` |
| Rate limits | — | Default class everywhere; migration commit + school creation tightened per school (5/hour) to stop abuse |
| Privacy | — | Public endpoints never expose enrollments, counts, or admin identity; minors' data never leaves tenant scope (`brd.md` §6) |

Validation is contract-first: OpenAPI-generated validators reject malformed input before services
run; sqlc repositories accept tenant-scoped parameters only.

## 7. Accessibility & Motion

None in this module — no UI surface exists here. The obligation this module carries is the **data
contract** for accessible screens elsewhere: every name in bn + en (`nameBn`/`nameEn`) so module 03
picker screens and module 07 admin screens can render the user's language, and stable IDs for
screen-reader labelling. Animated surfaces (if any) are owned by 07's motion table.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Partial migration apply (worker crash mid-commit) | `migration_run_items.applied_at` checkpoints; job marked failed in `jobs` | Some students moved, run still PREVIEWED | Job retry resumes from the first unapplied item — per-school transactional batches make re-runs idempotent |
| 2 | Module 05 down during `OnUserVerified` | Join call error → back-fill job enqueued | User VERIFIED with enrollment; group membership delayed | `hierarchy.backfill` retries (×5, backoff); membership back-filled on recovery |
| 3 | Module 06/FCM unavailable at verify | Bindings written regardless; 06 reads them later | Push topics subscribed late | Bindings are the contract — 06 subscribes devices whenever tokens register; no 04 action needed |
| 4 | Redis cache down | Cache errors fall through | Picker latency rises to Postgres-level | Read-through miss path serves Postgres; degraded, never fatal |
| 5 | Duplicate verify event (retry/race) | Unique partial index + idempotent service path | None — second call no-ops | Existing enrollment returned (`ORG-BR-006`) |
| 6 | Commit requested with ERROR items or wrong state | Service state guard | `CONFLICT`, nothing applied | School Admin fixes sections / re-previews |
| 7 | Neon cold start (free tier) | Slow first query | Picker first-read latency spike | Cache warm-up job pings `hierarchy:cities` after deploy; TTL keeps it hot |

## 9. Performance

- **Volumes:** 2 launch cities → 10+ schools (year 1, `brd.md` Goal 1) → ~100–300 sections/school-year → ~2,000 enrollments/school. Hierarchy metadata stays in the low thousands of rows; `enrollments` in the tens of thousands.
- **Hot queries + indexes:** picker reads (cached, tag-invalidated); enrollment-by-user+session (`(user_id, session_year)`, auto-grouping); roster by section (`(section_id, role, status)`, paged); migration candidate scan (`(school_id, session_year, status)`); unique `sections(school_id, class_level, name, session_year)`; unique `fcm_topic_bindings(topic_name)`.
- **Migration apply:** batches of 500 items per transaction; a 2,000-student school completes in 4 transactions — well inside the `jobs` worker budget.
- **Bundle impact:** none for apps (API-only module); `packages/shared` gains the `hierarchy.*` catalog (~1 KB gzip).

## 10. Alternatives Considered

### Option A — Adjacency list (explicit FK columns per level) · Option B — Closure table / ltree

| | A: FK columns (chosen) | B: closure table / ltree |
| --- | --- | --- |
| Advantages | Matches the fixed 3-level model exactly; trivially tenant-scoped (`school_id` on every row); sqlc-friendly plain SQL | Supports arbitrary depth and "subtree" queries in one query |
| Disadvantages | A new level (e.g. class nodes) needs a migration | Join-table/label maintenance for a depth that never varies; over-engineering (`docs/persona.md`: do not over-engineer) |
| Complexity / weight | Minimal — 3 FK columns | Extra table or Postgres extension (`ltree`) + query patterns few people know |

### Option A — Auto-grouping synchronously on verify · Option B — Verify-time job

| | A: synchronous (chosen) | B: job on verify |
| --- | --- | --- |
| Advantages | Student lands in the group within the verify request; easy to reason about; cheap (2 inserts + 1 call) | Verify handler never blocked by 05 |
| Disadvantages | 05 outage must be handled | Student sees "verified" but group-less for seconds–minutes; extra job machinery on the hottest path |
| Complexity / weight | Low, plus one back-fill job as fallback | Medium — every verify enqueues |

**Recommendation:** A + A — explicit FK columns for the fixed hierarchy; synchronous auto-grouping
with the `hierarchy.backfill` job as the failure fallback (§2 chain). **ADR:** record both in this
module's `07-progress.md`; the FK-column decision is referenced by modules 05/06/13, so if it ever
changes it moves to `docs/decisions/`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Bangladesh academic session = calendar year; promotion rules stay "+1, graduate at 10/12" | Migration window lands mid-year; wrong students moved at year end | `fromSessionYear` is per-school input (code is date-agnostic); rules live in one tested config constant; dry-run preview mandatory before commit; `TODO: Confirm` (OQ-2) |
| 2 | One school per student; guardians map 1-to-n onto students | Multi-school students (rare in BD K–12) hit `ORG-INV-001` | END the old enrollment explicitly via roster tooling before re-enrolling; migration RETAINED path covers repeats |
| 3 | All schools migrate in the same weeks (Dec–Jan) | `jobs` worker contention | Batches of 500; worker is per-module and horizontally scalable; runs enqueue per school, not globally |
| 4 | Section names reused across sessions (A/B every year) | Migration maps by (class+1, same name) — name changes break mapping | Preview marks unmapped students ERROR; School Admin creates the missing sections first |
| 5 | Neon free tier cold starts delay the first picker read of the day | Registration funnel feels slow | Cache warm-up after deploy + 24h TTL (§8 #7) |
