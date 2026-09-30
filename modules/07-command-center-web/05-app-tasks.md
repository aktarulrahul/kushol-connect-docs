# Command Center Web — App Tasks (Mobile)

**Module:** `07-command-center-web`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** N/A — this module covers `web` `api` only (README row: "… · `web` `api`")
**Last updated:** 2026-09-30

> N/A — module 07 is web-only. The mobile app surfaces that consume this module's data (notices
> published from the School Admin composer, tenant/city picker entries created by the Super Admin,
> download links surfaced on `/download`) belong to modules 03/05/06. Nothing below introduces app
> work; the heading structure is kept for template parity.

---

## 1. Screen Inventory

N/A — no expo-router screens in this module. The mobile side of the platform is owned by modules
03 (onboarding/login), 05 (chat/notices), 06 (push), 08+ (AI/marketplace).

## 2. Screen Breakdown

N/A — no app screens. The notice published via this module's composer reaches mobile through
module 05's `notices` REST/WS contract and module 06's push fan-out, both already specified.

## 3. Forms & Input

N/A — no app forms. Shared zod schemas in each app's `src/schemas` are reused by the web forms only here.

## 4. Data Flow

N/A — no app data flow. The generated OpenAPI client already covers `app`; module 07 adds the
lead/vendor/stats paths to the same spec so `app` could consume them later without new contracts.

## 5. Motion Spec

N/A — no app motion. Web motion lives in `04-frontend-tasks.md` §5.

## 6. Responsive & Device Behaviour

N/A — web responsive behaviour lives in `04-frontend-tasks.md` §6 (portals target ≥ 768 tablet;
landing works down to 360 px since it is the public funnel).

## 7. Accessibility

N/A — app accessibility is covered per-module by the modules that own app screens; module 07's web
a11y checklist lives in `04-frontend-tasks.md` §7.

## 8. Offline Behaviour

None — requires connectivity. N/A for `app`: this module has no app surface; the web lead forms
implement the retry-safe submission pattern from `02-solution-approach.md` §8 instead of an offline
queue.

## 9. Task Checklist

None — N/A (no `WEB-AP-*` tasks; module covers `web` `api` per the README row).
