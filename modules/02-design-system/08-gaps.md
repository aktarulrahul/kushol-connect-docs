# Design System — Gaps

**Module:** `02-design-system` · **Last updated:** 2026-10-01

Genuine remaining gaps only (reason · impact · next action).

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Logo vectors missing | Owner action (02 Q1, `docs/design-reference/brand/README.md`) | `<Logo/>`, splash and app icons use the supplied PNG (trimmed; icon swirl cut from it) — soft at very large sizes; production release needs vectors | Owner supplies `logo-lockup.svg`, `logo-monogram.svg`, `logo-lockup-knockout.svg`; swap the files behind `<Logo/>` (web `src/assets/brand`, app `assets/brand`) and regenerate icons — one commit per repo |
| G-2 | Status colours (success/warning/danger/info) are proposed, not in the design reference | Reference §2 lists brand colours only | Badges, toasts, alerts and table states may shift if the owner picks other values | Owner confirms or replaces the four values in `status` (both `src/theme/tokens.ts`); contrast tests re-check them |
| G-3 | Web font payload 199 KB preloaded vs ~150 KB budget (`verify`) | Four Hind Siliguri weights (≈ 39 KB each) + Inter variable | Slower first paint on 3G for the landing page | Decide with 07's CWV run: keep (Bangla typography quality), or drop weight 500/700 (faux or fallback weights in Bengali) |
| G-4 | App E2E (Maestro) not run | Maestro CLI not installed on the dev Mac; CI job comes with 15 | `DSN-E2E-001` (app) proven only by jest + manual Simulator check | Install Maestro (owner/CI), run `maestro test .maestro/design-system-smoke.yaml` against the dev build |
| G-5 | `DSN-AP-017` 360px low-end Android pass not done | No Android emulator/device (01 G-6) | Android rendering of Hind Siliguri, NativeWind and primitives unverified; iOS + jest (360pt metrics) only | With 03, on an Android emulator or a low-end phone: run the UI kit in bn and en, record screenshots here |
| G-6 | Notification small icon generated but not wired | `expo-notifications` arrives with 06 | Android would show the default icon for push | 06 adds the `expo-notifications` plugin with `icon: ./assets/brand/notification-icon.png` and colour `teal-800` |
| G-7 | Splash "one-time reveal on first launch" read as once per cold start | No persistent storage yet (MMKV with 03/05) | Reveal (≤ 900ms) plays on every cold start | Owner confirms the reading, or 03 stores a "seen" flag and `SplashReveal` checks it |
| G-8 | Language choice is not persisted; web SSR is always bn | Persistence is 03's (`DSN-BR-003`) | An English user sees bn first on reload (web) / app restart | 03 saves the choice per user and seeds `LocaleProvider` (cookie or route on web) |
| G-9 | App on NativeWind 4 / Tailwind 3 while web is Tailwind 4 | NativeWind 5 (Tailwind 4) is still a release candidate | Two Tailwind dialects; token values are shared by code, not by config | Re-evaluate when NativeWind 5 is stable; migration is config + class renames, tokens unchanged |
