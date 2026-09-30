# <Module Name> — App Tasks (Mobile)

**Module:** `NN-<module-name>`
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** YYYY-MM-DD

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
> English, 360px-first layouts.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/…` | | Verified / Pending / Public | push topic · notification payload · none |

## 2. Screen Breakdown

### 2.1 `<Screen>` — `<route>`

**Layout**

```text
<ASCII wireframe at 360px wide — one thumb, Bangla first>
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| | | shared RN primitive from module 02 where one exists |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching the final layout; no blocking spinners |
| Empty | Explanation + primary action in the user's language |
| Error | Retry + support path; never a blank screen |
| Offline | Queued action acknowledged ("will send when online") |
| Quota/permission denied | Upgrade or request-access path, never a dead end |
| Success | Confirmation in bn + en |

## 3. Forms & Input

| Field | Control | zod rule (from `packages/shared`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| | | | | |

Submission: same contract shape as the API · disable while pending · map field errors · never lose
input on error · keyboard-aware layout (avoid the keyboard covering the submit).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| List / detail read | TanStack Query → generated OpenAPI client → api; cache key declared in `06` §4 |
| Mutation | Optimistic update → confirm → rollback with message on failure |
| Realtime | WebSocket gateway subscription (rooms declared in `06` §1); reconnect with backoff |
| Push | expo-notifications; topic subscriptions declared in `06` §1; tap routes via the deep-link table above |
| Media | Compress on device → R2 presigned upload → confirm to api (magic-byte sniffed server-side) |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| | | | | static |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only,
unless the module's `02` §7 says otherwise.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column, thumb-reachable actions |
| ≥ 600px (tablet) | Two-pane where the module's `02` requires it, else centred column |
| Low-end Android / 3G | Compressed images, paginated lists, no blocking loads |
| Bengali content | Hind Siliguri renders; no clipped glyphs; `locale="bn"` where applicable |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)

## 8. Offline Behaviour

> If this module has no offline surface, write "None — requires connectivity" with the reason.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| | | |

## 9. Task Checklist

- [ ] `<PREFIX>-AP-001`
