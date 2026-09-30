# LMS/ERP Sync — App Tasks (Mobile)

**Module:** `14-lms-erp-sync`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

`docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
`docs/tech-stack.md` (app table) are binding — for the modules that do ship app surfaces.

---

## 1. Screen Inventory

N/A — no mobile screens in this module. Roster upload and LMS/ERP integration management are
School Admin web-only surfaces (README module 14 scope: `api` `web`; module 07 portal shell).
Students/guardians/teachers experience this module only through its *effects* (enrollments, groups,
topics applied by the 04/05/06 chain), never through app UI.

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| — | N/A — no routes; no push topics or deep links are produced by module 14 | — | — | — |

## 2. Screen Breakdown

N/A — no screens. No wireframes, components or states to specify. Any future mobile view of sync
status (e.g. a Super Admin tenant health card) is a new module decision, additive to this spec.

## 3. Forms & Input

None — no app forms. Upload and endpoint forms live in `04-frontend-tasks.md` §3 (web zod schemas
in `applications/web/src/schemas`).

## 4. Data Flow

None — the app makes no calls to `sync.*` endpoints. The module's server data flow is declared in
`06-integration-tasks.md` §1/§6.

## 5. Motion Spec

N/A — no app surfaces, nothing animated.

## 6. Responsive & Device Behaviour

N/A — no app surfaces. (Indirect device impact only: imported VERIFIED users get groups/topics via
the existing 04→05→06 chain; FCM topic fan-out is module 06's contract, untouched here.)

## 7. Accessibility

N/A — no app surfaces; web a11y obligations are in `04-frontend-tasks.md` §7.

## 8. Offline Behaviour

None — requires connectivity. No app action exists to queue; the app neither uploads rosters nor
manages endpoints.

## 9. Task Checklist

None — `LMS-AP-*` scope is empty by design (`N/A — README covers api + web only`). Any app task
appearing later must be justified against module 07's portal boundaries first.
