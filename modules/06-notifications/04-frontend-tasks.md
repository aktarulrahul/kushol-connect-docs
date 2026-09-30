# Notifications — Frontend Tasks

**Module:** `06-notifications`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

This module ships **no web surfaces** — the mobile app is the only notification consumer.
`docs/design-reference/README.md` rules still bind any future admin surface built from this
module's data (module 07): tokens only from each app's `src/theme`, every user-facing string in
Bengali + English.

---

## 1. Screen Inventory

N/A — no web screens exist in this module. The Super/School Admin "send notice" composer lives in
modules 05/07 and calls the `notify.BroadcastTopic` export server-side; the pilot test-push
control and delivery aggregates belong to module 07 and consume `POST /admin/notifications/test`
and the admin deliveries endpoints through the generated `openapi-fetch` client.

## 2. Screen Breakdown

N/A — reason: this module defines no web screens (see §1). The delivery-aggregate shapes consumed
by the future 07 dashboard are frozen in `03-backend-tasks.md` §2 (admin deliveries endpoints) so
07 builds against generated types, not bespoke ones.

## 3. Forms

N/A — no web forms in this module. When module 07 renders the test-push control, its zod schema
mirrors the OpenAPI contract exactly (`class`, `target`, `sectionId`) and reuses the
`validation.notifications.*` message keys — both languages from day one.

## 4. Data Flow

N/A — no web data flow in this module. Module 07 will read delivery aggregates via the generated
OpenAPI client → api (never the database directly), with the same auth chain (Super Admin /
School Admin role claims) enforced server-side per `03-backend-tasks.md` §2.

## 5. Motion Spec

N/A — no web surfaces; app-side motion is specified in `05-app-tasks.md` §5 (foreground banner,
premier/toggle transitions) with reduced-motion variants.

## 6. Responsive Behaviour

N/A — no web surfaces. Admin dashboards presenting this module's data follow module 02/07
responsive rules when built.

## 7. Accessibility

N/A — no web screens to audit here. Accessibility obligations for the surfaces that *display*
notification data (app settings, primer) are in `05-app-tasks.md` §7; future 07 dashboards are
axe-audited under module 07's checklist.

## 8. Design-System Compliance

N/A for screens. This module contributes the `notifications.*` and `validation.notifications.*`
bn/en catalog entries to each app's `src/i18n` (consumed by the app today, module 07 dashboards
later); no tokens or typography decisions are made here.

## 9. Task Checklist

None — no `NTF-FE-*` items exist for this module (web surfaces belong to module 07; the app is
covered by `NTF-AP-*` in `05-app-tasks.md`).
