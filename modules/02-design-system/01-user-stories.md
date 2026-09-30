# Design System — User Stories

**Module:** `02-design-system`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Module 02 turns the binding brand (`docs/design-reference/README.md`, `prompt.txt` §6) into the product's **visual API**: semantic design tokens, bilingual bn/en string catalogs, hand-written UI primitives for web (shadcn-style) and mobile (NativeWind), and the app icon/splash derived from the logo. Every later module builds screens only from these parts, so the super app reads as one trustworthy, organised, Bengali-first product — the trust objective in `brd.md` §2 and the bilingual-first standard in `docs/persona.md`.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Student (end user) | Uses themed screens; Bangla default, English opt-in; 360px low-end Android renders and fits Bangla type |
| Guardian | Judges trust signals (verified badge, school branding) built from these primitives |
| Teacher | Reads Bangla-heavy content in Hind Siliguri — no tofu, no clipped conjuncts |
| School/Super Admin (web) | Command Center screens (dense tables, keyboard-complete forms) from these primitives |
| Vendor / EdTech brand | Meets the brand via the landing page (`07-command-center-web`) built on these tokens |
| Developer (web + mobile) | Imports tokens and primitives only — raw hex/px/font names are lint-blocked |
| Designer | Reviews primitives against the brand; exercises reduced-motion and bn-length variants |
| System (CI) | Enforces catalog bn/en parity, token-only lint, font bundling, render tests |

The five roles plus Vendors are defined by `03-identity-access §2`; verification gating is unaffected here — this module serves every role identically and owns no permissions.

## 3. Scope

**In scope**

- Semantic design tokens in each app's `src/theme` — color (deep-teal 10-step scale, paper/ink neutrals), spacing, radius, type scale, motion — consumed by Tailwind v4 `@theme` (web) and NativeWind (app); fonts Hind Siliguri + Inter via `next/font/google` (web) and bundled `@expo-google-fonts` (app)
- bn/en string catalogs in each app's `src/i18n` (**this module OWNS the catalogs**): dot-namespaced keys, `t(key, params)` helper, CI key-parity gate
- Web primitives (shadcn-style, hand-written in `src/components/ui/`): Button, Input, Textarea, Select, Checkbox/Radio/Switch, Card, Dialog/Sheet, Toast, Tabs, Badge, Table shell, Skeleton, EmptyState, Avatar (verified-badge variant); RN mirrors (NativeWind + radix-primitives/zeego where useful)
- App icon (adaptive), splash and notification small icon from brand assets (EAS config); light theme first (WCAG 2.2 AA, both languages), dark optional later

**Out of scope** (explicit — prevents scope drift)

- Any feature screen — owned by `03-identity-access`, `05-communication-engine`, `07-command-center-web`, `08-ai-study-hub`, `10-tuition-marketplace`, `11-campus-commerce`
- Server code of any kind — module 02 owns **no database tables and no endpoints**; tokens, catalogs and components are code/config
- Producing logo vector files (owner action — `docs/design-reference/brand/README.md`; fallback is Open Question 1) · copywriting of feature strings (each module authors its keys) · illustration system · dark theme implementation

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| `01-foundations` | api contract + problem code registry only (`applications/api/openapi/openapi.yaml`). 01 ships **no** web/app scaffolding — 02 scaffolds web and app tooling itself (TS strict, ESLint 10, Vitest/jest-expo, per-repo CI) |

---

## 4. User Stories

### `DSN-US-001` — One product across web, app, Bangla and English

**Priority:** P0 · **Traces:** `prompt.txt` §6 · `docs/design-reference/README.md` §1–2 · prd.md §4A/§4B · **Depends on:** `01-foundations`

**Story** — As a **user of Kushol Connect (any role)**, I want **the web and the mobile app to look and feel like one product in both Bangla and English**, so that **I trust it as my school's official platform, not a bolted-together tool**.

**Acceptance criteria**

- **Given** a screen on web and its app counterpart, **when** compared, **then** both use the same semantic tokens (deep-teal primary, paper, ink, shared type scale) and the same component shapes.
- **Given** the same screen in bn and en, **when** the language toggles, **then** only the strings change — layout, hierarchy and brand stay identical.
- **Given** any role moving between landing, dashboard and app, **when** surfaces render, **then** none introduces a colour or font outside the token set (lint-enforced).

**Notes**

- The "one product" bar is exactly what principals judge before approving a rollout (`prompt.txt` §6).

### `DSN-US-002` — Developers import tokens only — no raw hex/px

**Priority:** P0 · **Traces:** `docs/design-reference/README.md` §2 · `docs/persona.md` (craft row) · **Depends on:** `01-foundations`

**Story** — As a **developer**, I want **feature code to import semantic tokens and primitives only**, so that **no raw hex, pixel or font name ships in features and re-theming is a one-file change**.

**Acceptance criteria**

- **Given** a PR adding a colour, **when** the token-only lint rule runs in CI, **then** raw hex/px/font-family outside each app's `src/theme` and the primitive folders fail the build.
- **Given** a token adjustment in each app's `src/theme` (e.g. re-verifying the palette against the SVG when supplied), **when** apps rebuild, **then** every consuming screen updates and no feature file changes.

**Notes**

- Rule is `DSN-BR-002`, implemented as `DSN-INT-002`.

### `DSN-US-003` — Bangla renders correctly at every text size, fast

**Priority:** P0 · **Traces:** `docs/design-reference/README.md` §3 · `docs/persona.md` (bilingual quality + performance rows) · **Depends on:** —

**Story** — As a **Bangla reader on a BDT-15k Android phone over 3G**, I want **Hind Siliguri to render every glyph correctly at every text size without costing me load time**, so that **reading notices and chat feels native and fast, not like a translated afterthought**.

**Acceptance criteria**

- **Given** a specimen corpus (conjuncts, vowel signs, Bengali numerals ০–৯, mixed bn/en lines), **when** rendered at caption→display sizes on web and app, **then** no tofu, no clipped matras/ascenders, no overlapping conjuncts.
- **Given** Bangla strings (~15–30% longer than English), **when** shown in buttons/labels/badges, **then** text wraps or the container grows — never truncates mid-glyph or overflows.
- **Given** any device/network, **when** the app or web first paints, **then** fonts render from the bundle (no font network fetch), subset woff2 with `display: swap` on web, and no runtime CSS-in-JS ships.

**Notes**

- Fixtures in `DSN-UT-003`/`DSN-UT-004` carry the specimen corpus; Inter never renders Bengali content (`DSN-BR-004`); CWV budgets asserted by `07-command-center-web`.

### `DSN-US-004` — Bengali default with complete bn/en catalogs

**Priority:** P0 · **Traces:** `prompt.txt` §2 (6), §12 · `brd.md` §2 (Goal 1) · **Depends on:** `DSN-US-001`

**Story** — As a **first-time user**, I want **the product to speak Bangla first with a clean English toggle**, so that **I can use it in the language I think in**.

**Acceptance criteria**

- **Given** a fresh launch before any account exists, **when** any screen renders, **then** copy is Bengali by default.
- **Given** a key missing from bn or en, **when** CI runs the parity test, **then** the build fails before merge; at runtime `t()` falls back requested locale → bn → key literal with a dev warning — never a crash or blank label.
- **Given** a user switches to English, **when** screens re-render, **then** `lang`/locale attributes update for screen readers and hyphenation.

**Notes**

- Per-user persistence is `03-identity-access` (settings); this module ships the mechanism. `DSN-E2E-001` proves bn default + en toggle on web and app.

### `DSN-US-005` — Primitives ship with a11y states and bilingual-ready layouts

**Priority:** P0 · **Traces:** `docs/persona.md` (craft row) · `docs/tech-stack.md` (web/app component rows) · **Depends on:** `DSN-US-001`

**Story** — As a **developer**, I want **every primitive to ship with focus/pressed/disabled states and layouts that survive bn strings ~15–30% longer**, so that **feature screens are accessible and Bangla-first without per-screen fixes**.

**Acceptance criteria**

- **Given** any interactive primitive, **when** rendered, **then** it defines focus-visible, pressed/hover, disabled and (where relevant) loading states styled from tokens.
- **Given** a primitive's render tests, **when** they run, **then** checks cover keyboard focus order, roles/labels and both en and bn fixture strings.
- **Given** Dialog/Sheet/Tabs/Toast with a screen reader, **when** opened or queued, **then** focus is trapped/moved and changes are announced (Radix/zeego behaviour).

**Notes**

- WCAG 2.2 AA in the light theme in both languages is an acceptance criterion, not a follow-up; axe runs on web in CI.

### `DSN-US-006` — Reduced motion removes all non-essential animation

**Priority:** P0 · **Traces:** `docs/design-reference/README.md` §5 · `docs/persona.md` (design every state) · **Depends on:** `DSN-US-001`

**Story** — As a **designer (and motion-sensitive user)**, I want **reduced-motion to remove all non-essential animation**, so that **the product stays comfortable and the brand rule (one-time ≤ 900ms splash reveal, otherwise static) holds everywhere**.

**Acceptance criteria**

- **Given** OS reduced-motion enabled, **when** any animation would play (press, sheet, toast, skeleton shimmer, splash reveal), **then** its static/instant variant renders instead; with motion on, durations/easings come from motion tokens only.
- **Given** first launch with reduced motion, **when** the splash shows, **then** the logo appears static with no reveal animation.

**Notes**

- Every row in `04-frontend-tasks §5` and `05-app-tasks §5` carries an explicit reduced-motion variant.

### `DSN-US-007` — Branded app icon and splash from day one

**Priority:** P1 · **Traces:** prd.md §4B · `docs/design-reference/README.md` §4–5 · **Depends on:** `01-foundations`

**Story** — As a **student or guardian installing the app**, I want **the app icon and splash to carry the Kushol Connect brand**, so that **I recognise the official school platform on my home screen**.

**Acceptance criteria**

- **Given** an EAS build, **when** produced, **then** the adaptive Android icon, iOS icon, splash (paper background, centred lockup) and notification small icon derive from brand assets — not the default Expo icon.
- **Given** vector files are absent (Open Question 1), **when** mockups/builds proceed, **then** the typographic fallback wordmark "কুশল CONNECT" + supplied PNG are used and the gap is recorded; on first launch the splash dismisses once fonts load, without flashing unstyled content.

**Notes**

- Production release still awaits SVG/AI per `docs/design-reference/brand/README.md` (owner action).

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `DSN-BR-001` | Every user-facing string exists in bn AND en under a dot-namespaced key; a missing bn or en key fails CI | CI catalog parity test (`DSN-UT-001`) |
| `DSN-BR-002` | App/web feature code uses semantic tokens only — no raw hex/px/font-family outside each app's `src/theme` and the primitive folders | ESLint token-only rule (`DSN-INT-002`) + review |
| `DSN-BR-003` | Bengali is the default locale; English is user-selectable; the selection persists per user | `t()` default (`bn`) here; persistence owned by `03-identity-access` |
| `DSN-BR-004` | Bengali text renders in Hind Siliguri, never Inter; `lang="bn"`/`lang="en"` tags set correctly | Type tokens + locale provider; render fixtures |
| `DSN-BR-005` | Palette comes only from the sampled brand tokens — deep teal `#095777`, slate teal `#386070`, swoosh gray `#707070` (brand graphic only, never UI text), paper, ink; verify against the SVG when supplied | Tokens module; `DSN-BR-002` lint |
| `DSN-BR-006` | Logo lockup: never recoloured, stretched, re-spaced or split below 20px; clear space ≥ ¼ swirl height; only a one-time ≤ 900ms reveal, static under reduced motion; accessible name "Kushol Connect — Home" | `<Logo/>` component; `docs/design-reference/README.md` §5 |
| `DSN-BR-007` | Reduced motion removes all non-essential animation everywhere | Motion tokens + primitives; `DSN-US-006` tests |

Content accuracy (`prompt.txt` §12): palette/typography facts here are sampled or bundled, not invented — the PNG-sampled values carry an explicit `verify` note pending vector files, and this module publishes no seeded content.

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| Catalog key name | Matches `^(common\|validation\|errors\|auth\|verification\|hierarchy\|chat\|notices\|notifications\|settings\|landing\|admin\|school\|vendor\|ai\|analytics\|tuition\|marketplace\|commerce\|payments\|ads\|events\|sync\|ops)\.[a-z0-9_]+(\.[a-z0-9_-]+)*$` (registry: `02-solution-approach.md` §1.1; `snake_case` segments allowed — other modules already use e.g. `hierarchy.city_empty`) | N/A — build-time CI error (never user-facing) |
| Catalog key parity | Key in both `bn.json` and `en.json`; non-empty; identical `{param}` placeholders | N/A — build-time CI error (`DSN-UT-001`) |
| Locale value | Must be `bn` or `en`; anything else resolves to `bn` | `common.language.unsupported` (dev-facing warning) |
| Language selection (onboarding/settings, `03`) | One of `bn` / `en`; default `bn` | `common.language.bn` / `common.language.en` labels |
| Token values | Hex/px/duration literals only inside each app's `src/theme` token definitions | N/A — lint error (`DSN-INT-002`) |

Mirrored exactly by the zod form schemas (`03-identity-access` onwards), which reference `validation.*` keys so server contract errors and client messages stay identical in both languages.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Missing catalog key at runtime | Fallback chain requested locale → bn → key literal; dev warning; never a crash or blank |
| 2 | Missing bn or en key at build | CI fails (`DSN-UT-001`) before merge |
| 3 | Bangla string longer than English inside a fixed control | Wrap/grow per primitive min-height rules; never clip mid-glyph |
| 4 | Glyph missing from the bundled font | System Bengali fallback (e.g. Noto Sans Bengali) renders; specimen test flags the gap |
| 5 | Web font files unavailable at build | `next/font/google` fails the build loudly; app unaffected (fonts bundled) |
| 6 | Reduced motion enabled | Static/instant variant of every animation incl. the splash reveal |
| 7 | OS dark mode while only the light theme ships | Light theme renders in both languages regardless of OS setting |
| 8 | Logo asset missing/corrupt | Build fails on import — a blank header can never ship |

## 8. Reporting Needs

None — module 02 produces no data. The dashboards of `07-command-center-web` and `09-teacher-analytics` consume this module's primitives (Badge, Table shell, Skeleton, EmptyState) and tokens (chart series from the teal scale) when they render reports.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Logo vector files (SVG/AI) for production icon/splash/web use | Rahul | Open | Typographic fallback wordmark "কুশল CONNECT" + the supplied PNG (`docs/design-reference/brand/kushol-connect-full-logo.png`) for mockups; recorded as a gap until vectors arrive |
| 2 | Exact paper/ink hex values (proposed in the reference, not sampled from the PNG) | Rahul | Open | Use proposed `#FAFBFC` paper / `#111827`-scale ink; confirm ≥ 4.5:1 contrast and re-verify against the SVG when supplied |
| 3 | Dark theme scope at launch | Rahul | Open | Light theme only at launch; dark theme deferred — tokens are theme-able so it is additive later |
