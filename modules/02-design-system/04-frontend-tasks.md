# Design System — Frontend Tasks

**Module:** `02-design-system`
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 (`@theme` fed by `packages/shared`) · shadcn-style hand-written primitives on Radix · lucide-react
**Last updated:** 2026-09-30

`docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding: tokens
only from `packages/shared`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

This module owns **no routes** — it ships the token/theme layer and `src/components/ui/*` that every
route is built from:

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | N/A | No screens owned. Consumers: `/` + `/download` (`07-command-center-web §1`), `/login` (`03-identity-access §1`), `/admin/*` (`07`), `/school/*` (`07`), `/vendor/*` (`07`, `11-campus-commerce §1`, `13-b2b-ads-events §1`) | Server Components composing client primitives | Public + all roles |

Consumption rule: those routes compose only these primitives and tokens (`DSN-BR-002`); their
screens are specified in the owning modules.

## 2. Screen Breakdown

### 2.1 Foundation — tokens, fonts, locale wiring (root layout)

**Layout**

```text
root layout (app/layout.tsx)
├── <html lang={locale}>              ← bn default; updates on toggle
├── fonts: HindSiliguri (bengali subset) · Inter (latin subset)   ← next/font, display swap
├── globals.css  @theme: --color-* · --spacing-* · --radius-* · --text-* · --ease-*
└── <LocaleProvider>                  ← t() from packages/shared catalogs
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `@theme` token bridge | Server (build) | CSS custom properties generated from `packages/shared` tokens — the only place hex values appear in `web` |
| Font loading (`next/font/google`) | Server (build) | Hind Siliguri `bengali` subset, Inter `latin` subset; CSS-variable mode; fallback stacks incl. Noto Sans Bengali |
| `LocaleProvider` + `t()` binding | Client | bn default; sets `<html lang>`; typed keys; fallback per `DSN-UT-002` |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Fonts swap in (`display: swap`); Skeleton primitives ready for feature screens |
| Font build failure | Build fails loudly (`02-solution-approach §8` #1) — never silently re-themed |
| Missing key | bn → key-literal fallback + dev warning; the CI gate is the real defence |
| Locale toggled | Strings + `lang` attribute update; layout unchanged |

### 2.2 Primitive inventory (`src/components/ui/`)

**Layout**

```text
Button                              Dialog (desktop) / Sheet (mobile ≤ 640px)
┌─────────────────────────┐         ┌──────────────┐   ┌────────────────┐
│ [icon] Label bn/en      │         │   backdrop   │   │  grab handle   │
│  +30% length → wraps,   │         │ ┌──────────┐ │   │  title (bn)    │
│  min-height grows       │         │ │ content  │ │   │  body wraps    │
└─────────────────────────┘         │ │ actions  │ │   │  actions       │
 focus ring · pressed · disabled ·  │ └──────────┘ │   └────────────────┘
 loading (all token-styled)
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| Button (+icon/loading) | Client | primary/secondary/ghost/destructive variants; min-height for bn wrap |
| Input · Textarea | Client | label/description/error slots; errors from `validation.*` via `t()` |
| Select | Client | Radix; bn option labels |
| Checkbox · Radio · Switch | Client | Radix; ≥ 44px targets |
| Card | Server-safe | surface/radius tokens; header/content/footer slots |
| Dialog / Sheet | Client | Radix dialog; Sheet = mobile variant ≤ 640px |
| Toast | Client | queue, auto-dismiss, action slot; `aria-live` |
| Tabs | Client | Radix; animated indicator (instant under reduced motion) |
| Badge (+verified variant) | Server-safe | trust signal; teal scale |
| Table shell | Server-safe | TanStack-compatible shell (header/body/empty slots); sticky header ≥ 1024 |
| Skeleton | Server-safe | shimmer; static pulse under reduced motion |
| EmptyState | Server-safe | icon/title/action; bn-first copy via `t()` |
| Avatar (verified-badge variant) | Server-safe | image + badge overlay; initials fallback in Hind Siliguri |
| `Logo` | Server-safe | lockup per `docs/design-reference/README.md` §5; accessible name "Kushol Connect — Home" |
| `AdminShell` (Sidebar + Topbar) | Client | professional console shell (`design-reference` §7.2): collapsible role-filtered sidebar, breadcrumbs, school switcher slot, language toggle, user menu; used by `/admin`, `/school`, `/vendor` |
| `PageHeader` | Server-safe | title, description, primary/secondary action slots |
| `StatCard` | Server-safe | label, value (Inter tabular), delta, optional sparkline; "—" + tooltip when value unavailable (never placeholder numbers) |
| `DataTable` | Client | TanStack Table on top of Table shell: sort, filter, pagination, row selection + bulk-action bar, density toggle |
| `MarketingSection` · `Hero` | Server-safe | landing building blocks (`design-reference` §7.1): section container/grid, eyebrow + headline + body + CTA slots, device-frame screenshot slot |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton twin of the final layout; no blocking spinners |
| Focus/pressed/disabled | Every interactive primitive defines all three from tokens; 2px focus-ring token |
| Error (forms) | Message resolved from `validation.*` via `t()`; announced to assistive tech |
| Empty | EmptyState with bn-first copy + primary action |
| Success | Toast/Badge confirmation in the user's language |

### 2.3 Bilingual rendering rules

- `<html lang>` = `bn` default; toggles with locale; dates/numbers via `Intl` with `bn`/`en`
  (`docs/tech-stack.md` i18n row).
- Bengali strings render in Hind Siliguri; Inter only for Latin and tabular figures (ledger IDs) —
  `DSN-BR-004`.
- Every primitive is tested with a bn fixture string ~30% longer than the en one (`DSN-UT-003`).

## 3. Forms

Module-owned forms: none. Provided to feature modules:

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Language | Segmented control (bn/en) | `z.enum(["bn","en"])` | `bn` | Rendered by `03-identity-access` onboarding/settings |
| (feature fields) | Input/Select/etc. from §2.2 | Schemas from `packages/shared`, module-owned | — | — |

Submission convention this module establishes: zod issue → `validation.*` key → `t()` message;
disable while pending; never lose input; error text announced. (The wiring itself is each
consuming module's `03`/`04` sections.)

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Tokens | Build-time import `packages/shared` → `@theme`; no runtime fetches |
| Strings | Static catalog import + `t()`; both locales bundled (the pair is small) |
| Brand assets | `next/image` static imports (logo PNG until vectors arrive — `01-user-stories §9` Q1) |
| Server data | N/A — module 02 makes no API calls; consumers use the generated OpenAPI client (`01-foundations`) |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Button press | scale 0.98 + state colour, 100–150ms | pointer down | Press registered | Instant state colour, no scale |
| Dialog / Sheet enter-exit | fade+scale ~180ms / slide-up ~240ms | open/close | Spatial context | Instant show/hide |
| Toast | slide+fade in; auto-dismiss ~4s | queued | Feedback arrived | Fade only, timing kept |
| Tabs indicator | layout transition ~200ms | tab change | Spatial continuity | Instant reposition |
| Skeleton shimmer | gradient sweep loop | pending data | Loading progress | Static 50%-opacity pulse |
| Splash/logo reveal | one-time ≤ 900ms swirl reveal | first launch | Brand | Static logo (`design-reference` §5) |

All durations/easings read from motion tokens; OS `prefers-reduced-motion` switches every row to
its right-hand column (`DSN-BR-007`).

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Dialog/Sheet | Sheet (bottom) | Dialog centred | Dialog centred |
| Table shell | Horizontal scroll + sticky first column | Full table | Dense table + sticky header |
| Buttons in forms | Full-width, stacked | Inline | Inline |
| Type scale | Base (360px-first) | Base | +1 step on display sizes |
| Toast | Full-width bottom | Top-right card | Top-right card |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order — primitives provide heading/section shells; verified per screen by owning modules
- [ ] Keyboard path complete; focus visible (2px ring token) and never lost (Radix focus management)
- [ ] Labels, descriptions, error announcements (`aria-describedby`; `aria-live` on toasts)
- [ ] Contrast meets WCAG 2.2 AA in the light theme in bn AND en (ink/paper ≥ 4.5:1; deep teal on paper verified; axe in CI per `docs/tech-stack.md`)
- [ ] Motion: reduced-motion variant verified for every row of §5

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold by construction: the palette exists only in
`packages/shared` tokens (`DSN-BR-002`/`DSN-BR-005`), the logo is reachable only through `<Logo/>`
(`DSN-BR-006`), Bengali never renders in Inter (`DSN-BR-004`), and every string resolves through
`t()` behind the CI parity gate (`DSN-BR-001`). Compliance tooling = `DSN-INT-002` lint +
`DSN-UT-001`/`DSN-UT-003` tests; the first real-world audit is module 07's screens.

## 9. Task Checklist

- [ ] `DSN-FE-001` — Semantic token module in `packages/shared` (color scale, spacing, radius, type, motion) + TS types
- [ ] `DSN-FE-002` — Tailwind v4 `@theme` bridge in `applications/web` consuming shared tokens (no other hex in `web`)
- [ ] `DSN-FE-003` — Fonts via `next/font/google`: Hind Siliguri (`bengali`+`latin`) + Inter (`latin`), CSS variables, fallback stacks
- [ ] `DSN-FE-004` — `LocaleProvider` + typed `t()` web binding; `<html lang>` bn default
- [ ] `DSN-FE-005` — Button (+icon, loading, destructive variants)
- [ ] `DSN-FE-006` — Input + Textarea (label/description/error slots)
- [ ] `DSN-FE-007` — Select
- [ ] `DSN-FE-008` — Checkbox + Radio + Switch
- [ ] `DSN-FE-009` — Card
- [ ] `DSN-FE-010` — Dialog + Sheet (mobile variant)
- [ ] `DSN-FE-011` — Toast
- [ ] `DSN-FE-012` — Tabs
- [ ] `DSN-FE-013` — Badge + verified variant
- [ ] `DSN-FE-014` — Table shell (TanStack-compatible)
- [ ] `DSN-FE-015` — Skeleton + EmptyState
- [ ] `DSN-FE-016` — Avatar with verified-badge variant
- [ ] `DSN-FE-017` — `Logo` component (usage rules, accessible name, one-time reveal hook, PNG-fallback support)
- [ ] `DSN-FE-018` — Light-theme contrast pass (WCAG 2.2 AA, bn/en) + axe clean on the primitive fixtures
- [ ] `DSN-FE-019` — Professional web primitives: `AdminShell`, `PageHeader`, `StatCard`, `DataTable`, `MarketingSection`/`Hero` (`docs/design-reference/README.md` §7)
- [ ] `DSN-UT-003` — Web primitive render/a11y fixtures (defined in `06-integration-tasks §9`)
