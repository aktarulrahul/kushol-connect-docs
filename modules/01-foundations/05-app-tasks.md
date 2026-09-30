# Foundations — App Tasks (Mobile)

**Module:** `01-foundations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

N/A file — this module ships **no app screens**. The Expo app scaffold (project shell, expo-router
setup, EAS config, fonts) lands with 02-design-system (primitives shell, icon/splash) and
03-identity-access (onboarding screens). This module works only in `applications/api`; the only
thing it hands the app is the api contract (`applications/api/openapi/openapi.yaml`). The app repo
scaffold and its generated client are 02's `DSN-AP-000`.

---

## 1. Screen Inventory

N/A — no routes. App routes (`/(tabs)/chat`, `/(tabs)/notices`, `/(tabs)/ai-hub`,
`/(tabs)/marketplace` + stack routes) are specified by their feature modules (05, 08, 10, 11).

## 2. Screen Breakdown

N/A — no screens; see §1.

## 3. Forms & Input

N/A — no forms; the app's own zod schemas (`src/schemas`) start with 03-identity-access onboarding.

## 4. Data Flow

N/A for screens; mechanism fixed here for later modules: TanStack Query → generated client → api;
realtime via the Go WebSocket gateway from 05-communication-engine.

## 5. Motion Spec

N/A — no UI motion; reduced-motion variant rule carries into every later module's spec.

## 6. Responsive & Device Behaviour

N/A — no screens; 360px-first, bn-first and low-end-Android/3G rules are binding from 02 onward.

## 7. Accessibility

N/A — no screens; on-device bn/en verification starts with 02/03 builds.

## 8. Offline Behaviour

None — requires connectivity (infrastructure module, no app surface). Offline queue patterns are
specified per feature module (e.g. 05-communication-engine chat queue).

## 9. Task Checklist

- None — no AP tasks. The app repo scaffold, client generation and app CI are 02's `DSN-AP-000`
  (EAS hooks added by 02/03).
