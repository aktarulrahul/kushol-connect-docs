# Organization Hierarchy — App Tasks (Mobile)

**Module:** `04-organization-hierarchy`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

N/A — this module ships **no mobile app screens**. The hierarchy picker UI (City → School → Section
cascade) lives in module 03's onboarding (`03-identity-access`, prefix `IDT-AP-*`); this module owns
only the **data contract** those screens consume: the three public picker endpoints
(`03-backend-tasks.md` §2) and the bn/en strings under `hierarchy.*` in `packages/shared`. Migration
and tenant management are Command Center (web, module 07) surfaces — never in-app.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| — | — | None in this module (picker screens are `IDT-*` in module 03; they read this module's endpoints) | n/a | none |

## 2. Screen Breakdown

N/A — no app screens in this module. The onboarding picker wireframes, states and 360px layouts are
specified by module 03 (`05-app-tasks.md` there) against this module's public read contract.

## 3. Forms & Input

N/A — no forms in this module. The picker's zod schema (cityId → schoolId → sectionId + sessionYear)
is generated from the OpenAPI contract and validated server-side when module 03 submits registration.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Picker reads (module 03 screens) | TanStack Query → generated OpenAPI client → `GET /api/v1/hierarchy/cities` → `…/cities/{id}/schools` → `…/schools/{id}/sections`; cache keys declared in `06` §4 |
| Auto-join on verification | Server-side (`OnUserVerified`); the app only observes: verified user lands in the section group with topics subscribed — no client call |
| Push topics | expo-notifications device token registered by module 06; subscriptions mirror `fcm_topic_bindings` — no app work here |

## 5. Motion Spec

N/A — no UI in this module; picker transitions are module 03's motion table.

## 6. Responsive & Device Behaviour

N/A — no UI in this module. The picker screens that consume this data follow module 03's 360px-first
rules (one thumb, Bangla first).

## 7. Accessibility

N/A — no UI in this module. Contract obligation: bn + en names in every picker payload so module 03
screens announce the user's language correctly.

## 8. Offline Behaviour

None — requires connectivity. Picker reads need the API (cached responses soften 3G flakiness);
auto-grouping happens server-side at verification, so there is no client-queued hierarchy action.
Registration with a stale picker cache is module 03's concern; the server re-validates the chosen
section on submit.

## 9. Task Checklist

N/A — no `ORG-AP-*` items exist by design (README ID rules). App-side work tied to this module's
contract is tracked in module 03 (`IDT-AP-*` onboarding picker) and module 06 (`NTF-AP-*` push
topics); the Maestro golden path "onboarding → verified → auto-join section group → receive notice"
asserts this module's behaviour end-to-end.
