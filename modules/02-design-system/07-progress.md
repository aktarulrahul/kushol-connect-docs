# Design System — Build Progress

**Module:** `02-design-system` · **Apps:** `web` · `app` (`api`: none — `03-backend-tasks.md` is all
N/A by design) · **Repos:** `applications/web`, `applications/app`, nothing committed by the build · **Last updated:** 2026-10-15

Owner instruction (2026-10-01): "complete the app, web, api till 02-design-system", then "use shadcn,
react query, react table in admin table", "use tailwind and react query as well in mobile app" and
"for both app and web, create all common component like button, typography, tables, menu, select,
textfields, input, badge, all kind of popup, toast, card, etc". Built against 01, which is still 🚧
(its Gates 2/3 wait on the owner) — the owner's instruction is taken as acceptance (`prompt-build.md`
§2).

## Stages & gates

| Stage / gate | Status | Date | Notes |
| --- | --- | --- | --- |
| 1 · Read & plan | ✅ (pre-approved by the instruction) | 2026-10-01 | Plan given in chat; owner then added shadcn, TanStack Query/Table and the full common-component set |
| 2 · UI build | ✅ | 2026-10-01 | Tokens, fonts, catalogs, primitives web + app; dev-only UI kits for review |
| Gate 1 · UI approval | ✅ owner | 2026-10-15 | Owner approved in session ("complete all from Gate 1"); review steps below were the submission |
| 3 · Docs sync | ✅ | 2026-10-15 | Checklists ticked (`DSN-FE-001…019`, `DSN-AP-001…016/018`, `DSN-UT/IT/INT` items); `DSN-AP-017` + app `DSN-E2E-001` stay open (device runs — G-4/G-5) |
| 4 · Backend build | N/A | — | No `DSN-BE` items, no tables, no endpoints |
| Gate 2 · SQL run | N/A | — | No migrations |
| 5 · Integration | ✅ CI gates in both repos | 2026-10-01 | `DSN-INT-001/002` done; `DSN-INT-003` = 03 consuming first |
| Gate 3 · integrated flows | ⏳ after Gate 1 | — | Web E2E green; app Maestro flow written (not run — G-4) |
| 6 · Gaps & verification | ✅ `08-gaps.md` written · final verification ⏳ owner | 2026-10-01 | |

## Owner decisions and build decisions (ADRs)

| # | Decision | Effect |
| --- | --- | --- |
| ADR-1 | **shadcn/ui for web** (owner) | `pnpm dlx shadcn@4.21.0 add …` (Radix base, `nova` style): 49 components vendored in `src/components/ui/`, themed by our tokens through shadcn's variable names. Tuned for 02: solid 2px focus ring (shadcn's 50% ring measured ≈ 2.1:1, below WCAG 1.4.11's 3:1), Button `min-h` + wrapping labels (bn +30%), Card radius 8px (design-reference §7.1), every hard-coded English string → `t()`, light theme only |
| ADR-2 | **TanStack Table + TanStack Query in the admin table** (owner) | `DataTable` = shadcn Table + TanStack Table **v9.2.4** (`useTable`, feature registry) — sort, global search, pagination, row selection + bulk-action bar, density toggle; `query` prop switches to server mode (TanStack Query **5.104.0**: every slice in the query key, `keepPreviousData`) |
| ADR-3 | **Tailwind + TanStack Query in the app** (owner) | NativeWind **4.2.7** on Tailwind **3.4.19** (NativeWind 5 — the Tailwind 4 line — is still `5.0.0-rc.0`); theme built only from `src/theme/tokens.ts`; TanStack Query in the root layout (dev card uses `useQuery`) |
| ADR-4 | **React Native Reusables** for app primitives (shadcn for RN, on `@rn-primitives` 1.5.x — the "radix-primitives" of the tech stack) | 32 components vendored; every text-rendering primitive routed through our `Text` (fonts), `leading-none` removed (clips Bengali matras), controls resized to ≥ 44pt targets, `dark:` inert |
| ADR-5 | Catalog shape = **two files** `bn.json` / `en.json`, flat `key → string` | `prompt.txt` §1 outranks the combined `{bn,en}` example in 02 `03` §2 (§1.1 precedence). Keys follow the registry regex (lower snake_case), so `common.app_name`, not the `common.appName` example |
| ADR-6 | Tokens generated in code | Five reference colours → OKLCH 50–950 scales (Tailwind's lightness rhythm); deep teal pinned at `teal-800`, ink at `neutral-900`; identical generator in both repos; status colours **proposed** (`TODO: Confirm`, G-2) |
| ADR-7 | Fonts | Web: `next/font` Hind Siliguri (bengali subset, 400/500/600/700) + Inter (latin); Latin always from Inter — preloaded payload 230 → **199 KB** (G-3). App: 8 bundled faces; `Text` picks the face by script (any Bengali → Hind Siliguri) and weight class (Android can't synthesise weights) |
| ADR-8 | Contrast-safe UI boundaries | `input` border = `neutral-500`, `ring` = `teal-700`: ≥ 3:1 on every surface (test-enforced) |
| ADR-9 | Splash reveal plays **once per cold start** (≤ 900ms, skipped under reduced motion) | "first launch" read as cold launch until 03/05 bring persistent storage — `TODO: Confirm` (G-7) |
| ADR-10 | App icon set from the supplied PNG | Swirl separated by connected-component analysis of the PNG's alpha (no redraw/recolour); iOS icon on paper, adaptive foreground + monochrome, white notification silhouette — interim until vectors (G-1) |
| ADR-11 | Dev-only UI kits for Gate 1 | Web `/dev/ui` (+ `/admin`, `/landing`) returns 404 in production builds (E2E-tested); app `/dev/ui` redirects outside `__DEV__` |
| ADR-12 | Token-only lint (`DSN-INT-002`) | Local ESLint rule in each repo (`eslint-rules/design-tokens.mjs`): raw hex/rgb/oklch, Tailwind arbitrary colours/lengths, font-family literals and numeric spacing in style objects fail outside `src/theme` and `src/components/ui`. Vendored component folders relax only 3 stylistic strict rules |

## Defaults relied on

| Item | Default |
| --- | --- |
| 02 Q1 logo vectors | Supplied PNG (trimmed) through `<Logo/>`; icons cut from it (G-1) |
| 02 Q2 paper / ink | Proposed `#FAFBFC` / `#111827`, contrast-tested |
| 02 Q3 dark theme | Light only; `dark:` classes inert on both platforms, OS dark mode ignored |
| Language persistence | Mechanism only (03 persists per user) — G-8 |

## Pinned versions (verified 2026-10-01)

| Repo | Package | Version |
| --- | --- | --- |
| web | shadcn (CLI, dev) · cn · radix-ui · class-variance-authority · lucide-react | 4.21.0 · 0.4.0 · 1.6.7 · 0.7.1 · 1.49.0 |
| web | @tanstack/react-table · @tanstack/react-query · sonner · vaul · cmdk · input-otp · react-day-picker · date-fns · tw-animate-css (dev) | 9.2.4 · 5.104.0 · 2.0.8 · 1.1.2 · 1.1.1 · 1.5.0 · 10.0.1 · 4.4.0 · 1.4.0 |
| app | nativewind · tailwindcss (dev) · tailwindcss-animate · @rn-primitives/* · @rn-primitives/portal | 4.2.7 · 3.4.19 · 1.0.7 · 1.5.2 · 1.5.3 |
| app | react-native-reanimated · react-native-worklets · react-native-svg · expo-font · expo-splash-screen (Expo 57 pins) | 4.5.1 · 0.10.1 · 15.15.4 · 57.0.4 · 57.0.9 |
| app | @expo-google-fonts/hind-siliguri · @expo-google-fonts/inter · lucide-react-native · @tanstack/react-query · clsx · tailwind-merge | 0.4.1 · 0.4.2 · 1.49.0 · 5.104.0 · 2.1.1 · 2.6.1 |

## Evidence (2026-10-01)

| Repo | Check | Result |
| --- | --- | --- |
| web | `pnpm format:check` · `lint` · `typecheck` · `contracts:check` | all clean; `contracts: no drift` |
| web | `pnpm test` (Vitest) | **80/80** — catalog parity (`DSN-UT-001`), `t()` fallback (`DSN-UT-002`), primitives + DataTable incl. TanStack Query server mode and axe on composed primitives (`DSN-UT-003`), token pins + theme.css drift + contrast (`DSN-UT-005`, `DSN-FE-018`), lint-rule RuleTester (`DSN-IT-001`) |
| web | `pnpm build` + `pnpm test:e2e` (1280px + 768px) | static `/`; **4/4** — bn default, en toggle (`lang`, Inter stack), axe 0 serious/critical in both languages, `/dev/ui` 404 (`DSN-E2E-001` web) |
| web | Font payload | 19 self-hosted woff2; **199 KB preloaded** (budget ~150 KB `verify` — G-3) |
| web | Browser review (dev) | `/dev/ui`, `/dev/ui/admin` (bn + en), `/dev/ui/landing` at 1280px, `/` at 768px; dialogs, confirm, toggle, DataTable server mode checked by hand; one duplicate-key warning and the destructive-confirm colour fixed |
| app | `pnpm format:check` · `lint` · `typecheck` · `contracts:check` · `doctor` | all clean; expo-doctor 21/21 |
| app | `pnpm test` (jest-expo) | **67/67** — parity, fallback, token pins + NativeWind theme + contrast, font selection, RN primitives on a 360pt phone in bn/en (`DSN-UT-004`), holding-screen render + toggle (`DSN-IT-002`) |
| app | `pnpm test:rules` | **10/10** RuleTester cases (`DSN-IT-001`) |

## Gate 1 — how to review

1. **Web:** `cd applications/web && pnpm dev` → open http://localhost:4433/dev/ui (all components;
   toggle বাংলা/English top-right), `/dev/ui/admin` (AdminShell + KPIs + TanStack Query table — try
   search, sort, select rows, density, pages), `/dev/ui/landing` (hero + sections). Narrow the
   window below 640px to see dialogs become bottom sheets and toasts move to the bottom.
2. **App:** build/open the dev client (`cd applications && ./dev-start.sh`, or `cd app && pnpm ios`)
   → holding screen → **Open UI kit**. Try the language pill, buttons (long Bangla label), forms
   (blur the empty name field), OTP, bottom sheet, delete confirm, toasts, dropdown, tabs.
3. **Reduced motion:** turn on Reduce Motion (macOS / iOS settings) — splash shows a static logo,
   skeletons stop pulsing, sheets/toasts appear without sliding.

## Checklist status

Ticked after Gate 1 (Stage 3). Built: `DSN-FE-001…019`, `DSN-AP-001…015`, `DSN-AP-016` (icon/splash;
notification icon asset only — G-6), `DSN-AP-018`, `DSN-INT-001/002`, `DSN-UT-001…005`,
`DSN-IT-001/002`, `DSN-E2E-001` (web). Open: `DSN-AP-017` (360px low-end Android pass — G-5),
`DSN-E2E-001` (app via Maestro — G-4), `DSN-INT-003` (03 consumes first).
