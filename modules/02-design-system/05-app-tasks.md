# Design System — App Tasks (Mobile)

**Module:** `02-design-system`
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens (from each app's `src/theme`) · @expo-google-fonts · radix-primitives/zeego · lucide-react-native · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

`docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
`docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
English, 360px-first layouts.

---

## 1. Screen Inventory

No routes owned — module 02 ships the theme/font/locale layer and the RN primitives that routed
screens consume:

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `app/_layout` (root — owned here) | Provider stack: fonts → theme → locale; splash gating | All (incl. Pending) | none |
| — | `/(tabs)/chat` · `/groups/[id]` · `/messages/[peerId]` | `05-communication-engine §1` | Verified | push · WS event |
| — | `/(tabs)/notices` | `05-communication-engine §1` | Verified | push topic |
| — | `/(tabs)/ai-hub` (+ `/ai-hub/scan`, `/ai-hub/test/[id]`) | `08-ai-study-hub §1` | Verified (quota) | push |
| — | `/(tabs)/marketplace` (+ tutors, store) | `10-tuition-marketplace §1` · `11-campus-commerce §1` | Verified | push · deep link |
| — | onboarding / auth / settings | `03-identity-access §1` | Public / any | none |

Consumption rule identical to web (`04-frontend-tasks §1`): primitives + tokens only.

## 2. Screen Breakdown

### 2.1 Root providers & splash — `app/_layout`

**Layout**

```text
┌──────────────────────────┐
│                          │
│      [swirl]  কুশল        │  ← lockup on paper background, centred
│        CONNECT           │
│                          │
│  (one-time ≤900ms reveal)│  → dismisses when fonts are ready
└──────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| Font gate (`useFonts`, `@expo-google-fonts`) | Client | Hind Siliguri + Inter bundled; native splash held until loaded — never an unstyled first frame |
| NativeWindProvider (shared tokens) | Client | `tailwind.config` preset consumes each app's `src/theme` tokens; pinned versions |
| `LocaleProvider` (`t()`) | Client | bn default; persisted selection hand-off owned by `03-identity-access` |
| Splash reveal | Client | one-time ≤ 900ms; static under reduced motion (`design-reference` §5) |

**States**

| State | Behaviour |
| --- | --- |
| Loading (fonts) | Native splash stays up — no flash of fallback type |
| Fonts ready | JS splash dismisses; first themed frame renders |
| Font load error | System Bengali fallback stack; app usable; never blank (fonts are bundled — failure ≈ corrupt install) |
| Reduced motion | Logo static; splash dismisses immediately |

### 2.2 RN primitive inventory (mirrors `04-frontend-tasks §2.2`)

**Layout**

```text
┌──────────────────────────┐
│  backdrop (dimmed)       │
│  ┌────────────────────┐  │
│  │  ── (grab handle)  │  │
│  │  Title (bn)        │  │
│  │  Body wraps ≥ +30% │  │
│  │  [ action ] [ghost]│  │
│  └────────────────────┘  │
└──────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| Button (+icon/loading) | Client | press feedback from motion tokens; ≥ 44pt height |
| Input · Textarea | Client | label/error slots; `validation.*` via `t()`; keyboard-aware |
| Select | Client | zeego action-sheet / native picker; bn option labels |
| Checkbox · Radio · Switch | Client | radix-primitives RN; ≥ 44pt targets |
| Card | Client | surface/radius tokens |
| Dialog / Sheet | Client | bottom sheet on phones; centred dialog ≥ 600px |
| Toast | Client | safe-area aware; `AccessibilityInfo` announcement |
| Tabs | Client | `/(tabs)` shell styling + in-screen tabs |
| Badge (+verified variant) | Client | trust signal (verified tutor, official notice source) |
| Skeleton | Client | opacity pulse; no endless shimmer loops on low-end devices |
| EmptyState | Client | bn-first copy + primary action |
| Avatar (verified-badge variant) | Client | initials fallback in Hind Siliguri |
| Icon wrapper | Client | lucide-react-native with token sizes/colours |
| `FloatingTabBar` + `Fab` | Client | CircleUp-style detached dark pill (teal-950), icon-only tabs + active dot, separate circular primary FAB with per-tab contextual action (hidden when none); safe-area aware; ≥ 44pt targets (`design-reference` §6.1) |
| `ScreenHeader` | Client | header wash (teal-50 → Paper, static) + large left title + circular outlined action button + avatar entry to `/settings` |
| `SegmentedPill` | Client | pill track with filled active segment (chat filters etc.); `accessibilityRole="tablist"` |
| `ListRow` | Client | avatar slot (+presence dot), title, 1-line preview, trailing time + `UnreadBadge`; long-press slot; used by chat list, notifications, members |
| `UnreadBadge` · `PresenceDot` · `AvatarStack` | Client | count badge (99+ cap, bn numerals via `Intl`); online dot; overlapping avatars + "১k+" count |
| `OtpInput` | Client | 6 boxes, auto-advance, paste + SMS autofill (`textContentType="oneTimeCode"`/`autoComplete="sms-otp"`) |
| `ConfirmModal` | Client | centred card with circular icon badge, Cancel (outline) + primary/destructive (CircleUp 47/83) |
| Table shell | N/A on RN — lists are FlatList/SectionList patterns owned by feature modules |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton twins; no blocking spinners (`prompt.txt` §3) |
| Focus/press/disabled | Pressed opacity/scale tokens; visible focus for keyboard/AT users |
| Error | Message via `t()`; retry owned by the feature screen |
| Offline | N/A for primitives themselves; queues are feature concerns (`05-communication-engine §8`) |
| Success | Toast/Badge confirmation in the user's language |

### 2.3 Bengali typography on device

- Fonts bundled via `@expo-google-fonts` (Hind Siliguri + Inter) — a launch requirement, not an
  add-on (`docs/tech-stack.md` app table); no system-font dependence.
- Specimen corpus (conjuncts, vowel signs, Bengali numerals ০–৯) rendered at caption→display in
  `DSN-UT-004` fixtures; on-device check in `DSN-E2E-001`.
- `allowFontScaling` respected (accessibility text sizes); bn strings +30% fixtures; no
  `numberOfLines={1}` on user content.

## 3. Forms & Input

Module-owned forms: none. Provided to feature modules:

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Language | Segmented control (bn/en) | `z.enum(["bn","en"])` | `bn` | Rendered by `03-identity-access` onboarding/settings |
| (feature fields) | §2.2 controls | Module-owned schemas | — | — |

Submission conventions: same contract shapes as web; disable while pending; field errors via `t()`;
input preserved on error; the submit action is never covered by the keyboard (keyboard-aware
scroll / `windowSoftInputMode`).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Tokens | Build-time import → NativeWind config; no runtime fetch |
| Strings | Static catalog import + `t()` (both locales bundled) |
| Fonts | Bundled in the binary (`@expo-google-fonts`) |
| Server data | N/A — no api calls in this module; consumers use the generated OpenAPI client (`01-foundations`) |
| Push / media | N/A — owned by `06-notifications §1` / `05-communication-engine §1` |

## 5. Motion Spec

Cheap on low-end Android — layout transitions and press feedback only (`02-solution-approach §7`):

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Press feedback | opacity/scale tokens, ~100ms | touch | Press registered | Instant state change |
| Sheet / dialog | slide-up + fade ~240ms | open | Spatial context | Instant show/hide |
| Toast | slide + fade | queued | Feedback arrived | Fade only |
| Skeleton | opacity pulse | loading | Progress | Static 50%-opacity block |
| Splash reveal | one-time ≤ 900ms | first launch | Brand | Static logo |
| Tab switch | none beyond platform default | — | — | Static |

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; 16px gutters (space tokens); thumb-reachable primary actions |
| ≥ 600px (tablet) | Centred column (max-width token); Dialog instead of Sheet |
| Low-end Android / 3G | Everything bundled — zero font/token network cost; skeletons; no endless shimmer loops |
| Bengali content | Hind Siliguri renders all glyphs; no clipped matras; bn-first copy; `bn` locale for `Intl` |
| Safe areas / keyboard | Notch insets respected (Toast, Sheet); keyboard never covers the submit action |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states from tokens
- [ ] Contrast meets WCAG AA against the themed background, in bn and en
- [ ] Motion: reduced-motion form verified for every §5 row
- [ ] Both languages verified on-device (bn default, en secondary) — `DSN-E2E-001`

## 8. Offline Behaviour

None — requires connectivity only for features, not for the design system: fonts, tokens and
catalogs are bundled at install, so a first launch with no network still renders fully themed in
Bangla. There is no offline queue surface in this module (queues belong to
`05-communication-engine §8` and `06-notifications`).

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| N/A — no network actions exist in this module | — | — |

## 9. Task Checklist

- [ ] `DSN-AP-000` — App repo scaffold in `applications/app` (own git repo, no shared package): Expo + expo-router, TypeScript strict, ESLint 10 flat (boundary rule: api only via `src/api`; env only in `src/env.ts`) + Prettier, jest-expo, `sync:api-spec` (copies `../api/openapi/openapi.yaml` to `openapi/openapi.yaml`) + `generate:api` (openapi-typescript → `src/api/schema.gen.ts`, openapi-fetch client), zod env module, GitHub Actions gate (lint/typecheck/test + client drift)
- [ ] `DSN-AP-001` — NativeWind configured from the app's `src/theme` tokens (pinned versions)
- [ ] `DSN-AP-002` — @expo-google-fonts Hind Siliguri + Inter bundled; root font gate; splash held until loaded
- [ ] `DSN-AP-003` — `LocaleProvider` + typed `t()` RN binding (bn default)
- [ ] `DSN-AP-004` — Button (+icon/loading)
- [ ] `DSN-AP-005` — Input + Textarea (keyboard-aware)
- [ ] `DSN-AP-006` — Select (zeego/native)
- [ ] `DSN-AP-007` — Checkbox + Radio + Switch
- [ ] `DSN-AP-008` — Card
- [ ] `DSN-AP-009` — Dialog + bottom Sheet
- [ ] `DSN-AP-010` — Toast (safe-area, accessibility announcement)
- [ ] `DSN-AP-011` — Tabs styling for the `/(tabs)` shell + in-screen tabs
- [ ] `DSN-AP-012` — Badge + verified variant
- [ ] `DSN-AP-013` — Skeleton + EmptyState
- [ ] `DSN-AP-014` — Avatar with verified-badge variant
- [ ] `DSN-AP-015` — Icon wrapper (lucide-react-native, token sizing)
- [ ] `DSN-AP-018` — CircleUp-pattern primitives: `FloatingTabBar`+`Fab`, `ScreenHeader`, `SegmentedPill`, `ListRow`, `UnreadBadge`/`PresenceDot`/`AvatarStack`, `OtpInput`, `ConfirmModal` (`docs/design-reference/README.md` §6)
- [ ] `DSN-AP-016` — App icon (adaptive) + splash + notification small icon from brand assets in `app.json`/EAS config; fallback per `01-user-stories §9` Q1
- [ ] `DSN-AP-017` — 360px bn-first verification pass (specimen + +30% strings) on a low-end Android profile
- [ ] `DSN-UT-004` — RN primitive render fixtures (defined in `06-integration-tasks §9`)
