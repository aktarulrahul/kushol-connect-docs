# Design System — Technical Document

**Module:** `02-design-system` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Compresses spec files `01`–`06` in this folder; when it drifts, the specs win.

---

## 1. Overview

### 1.1 Purpose

Turns the binding brand (`docs/design-reference/README.md`, `prompt.txt` §6) into the product's
**visual API**: semantic design tokens, bilingual bn/en string catalogs, hand-written UI
primitives for web (shadcn-style) and mobile (NativeWind), and the app icon/splash derived from
the logo. Every later module builds screens only from these parts so the super app reads as one
trustworthy, Bengali-first product — the trust objective in `brd.md` §2 (detail in
`01-user-stories.md` §1).

### 1.2 Scope

**In:** semantic tokens in each app's `src/theme` (deep-teal 10-step scale, paper/ink neutrals,
spacing, radius, type scale, motion) → Tailwind v4 `@theme` (web) + NativeWind (app); fonts Hind
Siliguri + Inter (`next/font/google` web, bundled `@expo-google-fonts` app) · bn/en string
catalogs (**this module OWNS the catalogs**): dot-namespaced keys, `t(key, params)`, CI parity
gate · web primitives (`src/components/ui/`: Button, Input/Textarea, Select, Checkbox/Radio/
Switch, Card, Dialog/Sheet, Toast, Tabs, Badge, Table shell, Skeleton, EmptyState, Avatar, Logo)
+ RN mirrors · app icon (adaptive), splash, notification small icon via EAS config · light theme
first (WCAG 2.2 AA, both languages), dark optional later.

**Out:** any feature screen (03/05/07/08/10/11 own those) · server code of any kind — **no
database tables and no endpoints** · producing logo vector files (owner action; fallback = OQ-1) ·
copywriting of feature strings (each module authors its keys) · illustration system · dark theme
implementation.

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01-foundations | api contract + problem code registry only (`applications/api/openapi/openapi.yaml`). 01 ships **no** web/app scaffolding — 02 scaffolds web and app tooling itself (TS strict, ESLint 10, Vitest/jest-expo, per-repo CI) |
| consumed by | 03–14 (all feature modules) | import from their own app's `src/theme` (tokens), `src/i18n` (`t()`) and primitive folders; `03-identity-access` consumes first |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| web + app (per app) | `src/theme` token module + `src/i18n/bn.json` + `en.json` + typed `t()`, inside each of web and app | each app owns its copy; values pinned to `docs/design-reference/README.md` | catalogs + tokens are code/config, not data |
| web | Next.js App Router · Tailwind v4 `@theme` · shadcn-style hand-written primitives on Radix · `next/font/google` · lucide-react | token control + bn-first sizing baked in (`02-solution-approach.md` §10) | zero runtime CSS-in-JS |
| app | Expo SDK · React Native · NativeWind · `@expo-google-fonts` · radix-primitives/zeego · lucide-react-native | one token language across platforms | fonts bundled in the binary |
| api | None — no server code in this module (`03-backend-tasks.md` is all N/A by design) | — | — |
| tooling | ESLint token-only rule · Vitest + Testing Library · jest-expo · Playwright + Maestro (E2E smoke) | CI-enforced compliance (`DSN-INT-002`, `DSN-UT-001…004`) | versions pinned (`tech-stack.md`) |

---

## 3. Architecture

### 3.1 Component diagram

```text
docs/design-reference (brand truth — palette, fonts, logo rules)
        │ encoded as
        ▼
applications/web (own repo)                         applications/app (own repo)
├─ src/theme tokens ──► Tailwind @theme             ├─ src/theme tokens ──► NativeWind theme
│    ──► src/components/ui/* ──► screens (07+)      │    ──► RN primitives ──► screens (03/05/08/10/11)
└─ src/i18n bn/en ──► t(key, params)                └─ src/i18n bn/en ──► t(key, params)
   (CI parity gate DSN-UT-001 in each repo; token values pinned to the reference by DSN-UT-005)

brand assets (logo lockup/monogram, icon, splash, notification icon)
        └─► <Logo/> component · app.json / EAS config
```

### 3.2 Boundary

**Owns (tables / services):** each app's `src/theme` tokens + `src/i18n` catalogs + `t()` + catalog CI tests ·
`applications/web` `@theme` wiring, fonts, `src/components/ui/*` · `applications/app` NativeWind
config, bundled fonts, RN primitives, icon/splash EAS config. **No database tables** — data-model
ownership stays with 01 (audit_log, jobs), 03, 04, 05, 06 per `docs/modules/README.md`.

**Reads (via exported service functions only):** `01-foundations` — the api contract and problem
code registry only; 02 scaffolds the web and app repos' tooling itself. No server data crosses this boundary.

### 3.3 Request / data flows

```text
1. Tokens        src/theme token defs → build-time import → web @theme CSS custom properties
                 | NativeWind config preset → compiled styles. No runtime fetches.
2. Strings       static catalog import (both locales bundled) → t(key, params) → localized string.
                 Fallback: requested locale → bn → key literal + dev warning; never throws.
3. Fonts (web)   next/font/google downloads + self-hosts subset woff2 at build (bengali + latin);
                 build fails loudly on fetch failure. Escape hatch: partner the woff2.
4. Fonts (app)   @expo-google-fonts bundled in the binary; root font gate holds native splash until
                 useFonts resolves — never an unstyled first frame.
5. Locale toggle LocaleProvider updates strings + <html lang> (web) / Intl locale; layout unchanged.
```

No server request path exists — module 02 makes no API calls; consumers use the generated
OpenAPI client (`01-foundations`).

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| Catalog string key | drafted · shipped · deprecated · removed | drafted → shipped (bn + en added in the same commit, `DSN-UT-001`) · shipped → deprecated (replacement key named in the PR; old key kept ≥ 1 release) · deprecated → removed (lint: zero references remain) |
| Token / primitive prop | — | additive-first; breaking changes need an ADR note in `07-progress.md` (`06-integration-tasks.md` §7) |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| None — module 02 owns zero tables | design tokens, string catalogs and UI primitives are code/config inside each app (`src/theme`, `src/i18n`, `src/components`) | N/A — no tenant data exists here | N/A | closest equivalent to seed data is the catalog seed strings (each app's `src/i18n/bn.json`/`en.json`), specified in `03-backend-tasks.md` §2; illustrative copy stays clearly fictional |

---

## 5. Contracts

### 5.1 REST endpoints

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| None — no endpoints exist; no `DSN-BE` items. The module's real contract is the **catalog JSON schema** (`03-backend-tasks.md` §2): flat `key → {bn, en}` map, dot-namespaced under `common · validation · errors · auth · verification · hierarchy · chat · notices · notifications · settings · landing · admin · school · partner · ai · analytics · tuition · marketplace · commerce · payments · ads · events · sync · ops`, identical key sets and `{param}` placeholders in both files — CI-gated | — | — | — | — | — |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| None — no backend jobs; catalog/token checks run as CI steps, never scheduled jobs | — | — | — | — |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| Tokens (semantic: color/space/radius/type/motion) | every FE/AP task in 03+ | token values / CSS vars / NativeWind theme | build-time only — the only colour/size source (`DSN-BR-002`) |
| `t(key: CatalogKey, params?): string` | every user-facing string | localized string | never — fallback requested locale → bn → key literal |
| Catalogs `bn.json` / `en.json` | `t()`; 03 language UI | JSON per `03-backend-tasks.md` §2 | CI fails on parity breach (`DSN-UT-001`) |
| Web primitives (`src/components/ui/*`) | 03, 07, later FE modules | React components, minimal documented props | — |
| RN primitives | 03, 05, 08, 10, 11 | RN components mirroring the web inventory | — |
| `<Logo/>` + app icon / splash / notification icon | headers, landing (07), app config | component + EAS assets | build fails if an asset is missing |

Exports are typed and DTO-like (no app-internal types leak); renames go deprecate → remove.

---

## 6. Client Surfaces

This module owns **no routed screens** — tokens, catalogs and primitives **are the surface** every
route of 03–14 is composed from (`DSN-BR-002` consumption rule).

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| N/A routes — owned surface: root layout (`app/layout.tsx`): `<html lang>` bn default, Hind Siliguri + Inter subsets, `@theme` bridge, `LocaleProvider` | Foundation wiring (not a screen) | Server (build) + client `LocaleProvider` | all consumers |
| N/A routes — owned surface: `src/components/ui/*` (Button, Input/Textarea, Select, Checkbox/Radio/Switch, Card, Dialog/Sheet, Toast, Tabs, Badge+verified, Table shell, Skeleton, EmptyState, Avatar+verified, `Logo`) | 14 primitives, a11y-complete, bn +30% fixtures | Server-safe where possible; interactive ones Client | consumed by 03/07/11/13 |
| Consumers: `/` + `/download`, `/login`, `/admin/*`, `/school/*`, `/partner/*` | owned by 07/03/11/13 — composed only from these primitives | — | Public + all roles |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `app/_layout` (root — owned here) | Provider stack: fonts → theme → locale; splash gate (one-time ≤ 900ms reveal, static under reduced motion) | none | fully offline-capable: fonts/tokens/catalogs bundled at install |
| N/A routed screens — owned surface: RN primitives mirroring §6.1 (Button ≥ 44pt, Input keyboard-aware, Select via zeego, Card, Dialog/bottom Sheet, Toast safe-area, Tabs, Badge, Skeleton, EmptyState, Avatar, Icon wrapper; Table shell N/A on RN — FlatList patterns owned by feature modules) | — | push/deep links are consumer-module concerns (05/06/08/10/11) | N/A for primitives; queues are feature concerns (`05-communication-engine.md` §8) |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Google Fonts (web) | Hind Siliguri `bengali` + Inter `latin` subset woff2, self-hosted at build | HTTPS, build-time only (`next/font/google`) | none (public) | build timeout; CI retry | fallback stack `"Hind Siliguri", "Noto Sans Bengali", system` / Inter → system-ui; escape hatch: partner the woff2 |
| Google Fonts (app) | fonts bundled via `@expo-google-fonts` packages | npm install | none | pnpm install retry | fonts in the binary — no runtime failure path |
| npm: radix / zeego / lucide / @expo-google-fonts | primitive heads + icons + font packages | npm, pinned | none | install-time failure — CI blocks | — |

FCM · R2 · DeepSeek · SMS · payment gateways: **N/A — none touched by this module**
(`06-integration-tasks.md` §5).

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None — module 02 reads no environment variables; tokens, fonts and catalogs are bundled code/config | — | — | — |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Nothing at launch — module 02 ships no admin surface; per-user language selection arrives with `03-identity-access` onboarding | palette + generated scales · font families/subsets · spacing/radius/type scales · motion durations/easings · namespace whitelist · fallback chain (requested locale → bn → key) · light theme |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | N/A — no entry points, no auth middleware; the five roles + partners are defined by 03; this module serves every role identically and owns no permissions |
| Role matrix | N/A — no permissions owned |
| Tenant scope | N/A — no tables, no tenant data (`03-backend-tasks.md` §1 is all N/A) |
| Rate limits | N/A — no routes |
| Audit events | none — no server actions to audit |
| Privacy / minors | downstream properties: primitives render strings as plain text (never `dangerouslySetInnerHTML`) so feature screens inherit XSS-safe rendering; `src/theme`/`src/i18n` ship no secrets; web fonts fetched at build via `next/font` and self-hosted — never from a runtime endpoint |

---

## 10. Error Handling

No API errors exist (no endpoints). The module's failure modes and client-visible behaviour:

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `common.language.unsupported` | locale not `bn`/`en` | invalid locale value resolves to `bn` (dev-facing warning) | bn renders; never a crash |
| missing catalog key | key absent at runtime | any `t()` call on an unshipped key | fallback requested locale → bn → key literal + dev warning; CI parity gate prevents recurrence |
| catalog parity breach | bn/en key sets, placeholders or values diverge | CI build (`DSN-UT-001`) — never runtime | merge blocked; fix the catalog |
| token-only lint breach | raw hex/px/font-family in feature code | CI build (`DSN-INT-002`) | import the semantic token |
| missing logo asset | asset absent/corrupt | build fails on import | a blank header can never ship |

Seam convention fixed for all consumers: server error codes map to `validation.*`/`errors.*`
catalog keys resolved by `t()` before display; all user-visible messages ship in **bn + en**
(bn default) via each app's `src/i18n` catalogs (`06-integration-tasks.md` §6).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | none of its own — no server code; failures surface as CI errors (font fetch, parity, lint, render tests) |
| Metrics / counters | none — no data produced; 07/09 dashboards consume these primitives/tokens when they render reports (02 §8) |
| Health contribution | none — no runtime dependency; contributes no `/readyz` probe |
| Jobs & retries | none — catalog/token checks are CI steps; failures block merge, recovery is fix-and-push |
| Runbook pointers | font-fetch outage: retry CI or partner subset woff2 (`02-solution-approach.md` §8); NativeWind/Tailwind mismatch caught by pinned versions + `DSN-IT-002` smoke; catalog lifecycle (deprecate ≥ 1 release) in `02-solution-approach.md` §3 |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | catalog parity (schema, key sets, placeholders, namespace whitelist) · `t()` fallback safety · web primitive render/a11y fixtures (focus/pressed/disabled, bn +30%, accessible names) · RN primitive render fixtures (jest-expo) | `DSN-UT-001…004` | green in CI |
| Integration | token-usage lint over web + app (no raw hex/px/font-family) · apps render themed + localized end-to-end (Next build smoke; app root render) | `DSN-IT-001…002` | CI lint + smoke gate |
| E2E | bn default renders + en toggle works on web (Playwright) and app (Maestro); reduced-motion static splash checked | `DSN-E2E-001` | CI |
| CI | per-repo quality gate in web and in app, set up by this module (`pnpm lint/typecheck/test/build`) + parity/token gates | — | required checks |

The generic server-test requirements (unauthenticated denied, `TENANT_MISMATCH`, publish guards)
are N/A — no entry points exist; the parity + fallback gates are this module's mandatory gates.

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | n/a — build-time artifacts; every screen of 03–14 is the consumer |
| Hot paths + indexes | n/a — no database, no queries |
| Latency targets | app cold start: fonts from the binary; splash held only until `useFonts` resolves — no network on first launch |
| Bundle / payload impact | subset woff2 (`bengali` + `latin`), `display: swap`; both families together ≤ ~150KB budgeted, measured at build (`verify`) · Radix/zeego + lucide tree-shake per component · catalogs are one JSON pair shared by both apps · no runtime CSS-in-JS anywhere |
| Caching | none server-side — web tokens/catalogs ship as content-hashed rebuilt bundles; CWV landing budgets asserted by 07's Playwright runs on this foundation |

---

## 14. Risks & Open Questions

Consolidated from `01-user-stories.md` §9 and `02-solution-approach.md` §11 — reviewed at module
readiness checks; unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Logo vector files (SVG/AI) for production icon/splash/web use | icon/splash stay on PNG fallback | Rahul | Open | typographic fallback wordmark "কুশল CONNECT" + supplied PNG for mockups; recorded as a gap until vectors arrive |
| 2 | Exact paper/ink hex values (proposed, not sampled from the PNG) | brand colours shift | Rahul | Open | use proposed `#FAFBFC` paper / `#111827`-scale ink; confirm ≥ 4.5:1 contrast; re-verify against the SVG when supplied |
| 3 | Dark theme scope at launch | deferred work | Rahul | Open | light theme only at launch; tokens are theme-able so dark is additive later |
| 4 | Vector logo arrives before production release | soft branding at some sizes | Rahul | Assumption | `<Logo/>` + EAS assets make the swap a one-commit change |
| 5 | Sampled palette matches the final SVG (`verify` note until then) | single-file token update | Rahul | Assumption | all colour flows through tokens |
| 6 | Hind Siliguri covers the launch Bengali corpus incl. Bengali numerals ০–৯ | rare glyphs fall back | Rahul | Assumption | specimen tests `DSN-UT-003/004`; system-Bengali fallback stack (`DSN-BR-004`) |
| 7 | bn strings stay ≤ +30% vs en | overflow in tight controls | Rahul | Assumption | primitives sized bn-first; fixtures at +30% |
| 8 | NativeWind stays compatible with the pinned Tailwind version | styling breaks on upgrade | Rahul | Assumption | version pins + `DSN-IT-002` smoke |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| `DSN-BR-001` bn/en catalog parity · `DSN-BR-003` bn default | prd §4A/§4B; prompt §2(6), §12 | DSN-US-004 | DSN-INT-001, DSN-FE-004, DSN-AP-003 | DSN-UT-001/002, DSN-E2E-001 |
| `DSN-BR-002` tokens only, no raw hex/px · `DSN-BR-005` palette from brand tokens | design-reference §2 | DSN-US-001/002 | DSN-INT-002, DSN-FE-001/002, DSN-AP-001 | DSN-IT-001 |
| `DSN-BR-004` Bengali never in Inter | design-reference §3 | DSN-US-003 | DSN-FE-003, DSN-AP-002 | DSN-UT-003/004 |
| `DSN-BR-006` logo via `<Logo/>` only | design-reference §5 | DSN-US-007 | DSN-FE-017, DSN-AP-016 | DSN-IT-002, DSN-E2E-001 |
| `DSN-BR-007` reduced motion everywhere | design-reference §5 | DSN-US-006 | DSN-FE-005…018, DSN-AP-004…017 | DSN-UT-003/004, DSN-E2E-001 |
| — (all stories) | prompt §6; persona | DSN-US-001…007 | DSN-FE-001…018 · DSN-AP-001…017 · DSN-INT-001…003 | DSN-UT-001…004 · DSN-IT-001…002 · DSN-E2E-001 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Namespace whitelist replaced by a 24-namespace registry (`02` §1.1) — later modules already used namespaces outside the original eight; CircleUp mobile primitives (`DSN-AP-018`) and professional web primitives (`DSN-FE-019`) added per owner UI direction (`docs/design-reference/README.md` §6–§7) | Claude |
| 2026-09-30 | Isolated applications (owner): no `packages/shared` — web and app each own `src/theme`, `src/i18n`, `src/schemas`, `src/api`; 02 now scaffolds both repos (`DSN-FE-000`, `DSN-AP-000`); token reference pin `DSN-UT-005`; drift risk recorded | Claude |
| 2026-09-30 | Web/app repo scaffolds (`DSN-FE-000`, `DSN-AP-000`) delivered by 01 as `FND-FE-001`/`FND-AP-001` (owner instruction); 02 starts from those repos: tokens, fonts, catalogs, primitives, icon/splash | Claude |
