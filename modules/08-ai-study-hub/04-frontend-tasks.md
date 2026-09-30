# AI Study Hub — Frontend Tasks

**Module:** `08-ai-study-hub`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** N/A — no web frontend in this module
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from `packages/shared`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

N/A — the student/teacher AI surfaces are **mobile-only** (Expo app, `05-app-tasks.md`). The web
Command Center has no AI screens in this module by design: Pain Point Matrix dashboards belong to
module 09, and AI cost cards for Super/School Admin ship in module 07 **when this module's data
exists**. Routes other modules implement against this module's APIs:

| # | Route (owner module) | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/admin/ai-cost` (07) | Platform AI cost, cost per active user, per-feature split | Server Component + chart | Super Admin |
| 2 | `/school/ai-cost` (07) | Own-tenant AI cost cards | Server Component | School Admin |
| 3 | `/school/ai-matrix` (09) | Pain Point Matrix (failed-MCQ topics, classified chat queries) | Server Component + heatmap | Teacher / School Admin |

## 2. Screen Breakdown

N/A — no screens are built in this module. All scan-flow, archive, test-taking and quota wireframes
are specified in `05-app-tasks.md` §2 (360px-first, bn-first). The 07 cost cards and 09 matrix
follow those modules' admin screen patterns and consume the data contracts declared here — no
AI-specific web UI is specified twice.

## 3. Forms

N/A — no web forms. All input surfaces (test-generation form, search bar, share toggle) are
app-side (`05-app-tasks.md` §3) with zod schemas from `packages/shared` mirroring
`validation.ai.*`; 07's month picker and 09's filters reuse the generated contract shapes.

## 4. Data Flow

N/A — no web data flow in this module. Contract handoff (always via the generated `openapi-fetch`
client or Go exports — never the database directly):

| Consumer | Consumes | Mechanism |
| --- | --- | --- |
| 07 cost cards | `GET /api/v1/ai/admin/cost-report?month=` (`03` §2 #16) | role-gated: Super = platform, School Admin = own tenant |
| 09 matrix | `ai.AttemptStats(sectionID, from, to)` + `ai.ClassifyChatQueries` (`06` §2) | Go service exports; 09 exposes its own API routes |
| Both | cache tags `ai:usage:{userId}`, `ai:breaker:state` (`06` §4) | revalidation headers through the generated client |

## 5. Motion Spec

N/A — no web UI. (Score-ring, scan-progress and tag-chip motion is app-side: `05-app-tasks.md` §5,
with static reduced-motion forms.)

## 6. Responsive Behaviour

N/A — no web UI. (07's admin routes follow module 07's responsive table; app surfaces are
360px-first per `05-app-tasks.md` §6.)

## 7. Accessibility

N/A — no web UI. (App-side a11y: `05-app-tasks.md` §7; 07/09 dashboards inherit the repo-wide
axe/WCAG 2.2 AA gate in their own modules' checklists.)

## 8. Design-System Compliance

N/A — no web UI. The bn/en strings this module contributes to `packages/shared` (`ai.*`,
`validation.ai.*`) are enumerated in `01` §6 and `05-app-tasks.md` §2/§3; 07's cost cards and 09's
matrix reuse those keys (feature names, quota copy, "AI paused" banner) rather than inventing
parallel strings.

## 9. Task Checklist

- [ ] `AIH-FE-001` — Contract handoff to module 07: endpoint #16 (`cost-report`) present in the generated `openapi-fetch` client with role-gated payloads; cache tags of `06` §4 importable by 07's Server Components
- [ ] `AIH-FE-002` — Contract handoff to module 09: `ai.AttemptStats` / `ai.ClassifyChatQueries` exports match 09's expected DTOs (`06` §2); no dashboard work duplicates this module's data model
