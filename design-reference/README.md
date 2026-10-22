# Design Reference — Kushol Connect brand

| | |
| --- | --- |
| **Status** | 🟢 Binding reference — encode as tokens in each app's `src/theme` (web and app each hold their own copy) |
| **Date** | 2026-09-29 |
| **Brand asset** | `brand/kushol-connect-full-logo.png` (1280 × 647, transparent background) — source PNG supplied by the owner |
| **Mobile UI reference** | CircleUp UI kit (Figma, owner-supplied 2026-09-30) + WhatsApp chat conventions — §6; screenshots in `mobile-circleup/` |
| **Web UI direction** | Professional SaaS: landing = B2B marketing site, Command Center = dense admin console — §7 |

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

## 6. Mobile UI language — CircleUp layout + WhatsApp chat (binding, 2026-09-30)

**Source.** Owner direction 2026-09-30: the app "should be like" the CircleUp — Community, Events &
Networking Mobile App UI Kit (Figma file `7Tog1PwHGskht1FadlEBnJ`, frame "Screens Preview",
node `16041:16607`, ~90 screens) **and like WhatsApp**. Reference screenshots (internal use only —
the kit is a third-party preview; never ship its illustrations, photos or icons):

| File | Shows |
| --- | --- |
| `mobile-circleup/00-all-screens-overview.png` | Every screen: splash, onboarding, auth/OTP, feed, communities, posts, events, messages, profile, search, notifications, settings |
| `mobile-circleup/58-message-list.png` | Message list with segmented filter + floating tab bar |
| `mobile-circleup/61-chat-one-to-one.png` | 1:1 chat bubbles, ticks, composer |
| `mobile-circleup/31-community-details-feed.png` | Group/community header, member stack, Join CTA, Feed/Event tabs, post card |

The Figma file is a flat-image preview (no variables/components) — values below are read from the
screens, not exported tokens. `TODO: Confirm` exact spacing/radius when the full kit is available.

**Rule: take CircleUp's layout, components and interaction patterns; keep Kushol's identity.**
CircleUp's violet primary is replaced by deep teal `#095777` (§2) everywhere (active pill, outgoing
bubble, FAB, primary CTA, header wash). Typography stays Hind Siliguri/Inter (§3), bn-first. Every
pattern must still work at 360px on low-end Android (`prompt.txt` §3).

### 6.1 App shell

| Pattern (CircleUp screen) | Kushol rule |
| --- | --- |
| Floating tab bar (58, 22) — dark rounded pill, 4 icon-only tabs, active = dot under icon, detached circular primary **FAB (+)** to its right | Pill surface = teal-950 (derived scale), icons white 70% / active 100% + dot; tabs map to `prompt.txt` §7: **Chat · Notices · AI Hub · Marketplace**. A tab appears only once its module ships (Phase 1: Chat + Notices). FAB is contextual: Chat → new message/club · Notices → compose (admin/teacher only; hidden otherwise) · AI Hub → scan note · Marketplace → none (hidden). Icons carry `accessibilityLabel` in bn/en |
| Header wash (all tab roots) — faint brand tint gradient at top fading to white | teal-50 → Paper, ≤ 180pt tall, static (no animation) |
| Page title (58) — large left-aligned title + circular outlined action button right | Title = `type.title` Hind Siliguri semibold; right action = 40pt circle outline (e.g. new chat, filter); avatar top-left opens `/settings` + profile |
| Segmented pill filter (58: All / People / Group) | Chat home filter = **All · Official · Clubs · DMs** (05 `SegmentedTabs`); light-gray track, filled teal pill for active |
| Underline tabs (31: Feed / Event) | In-screen tabs (group detail: Chat · Notices · Members; AI Hub: Scans · Tests) |
| Onboarding carousel (2–7) — 3 slides, large illustration, title, pill CTA + round back button | 03 onboarding intro: 3 slides (Connect your school · Official notices · Study with AI), Kushol-owned illustrations only (`TODO: Confirm` illustration source), skip on every slide |
| Auth (8–21) — SSO row, rounded inputs, full-width pill CTA, 4–6 box OTP input, success modal with circular icon badge | 03 phone-OTP-first flow uses these layouts; OTP = 6 boxes, auto-advance, SMS autofill |

### 6.2 Chat — WhatsApp behaviour in CircleUp styling (module 05)

| Element | Rule |
| --- | --- |
| Chat list row (58) | 48pt circular avatar (initials fallback in Hind Siliguri, tinted), online dot (presence) bottom-right, name semibold 1 line, last-message preview 1 line ellipsis (`Sender: text` in groups), time right, **unread count badge** (brand-danger circle) under the time; sorted by last activity; pinned rows first (official section group pinned by default); long-press → pin / mute / mark read |
| Chat screen (61) | Header: back, avatar + online dot, name, subtitle = "typing…" / "online" / member count, overflow `⋯`. Incoming bubble = light-gray surface, left, sender avatar + (groups) sender name in tinted colour; outgoing = teal fill, white text, right. Bubble radius ≈ 20pt with tighter corner at the tail side; timestamp + ticks under the bubble (SENDING clock → SENT ✓ → SEEN ✓✓ accent — 05 `MessageBubble`) |
| WhatsApp conventions kept | Day separators ("আজ / Today"), consecutive-message grouping (avatar once per run), swipe-right-to-reply with quoted preview, long-press action sheet (reply · copy · delete-within-window · report), jump-to-latest button with unread count, offline banner + queued clock state, voice-note hold-to-record with slide-to-cancel, image/PDF inline cards, deleted-message tombstone |
| Composer (61) | Pill input with attach icon (left) and mic (right, becomes send when text present) + separate circular teal **send** button; keyboard-aware; disabled with notice in archived groups |
| Not copied from WhatsApp | Calls (out of scope `brd.md` §4), stories/status, disappearing messages, end-to-end-encryption claims (the platform stores messages server-side — never imply E2EE in copy) |

### 6.3 Content surfaces

| Pattern (CircleUp) | Kushol use |
| --- | --- |
| Group/community header (31) — cover image/gradient, translucent circular back/more buttons, overlapping logo avatar, verified badge, member avatar stack "1k+", pill primary CTA + circular share | School/section group detail, storefront (11), event (13). Verified badge only for real verified entities (never fake — 05) |
| Post/notice card (31) — author row (avatar, name, time · place, `⋯`), rounded media, action row with counts | Notice card (05) — no like/comment counts on official notices; pin + scope badge instead. Events (13) may show interested counts |
| Event list/detail (50–57) — cover card with date chip, RSVP bottom sheet, attendee list | Module 13 events + tickets |
| Bottom sheets (25, 48) — quick actions, report reasons | All secondary actions on mobile (02 `Sheet`) |
| Confirmation modal (47, 83) — centred card, circular icon badge, Cancel (outline) + primary/destructive | All destructive confirms (02 `Dialog`) |
| Search (74–79) — pill search field, result-type tabs, filter sheet, illustrated empty state | Directory/tutor/marketplace search (10/11) |
| Notifications (80–83) — grouped by day, avatar/icon + text + time, unread tint, "mark all read" | 06 in-app notification centre |
| Settings (84–89) — grouped rows with chevrons/toggles; theme and language pages | `/settings`: language (bn/en), notification preferences (06), privacy, help, about/version |

### 6.4 Motion & accessibility

Press = scale 0.97 + opacity; sheets/modals spring in ≤ 250 ms; bubble send = 150 ms slide-fade.
All have static reduced-motion variants (`01` §7 convention). Touch targets ≥ 44pt even inside the
floating tab bar; contrast of white-on-teal-950 and teal-on-white verified AA.

## 7. Web UI direction — professional (module 07 and every web surface)

**Owner direction 2026-09-30:** the landing page and admin panels must look professional —
credible to school principals and brand managers. No consumer-app styling (no floating tab bar,
chat bubbles or playful illustration on web).

### 7.1 Landing page (`/`, `/download`)

> **Owner direction 2026-10-09:** the landing page becomes a promotional, illustrated, animated
> funnel with denser sections (56–72 px desktop / 40–48 px mobile) and an auto + manual feature
> slider. `docs/prompt/prompt-landing-design.md` supersedes the **Visual** and **Imagery** rows
> below for `/` and `/download`; every other rule here, §1–§5 and §7.2 still apply.

| Rule | Value |
| --- | --- |
| Reference class | Modern B2B SaaS marketing site (clean hero, product screenshots, proof, clear CTAs) |
| Structure | Sticky header (logo, section links, language toggle, "Book a pilot" primary CTA) → hero (bn headline, one-line value prop, primary CTA + secondary "Download app", real product screenshot in a device frame) → audience sections (Schools · Brands/Partners · Students & Guardians) → how it works (3 steps) → ROI calculator card → trust (verified-school model, data privacy, local payments) → pilot form → footer (contact, legal, social) |
| Visual | Paper background, generous whitespace (section padding 96px desktop / 56px mobile), 12-col grid max-width 1200px, deep-teal primary, slate-teal secondary, one subtle teal gradient in the hero only; 8px radius cards, 1px borders, soft single-layer shadows |
| Imagery | Real app screenshots (post-module 05) and owner-supplied photos only; never stock "happy students" placeholders shipped as final; no fabricated logos, testimonials, or user counts (`prompt.txt` never-fabricate rule) |
| Performance/SEO | Static render, LCP < 2.5s on 3G-fast, fonts via `next/font` subsets, OG images per locale (`prompt.txt` §4A) |

### 7.2 Command Center (`/admin`, `/school`, `/partner`)

| Rule | Value |
| --- | --- |
| Reference class | Professional admin console (shadcn/ui dashboard style) |
| Shell | Collapsible left sidebar (icon + label, grouped sections, role-filtered), top bar (breadcrumbs, school switcher for Super Admin, global search, language toggle, user menu), content max-width fluid with 24px gutters |
| Dashboard | KPI stat cards (label, value in Inter tabular figures, delta, sparkline), then tables/charts; every number from an API — "—" with tooltip when unavailable, never a placeholder figure |
| Data | TanStack Table: sticky header, column sort/filter, pagination, row selection + bulk actions, density toggle, CSV export where the API allows; empty/loading/error states from 02 |
| Forms | Sectioned forms with helper text, inline validation (React Hook Form + zod), sticky save bar for long forms, destructive actions confirmed in a Dialog |
| Visual | Neutral gray surfaces (white cards on gray-50), deep-teal only for primary actions/active nav/focus, status colours via semantic tokens (success/warning/danger/info) with icons (never colour alone) |
| Responsiveness | Desktop-first, complete down to tablet 768px (`prompt.txt` §4B); keyboard-complete |
