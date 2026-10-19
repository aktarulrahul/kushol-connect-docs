# Communication Engine — Frontend Tasks

**Module:** `05-communication-engine`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** N/A — no web frontend in this module
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from each app's `src/theme`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

N/A — chat is app-first: all student/teacher/guardian chat and notice surfaces are built in
`05-app-tasks.md` (Expo). The only web consumer is the **School Admin notice composer + club
approval queue**, built by module 07 against the REST endpoints of `03` §2.

Routes module 07 implements against these APIs:

| # | Route (07) | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/school/notices` | Notice list + pin/delete actions | Server Component | School Admin |
| 2 | `/school/notices/new` | Notice composer (attachment via `POST /media/*`) | Client Component (form) | School Admin |
| 3 | `/school/notices/[id]` | Notice detail + pin/delete | Server Component | School Admin |
| 4 | `/school/clubs` | Club approval queue (approve/decline `pending_approval` groups) | Server Component + actions | School Admin |

## 2. Screen Breakdown

N/A — no screens built in this module. App-side equivalents (chat tabs, group screen, notices
tab, request inbox) are specified in `05-app-tasks.md` §1–§2; the 07-side composer follows
module 07's admin form pattern.

## 3. Forms

N/A — no web forms here. The notice-composer form (RHF + Zod, schemas mirroring
`validation.notices.*`) belongs to module 07; the zod schemas it imports are generated from the
OpenAPI contract owned in `03` §2 of this module.

## 4. Data Flow

N/A — no web data flow in this module. Contract handoff: 07 consumes `GET/POST /api/v1/notices`,
`PATCH /api/v1/notices/{id}/pin`, `DELETE /api/v1/notices/{id}`, and `POST /chat/groups` +
member-role endpoints for club approvals — via the generated client, never the database
directly. Cache tags (`notices:school:{id}`, `notices:section:{id}`) are defined in `06` §4 so
07's Server Components can subscribe to them.

## 5. Motion Spec

N/A — no web UI. (Chat bubble, typing-indicator and notice-row motion is app-side: `05-app-tasks.md` §5.)

## 6. Responsive Behaviour

N/A — no web UI. (07's routes follow module 07's responsive table; app surfaces are 360px-first per `05-app-tasks.md` §6.)

## 7. Accessibility

N/A — no web UI. (App-side a11y: `05-app-tasks.md` §7; 07-side composer a11y: module 07's checklist, axe-clean per the repo DoD.)

## 8. Design-System Compliance

N/A — no web UI. The bn/en strings this module contributes to each app's `src/i18n` (`chat.*`,
`notices.*`, `validation.*`) are enumerated in `01` §6 and `05-app-tasks.md` §2; 07's composer
reuses the same keys.

## 9. Task Checklist

- [x] `COM-FE-001` — 2026-10-02 (spec + generated TS clients updated in api/web/app; tags `notices:school:{id}`/`notices:section:{id}` documented in the spec): — Contract handoff to module 07: verify endpoints #15–#20 (notices/media) and #3/#4/#6 (club approval) exist in the generated `openapi-fetch` client, and the cache-tag contract of `06` §4 is importable by 07
- [x] `COM-FE-002` — — 2026-10-18 (owner instruction; the web console `/chat` is module-owned since 2026-10-17): @mentions (composer "@" roster picker via `listChatGroupMembers`, highlight of "@Name" tokens from the message's mention ids) + stars (Star/Unstar in the ⋮ menu, star badge on the bubble, "Starred messages" card in the group info panel, jump-to-message from the card); contract #23–#25 synced into the generated client; unit-pinned via `message-actions` (star) — 2026-10-18
