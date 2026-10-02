# 04-organization-hierarchy — Build Progress

Module: organization-hierarchy · Surfaces: api (web/app N/A by design) ·
Repo: `applications/api` (branch `module/03-identity-access` — see ADR-4) · **Last updated:** 2026-10-02

> Note: the build prompt parameter `TODAY=2026-10-01` lags the actual build date; all dates below
> are recorded truthfully as 2026-10-02.

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ approved 2026-10-02 | plan delivered in session; owner answered with the onboarding flow steer + "proceed with recommended" |
| 2 UI (mock-driven) | N/A — module ships no web/app screens (`04`/`05` checklists have no items; picker UI = 03 `IDT-AP-*`, admin screens = 07 `WEB-FE-*`) | — |
| Gate 1 (UI approval) | N/A — no UI surface (recorded per build prompt §3 exceptions) | — |
| 3 Docs sync | ✅ 2026-10-02 | this file, `08-gaps.md`, README row → 🚧, `06` §1/§2 gained I-8 + `CreateSchool`, technical-document change log, 03 `06` §3 cross-module note |
| 4 Backend | 🚧 schema + services + tests done 2026-10-02; entry points/jobs/seed/handler-wiring wait for Gate 2 | evidence table below |
| Gate 2 (SQL on Neon) | ⏳ pending owner — one command applies 01 → 03 → 04 in order | hand-off below |
| 5 Integration | ⏳ after Gate 2 | entry points, OpenAPI regen, jobs, seed, ORG-IT-006, web/app spec sync |
| Gate 3 (integrated flows) | ⏳ pending | — |
| 6 Gaps & verification | 🚧 | `08-gaps.md` G-1…G-6 |

## Owner decisions (2026-10-02) — ADR

0. **ADR-0 — Standing rule (owner, 2026-10-02): the agent never runs the app.** No Docker, no
   dev servers, no api binary, no direct DB sessions. Anything app-side — Gate 2 SQL,
   `make test-integration`, the dev stack — is run manually by the owner with the exact
   commands handed over; results recorded here. Agent-side checks are limited to
   build/vet/lint/fmt/contracts and container-free unit tests.
1. **ADR-1 — Picker data is DB-backed (owner instruction).** "All cities, schools/colleges from
   cities, sections … should come from the backend": the three public picker reads are served by
   the real hierarchy service (Postgres + Redis 24 h tag cache), replacing 03's in-memory demo
   fake (which remains for 03's own tests).
2. **ADR-2 — Onboarding via request approval (owner instruction + Q1 recommended).** A
   school/college enters the hierarchy when the application admin approves its public
   school-request: 03's `POST /admin/school-requests/{id}/approve` handler orchestrates
   `hierarchy.CreateSchool` (04; school + `school-{id}` binding + audit in one tx) →
   `users.CreateProvisionedAdmin` (03; the request's POC becomes a pre-verified `school_admin`,
   signs in by phone OTP) → decision recorded. `POST /admin/schools` stays in the contract as the
   data-carrying path (used directly by the approval flow and by 07's wizard later).
3. **ADR-3 — `schools.type` column (spec gap found while wiring ADR-2).** Requests carry
   `school|college`; the spec's `schools` table had no type. Added `type` (`school` default,
   CHECK-constrained) directly in migration `…090002` — the 04 block has never been applied
   anywhere, so no fix-forward was needed.
4. **ADR-4 — Branch state (owner-informed default).** All three repos sit on
   `module/03-identity-access` with uncommitted 03 WIP; no commits were authorised for this
   session, so 04 builds in the working tree alongside the WIP. 04's changes are kept in separate
   files where possible; shared-file edits (httpapi server, wiring) are minimal and marked.
5. **Request ↔ school traceability (Q3):** audit trail only — no schema change to 03's
   `school_requests` (04's `school.created` audit entry records the request id).
6. **Rate-limit keying (implementation note):** the 5/hour caps on school creation and migration
   create/commit key on client IP, not principal — the rate classifier runs before
   authentication in the router chain. Stricter for shared NATs; revisit with module 07 if needed.
7. **Re-preview semantics:** `PreviewMigration` replaces any DRAFT for the same
   (school, session) — discard-and-recompute per the §3 lifecycle table; one live run still
   enforced by the partial unique index.

## Defaults relied on (open questions / precedence)

- OQ-1 launch cities: Dhaka + Chattogram only.
- OQ-2 `TODO: Confirm` promotion rules: +1 within same school, Class 10/12 → ALUMNI, mapping by
  (class+1, same name), stream carried forward, preview ERROR blocks commit, 500-item batches.
- OQ-3: Super-Admin-provisioned onboarding — refined by ADR-2 (request-approval path).
- OQ-4: guardians get role-GUARDIAN enrollments in each linked student's section at verification.
- Precedence: picker `HierarchySection.classLevel` stays `string` (03 + web/app clients already
  ship that shape; 04's admin DTOs use integer); `sections.stream` ships inside migration 3 (also
  covering checklist `ORG-BE-026`'s "+ sections.stream" without an extra file).

## Evidence

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` + `go vet ./...` (+ `-tags=integration` on hierarchy) | clean, 2026-10-02 |
| api | `make fmt-check` | clean |
| api | `make contracts-check` | `contracts: no drift` |
| api | golangci-lint `./internal/hierarchy/... ./internal/users/...` | 0 issues (repo-wide `./...` reports 1 errcheck in 03's uncommitted `smsout.go` WIP — not 04's) |
| api | `go test -race ./...` (unit, no containers) | **20/20 packages ok**, 0 failures (incl. hierarchy: ORG-UT-001…007) |
| api | migrations up → down-to-zero → up on a scratch Postgres 18 database | `20261002090007 dirty=false`, all 7 down files reverse cleanly (validated 2026-10-02 before ADR-0 froze agent-side runs) |
| api | `ORG-IT-001…009` (testcontainers) | **pending owner run** (G-6): `make test-integration`. Partial runs before the rule exercised IT-005/008/009 green and exposed 3 defects — all fixed: missing user rows in seeds (users FK), `UpsertTopicBinding DO NOTHING` returning no row, IT-003 ACTIVE-count assertion |

## Gate 2 hand-off (owner runs; nothing here needs the agent)

Files (all in `applications/api/db/migrations/`, this module's reserved block
`20261002090001–090007` — README registry row 3):

| # | Migration | One-line description |
| --- | --- | --- |
| 1 | `20261002090001_create_cities.{up,down}.sql` | `cities` — platform geography, unique bn/en (case-insensitive), launch flag, soft-only status |
| 2 | `20261002090002_create_schools.{up,down}.sql` | `schools` — the tenant root (`id` = tenant claim), `type school\|college` (ADR-3), unique name pair per city |
| 3 | `20261002090003_create_sections.{up,down}.sql` | `sections` — class 1–12 + `stream` + session year, unique per (school, class, name, session) |
| 4 | `20261002090004_create_enrollments.{up,down}.sql` | `enrollments` — user↔section roles; one ACTIVE STUDENT per session; idempotency key |
| 5 | `20261002090005_create_fcm_topic_bindings.{up,down}.sql` | `fcm_topic_bindings` — deterministic `city-/school-/section-{id}` topics (06's contract) |
| 6 | `20261002090006_create_migration_runs_and_items.{up,down}.sql` | `migration_runs` + `migration_run_items` — DRAFT→PREVIEWED→COMMITTED lifecycle, `applied_at` resume checkpoints |
| 7 | `20261002090007_add_identity_hierarchy_fks.{up,down}.sql` | wires 03's loose refs (`users.school_id`, `verification_requests.school_id`/`.requested_section_id`, `guardian_links.school_id`) to `schools`/`sections` |

Exact commands (from `applications/api/`; `<NEON_URL>` = the shared Neon `DATABASE_URL`):

```sh
DATABASE_URL="<NEON_URL>" go run ./cmd/api migrate up --confirm   # applies every pending migration in version order (01 → 03 → 04)
DATABASE_URL="<NEON_URL>" go run ./cmd/api migrate-status          # expect: database_version=20261002090007 dirty=false
```

If the local `kc` database should also get the block (03's flow did), run the same pair without
the env override (api/.env already points at it). Note: on a database holding rows that point at
the old in-memory demo ids, migration 7's `VALIDATE CONSTRAINT` fails loudly — report the output
and the demo seed (built after this gate) restores the demo tenant under its stable id.

## Owner-run checks after Gate 2 confirmation

```sh
cd applications/api && make test-integration   # ORG-IT-001…009 + 01/03 suites (Docker required)
```
