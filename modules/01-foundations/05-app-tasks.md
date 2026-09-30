# Foundations — App Tasks (Mobile)

**Module:** `01-foundations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

This module ships **no app screens** — only the app repo foundation (`FND-AP-001`, owner
instruction 2026-09-30). Fonts, tokens, icon/splash and primitives land with 02-design-system;
onboarding screens with 03-identity-access; EAS profiles with 15.

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

- [x] `FND-AP-001` — App repo scaffold in `applications/app` (own git repo, branch `module/01-foundations`): Expo SDK 57 + expo-router (`src/app`), React Native 0.86, TypeScript 6 strict, ESLint 10 flat with boundary rules + Prettier, jest-expo + Testing Library, `sync:api-spec` + `generate:api` (same client shape as web), `contracts:check`, zod env module (`EXPO_PUBLIC_API_URL`), expo-doctor, GitHub Actions gate (incl. Android bundle export); CNG — no committed `ios/`/`android/`; placeholder `/` (brand name only) — was 02 `DSN-AP-000` — 2026-09-30
