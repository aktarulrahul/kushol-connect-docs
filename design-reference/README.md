# Design Reference — Kushol Connect brand

| | |
| --- | --- |
| **Status** | 🟢 Binding reference — encode as tokens in `packages/shared` and per-app theme configs |
| **Date** | 2026-09-29 |
| **Brand asset** | `brand/kushol-connect-full-logo.png` (1280 × 647, transparent background) — source PNG supplied by the owner |

> **How to use this folder.** The logo PNG is the single source of truth for the brand until vector
> files are supplied (see `brand/README.md`). When building, define design tokens from the palette
> below, and sample exact values from the PNG. Never redraw or restyle the mark.

---

## 1. The mark

The Kushol Connect logo has three parts, always used together as a lockup:

1. **The swirl** — a spiral "eye" form on the left, rendered in a gradient that sweeps from
   swoosh-gray through slate-teal into deep teal. It reads as connection, community and focus.
2. **The wordmark "কুশল"** — Bengali logotype in deep teal, set on the baseline right of the swirl.
   This is the primary brand name; "Kushol" is the romanisation.
3. **The subtitle "CONNECT"** — spaced capitals set under the right portion of the wordmark in
   deep teal. It distinguishes this product (the Connect platform) within the Kushol brand family.

The brand speaks Bengali first: UI copy defaults to Bangla, with English as the secondary language
(`brd.md` audience, `prd.md` §2).

## 2. Palette (sampled from the PNG 2026-09-29 — `verify` against the SVG when supplied)

| Token | Sampled value | Where it appears | Role in the design system |
| --- | --- | --- | --- |
| Deep teal | `#095777` | Wordmark, "CONNECT", swirl core | `--brand-primary`: primary buttons, links, active states, headers |
| Slate teal | `#386070` | Swirl gradient midpoint | `--brand-secondary`: secondary surfaces, icons, chart series |
| Swoosh gray | `#707070` | Swirl tail / highlight | Brand graphic only — do not use as a UI text colour |
| Paper | near-white `#FAFBFC` (proposed) | — | Light background (mobile + web light theme) |
| Ink | near-black `#111827`-scale (proposed) | — | Primary text; verify contrast against Paper (target WCAG AA ≥ 4.5:1) |

Derived tints/shades (10-step scale from deep teal) are generated in code — do not hand-pick
one-off hex values in components.

## 3. Typography

| Use | Typeface | Notes |
| --- | --- | --- |
| Bengali UI + display | **Hind Siliguri** | Launch requirement; bundled in the app (`@expo-google-fonts`) and web (`next/font/google`, `bengali` subset) |
| Latin UI + body | **Inter** | Pairs with Hind Siliguri at matching metrics |
| Numbers/metadata (IDs, ledger figures) | Inter tabular figures | No monospace brand need identified yet |

Rules: never render Bengali user content in Inter (missing glyphs); set language tags correctly
(`lang="bn"` / `lang="en"`) for screen readers and hyphenation.

## 4. Logo files needed (owner action)

`brand/README.md` lists the vector sources to add. Until then the PNG in `brand/` is the reference
and may be used for internal mockups only — a production build needs SVG (or 2× PNG exports).

## 5. Logo usage rules

| Rule | Value |
| --- | --- |
| Header size | Lockup height 28–32px (width follows the ≈ 2 : 1 ratio of the supplied PNG) |
| Minimum size | Lockup ≥ 20px tall; do not separate the swirl from the wordmark below this size |
| Clear space | ≥ ¼ of the swirl's height on every side |
| Backgrounds | Paper, white, or flat deep-teal surfaces only — never busy photography or gradients behind the lockup |
| Colour variant | On deep-teal backgrounds use a white/knockout version (to be supplied) — do not invent one by inverting the PNG |
| Never | Recolour the swirl gradient · stretch or re-space the wordmark or "CONNECT" · add shadows/effects · set the Bengali wordmark in a different typeface · animate the swirl in loops (a one-time ≤ 900ms reveal on first launch is acceptable, static under reduced motion) |
| Accessible name | The logo reads "Kushol Connect — Home" (`aria-label`), not the literal Bengali glyphs letter-by-letter |
