# Organization Hierarchy — Frontend Tasks

**Module:** `04-organization-hierarchy`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

N/A — this module ships **no web screens**; it covers apps `api` + `shared` only (README row). The
Super Admin tenant screens and the School Admin migration wizard are built in module 07
(`07-command-center-web`, prefix `WEB-FE-*`) against the endpoints in `03-backend-tasks.md` §2.
This module specifies the data they need: bn + en names in every payload and the `hierarchy.*` /
`validation.*` keys in `01-user-stories.md` §6 (`packages/shared` catalogs).

---

## 1. Screen Inventory

Routes module 07 will implement (owned there; listed here so the contract is visible):

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/admin/tenants` | Tenant school list (search, status, city filter) | Server Component | Super Admin |
| 2 | `/admin/tenants/new` | School onboarding wizard (city + school + first School Admin) | Server Component + client form | Super Admin |
| 3 | `/admin/cities` | City management (add, archive, launch flag) | Server Component | Super Admin |
| 4 | `/school/sections` | Classes/sections manager per session year | Server Component | School Admin |
| 5 | `/school/sections/[sectionId]` | Section detail + roster + class-teacher assignment | Server Component | School Admin |
| 6 | `/school/migrations/new` | Year-end migration wizard: dry-run → review → commit → result | Server Component | School Admin |

## 2. Screen Breakdown

N/A — no screens in this module; wireframes, components and states are `WEB-FE-*` items in module 07, against `03-backend-tasks.md` §2 and `06` §6.

## 3. Forms

N/A — no forms here. Module 07 forms (school create, section create, teacher assign, migration
trigger) mirror the zod schemas generated from the OpenAPI contract; error messages come from the
`hierarchy.*` / `validation.*` keys in `01-user-stories.md` §6.

## 4. Data Flow

Reference mapping for module 07 (this module defines it; 07 implements it):

| Need | Mechanism |
| --- | --- |
| Tenant list / city list | Server Component → generated OpenAPI client → `GET /api/v1/hierarchy/cities`, `GET /api/v1/school/enrollments`, admin reads |
| School onboarding | Server Action → `POST /api/v1/admin/schools` → toast + refreshed tenant list |
| Sections manager | Server Action / Route Handler → `POST`/`PATCH /api/v1/school/sections*`, `POST …/teachers` |
| Migration wizard | `POST /api/v1/school/migrations` (dryRun) → `GET /api/v1/school/migrations/{id}` polling → `POST …/commit` |

## 5. Motion Spec

N/A — no UI in this module; module 07 owns the motion table for the routes listed in §1.

## 6. Responsive Behaviour

N/A — no UI in this module. Module 07 targets keyboard-complete admin layouts down to tablet (`prompt.txt` §4B).

## 7. Accessibility

N/A — no UI in this module. Contract obligation that makes 07's screens accessible: every entity
carries `nameBn` + `nameEn`, and list endpoints return stable ids for labelling.

## 8. Design-System Compliance

N/A — no UI in this module; module 07 applies the shared tokens (`packages/shared`) to the routes above.

## 9. Task Checklist

N/A — no `ORG-FE-*` items exist by design (README ID rules). The six routes in §1 are tracked as
`WEB-FE-*` items inside module 07; this module's frontend-adjacent deliverables are the OpenAPI
contract entries (`03` §2/§7) and the bn/en catalogs in `packages/shared`.
