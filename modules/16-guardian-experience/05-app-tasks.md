# Guardian Experience — App Tasks (Mobile)

**Module:** `16-guardian-experience`
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod · generated `openapi-fetch` client (`src/api/schema.gen.ts`)
**Last updated:** 2026-10-19

> **Status: planned, not built.**
>
> Binding rules:
> - `docs/design-reference/README.md` and `docs/tech-stack.md` (app table): tokens only, and
>   every string via `t()` with bn/en parity (bn values contain Bengali; placeholder parity test).
> - 360px-first.
> - The app gets a new catalog namespace, `guardian`. This needs `src/i18n/namespaces.ts`, the
>   `NAMESPACES` length assertion in `catalog.test.ts` (24 → 25), the web registry comment, and
>   02 `02-solution-approach.md` §1.1, all in the same change.
>
> Each feature uses the existing trio pattern: `src/lib/guardian/{backend.ts, live.ts,
> use-guardian.ts}` plus the `src/fixtures/guardian.ts` seam.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source | Phase |
| --- | --- | --- | --- | --- | --- |
| 1 | `/(tabs)/feeds` | Guardian home: `<GuardianHome/>` when `me.role === 'guardian'`, above the existing feed | Verified | none | G1 |
| 2 | sheet over any guardian screen | Child switcher | Verified | none | G1 |
| 3 | `/children` | My children: list, pending requests, pending invites (G2), "Add child" | Verified | push `guardian_link_decided` (approved, many children) | G1 |
| 4 | `/children/[studentId]` | Child hub: Overview · Notices · Fees · Chat · (Attendance · Results behind a flag) | Verified + linked + consent | push `guardian_link_decided` (approved), `guardian_child_placed` | G1 |
| 5 | `/children/add` | Add child (link request form) | Verified | none | G1 |
| 6 | `/children/requests` | Link requests (status, reason, cancel) | Verified | push `guardian_link_decided` (rejected) | G1 |
| 7 | `/(modals)/guardian-consent` | Guardian privacy notice (consent) | Verified | opened by home or hub on `consentRequired` / `CONSENT_REQUIRED` | G1 |
| 8 | `/payments?studentId=` (existing screen) | Fees with child filter chips; payer-scoped list | Verified | push `payments_fee_due` (existing; now also sent to guardians) | G0/G1 |
| 9 | `/(tabs)/notices` (existing) | Child filter chips for guardians with more than one child | Verified | push `notice_new` (existing) | G1 |
| 10 | `/(tabs)/you` (existing) | "My children" item (guardian) / "My guardians" item (student) | Verified | none | G1 |
| 11 | `/me/guardians` | Student: my guardians (read-only) | Verified student | none | G1 |
| 12 | `/(onboarding)/contact` (existing) | Relation select widened; invite-claim step after OTP (G2) | Public / Pending | SMS invite link → `/download` | G1/G2 |
| 13 | `PendingScreen` (existing component) | Guardian copy: "Your institution is matching you with student ID {code}" | Pending | none | G1 |

## 2. Screen Breakdown

### 2.1 Guardian home — `/(tabs)/feeds`

**Layout**

```text
360px
┌ Header: কুশল · 🔔 ────────────────────────────┐
│ Hello, করিম ভাই              [রাফি ▾] (switcher) │
│ ┌ ChildCard ─────────────────────────────────┐ │
│ │ (avatar) রাফি আহমেদ                          │ │
│ │ ক্লাস ৭ · শাখা খ · ডেমো হাই স্কুল               │ │
│ │ বকেয়া ৳ ১,২০০ (২টি)      সর্বশেষ নোটিশ: ছুটি… │ │
│ │ [শিক্ষককে বার্তা] [ফি দিন] [দেখুন →]            │ │
│ └────────────────────────────────────────────┘ │
│ ┌ ChildCard (waiting for placement) ─────────┐ │
│ │ সুমাইয়া · প্রতিষ্ঠান ক্লাসে যুক্ত করার অপেক্ষায় │ │
│ └────────────────────────────────────────────┘ │
│ [+ সন্তান যোগ করুন]   Requests (1 pending) →   │
│ ── existing feed below ──                      │
└────────────────────────────────────────────────┘
```

**Components** (`src/components/guardian/*`)

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `GuardianHome` | Server-driven (`GET /guardian/children`) | Renders the cards, the consent banner when `consentRequired`, and pending invites (G2) |
| `ChildCard` | Server-driven | `ui/card`, `ui/user-avatar`, `ui/badge`. ৳ amounts use bn digits in bn. The three actions are DM class teacher → `/messages/{peerId}`, pay → `/payments?studentId=`, view → `/children/{id}`. |
| `ChildSwitcher` | Client | Header chip plus a `ui/sheet` list. Writes `useActiveChild` (zustand). |
| `PendingInviteRow` (G2) | Server-driven | Accept / Decline |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Two ChildCard skeletons; the feed below loads independently |
| Empty | "No child linked" plus "Add child" (bn/en) |
| Error | Inline retry card plus a support path; the feed still renders |
| Offline | Cards from the in-memory query cache with an offline banner. Actions that need the network are disabled with a hint. |
| Quota/permission denied | `CONSENT_REQUIRED` opens the consent modal. A revoked link drops the card with a toast. |
| Success | Not applicable (read screen) |

### 2.2 Child switcher

- Shown when the guardian has 2 or more children. It is a header chip with the active child's
  first name.
- The active child is held in `useActiveChild` (zustand). Its id is persisted with
  `expo-secure-store`, which is already a dependency; the value is small and non-secret, and no
  AsyncStorage dependency is added. On load, an id that is no longer in the children list falls
  back to the first child.
- The hub, the notices filter and the payments filter all read the active child as their default.

### 2.3 Child hub — `/children/[studentId]`

**Layout**

```text
┌ ← রাফি আহমেদ                          [switch ▾] ┐
│ Segmented: সারসংক্ষেপ | নোটিশ | ফি | চ্যাট         │
│ Overview: class/section/session, class teacher   │
│   (name + [বার্তা]), co-guardians (name·relation),│
│   [Unlink…] (G1, OQ-10)                          │
│ Notices: ≤5 recent + "See all" → notices?child=  │
│ Fees: open invoices → pay; receipts              │
│ Chat: class teacher DM · school office DM ·      │
│   guardian group (G2)                            │
│ (Attendance | Results — hidden while flag off)   │
└──────────────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `ChildHubScreen` | Server-driven (`GET /guardian/children/{id}`) | `ui/segmented-pill` for sections |
| `ChildOverview` | Server-driven | Co-guardians show name and relation only |
| `ChildNoticesList` | Server-driven | Reuses the 05 notice row component |
| `ChildFeesList` | Server-driven | Reuses the 12 invoice row and links to `/payments/[invoiceId]` |
| `ChildChatLinks` | Server-driven | Opens the existing `/messages/[peerId]` and `/groups/[id]` routes |
| `AcademicRecordsSlot` | Flag-gated | Renders nothing while `guardian.academic_records` is off (`GRD-US-019`) |
| `UnlinkSheet` | Client | Optional reason, then confirm |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Section skeletons |
| Empty | Per section: "No notices yet", "No dues", "Class teacher not assigned yet" |
| Error | Retry. `FORBIDDEN`/404 ("This child is no longer linked") goes back to `/children`. |
| Offline | Last cached detail plus banner; pay and unlink disabled |
| Quota/permission denied | `CONSENT_REQUIRED` opens the consent modal, then re-fetches |
| Success | Unlink: toast, back to `/children`, and the caches are evicted |

### 2.4 Add child — `/children/add`

A form with school (prefilled with the guardian's school, locked in single-school mode), class
and section (reusing the onboarding hierarchy picker from `src/lib/onboarding/hierarchy.ts`),
student ID, relation, and the child's name (optional). Submit posts the link request.

| State | Behaviour |
| --- | --- |
| Loading | Picker skeleton |
| Error | Field errors mapped. `CONFLICT` shows "You already asked for this student" with a link to Requests. `GUARDIAN_LINK_LIMIT` shows the limit copy. |
| Offline | Submit disabled: "Connect to the internet to send the request" (not queued; the server must validate) |
| Success | Toast, then `/children/requests` |

### 2.5 Requests — `/children/requests`

A list of request rows (`PENDING`/`APPROVED`/`REJECTED`/`CANCELLED` badges, reason for
rejections, cancel for pending). Pull-to-refresh is supported.

### 2.6 Consent modal — `/(modals)/guardian-consent`

- Scrollable notice text in bn (default) or en. The text is `TODO: Confirm` until the owner
  approves it.
- The notice covers three things: what the guardian sees, what they never see, and how to
  unlink.
- An "I understand" button posts `{ noticeVersion, locale }`. The modal blocks child details but
  does not block the rest of the app.

## 3. Forms & Input

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| `sectionId` | Hierarchy picker | uuid, optional | — | add child |
| `studentCode` | `ui/text-field` | `studentCodeSchema` (exists, 3–20) | — | add child |
| `relation` | `ui/select` | `RELATIONS` widened to 10 values (`src/schemas/register.ts`) | `father` | add child, onboarding |
| `studentName` | `ui/text-field` | 2–80, optional | — | add child |
| `reason` (unlink) | `ui/textarea` | ≤500, optional | — | unlink |
| `noticeVersion` | hidden | equals the server value | from `GET /guardian/children` | consent |

Submission: the same contract shape as the API. Buttons are disabled while pending. Field errors
are mapped. Input is never lost on error. The layout is keyboard-aware.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Children list, child detail, requests | TanStack Query → `src/lib/guardian/backend.ts` (fixture or live chosen by the session-token selector, the 06/10/12 pattern) → `GET /guardian/children`, `/guardian/children/{id}`, `/guardian/link-requests`. Keys `['guardian','children']`, `['guardian','child',id]`, `['guardian','link-requests']` (`06` §4). |
| Mutations (link request, cancel, unlink, consent, invite claim) | `useMutation` → confirm → invalidate keys. **No optimistic update** for link changes (server decides). Rollback means nothing changes locally. |
| Fees | `src/lib/payments/live.ts` switches from `GET /school/invoices` (school-wide; a privacy bug) to `GET /payments/invoices?studentId=` (`GRD-INT-001`) |
| Notices | Existing 05 notices hook plus a client filter by the child's section ids (from the children list) |
| Realtime | None new. Chat uses 05's gateway. |
| Push | New types `guardian_link_decided`, `guardian_link_revoked` and `guardian_child_placed` route through the existing notification router: `/children/{studentId}` or `/children/requests`. Tapping one invalidates `['guardian','children']`. |
| Media | None new (avatars only, via 05 download urls) |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Child switcher sheet | Sheet slide-up 220 ms (Reanimated) | tap chip | Choosing context | static |
| ChildCard press | Scale 0.98 press feedback | press | Tappable | static |
| Card removal on revoke | Fade-out 150 ms | revoke detected | Child left | static |
| Pending badge | none (no pulse; low-end Android) | — | — | static |

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; actions in thumb reach; three card actions as icon + label buttons |
| ≥ 600px (tablet) | Centred column (max 560); hub sections in a two-pane grid |
| Low-end Android / 3G | One request for the children list (server batches); avatars via the compressed variant; paginated invoices |
| Bengali content | Hind Siliguri; bn digits for money and class numbers in bn; no clipped conjuncts in names |

## 7. Accessibility

- [ ] ChildCard `accessibilityLabel`: "{name}, class {n} section {s}, dues {amount}". Actions labelled.
- [ ] Touch targets ≥ 44pt; visible press states
- [ ] Contrast meets WCAG AA (dues badge and status badges)
- [ ] Reduced-motion form verified
- [ ] bn (default) and en verified on-device (owner, Gate 1)

## 8. Offline Behaviour

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| View children / hub | — (reads the in-memory cache of the current session; a cold start offline shows the offline state with retry, since there is no persisted query cache today) | Refetch on reconnect |
| Add child / cancel / unlink / consent / claim invite | No. Refused with a message. | — (the server must validate caps, duplicates and consent) |
| Pay | No (12 rule) | — |

## 9. Task Checklist

> Status on 2026-10-19: planned, not built.

- [ ] `GRD-AP-001` `src/lib/guardian/{backend,live,use-guardian}.ts` plus the `src/fixtures/guardian.ts` seam (fictional ডেমো data, contract-shaped)
- [ ] `GRD-AP-002` `guardian` namespace: `namespaces.ts`, `catalog.test.ts` length 24 → 25, bn/en keys (Edit-only on the shared catalogs), and 02 §1.1 registry row
- [ ] `GRD-AP-003` `GuardianHome` plus `ChildCard` in `(tabs)/feeds.tsx` (role-aware, anchored edit)
- [ ] `GRD-AP-004` `ChildSwitcher` plus the `useActiveChild` store (expo-secure-store persistence)
- [ ] `GRD-AP-005` `/children` list (requests and invites summary)
- [ ] `GRD-AP-006` `/children/[studentId]` hub (Overview, Notices, Fees, Chat) plus `AcademicRecordsSlot` (flag off)
- [ ] `GRD-AP-007` `/children/add` form
- [ ] `GRD-AP-008` `/children/requests` list plus cancel
- [ ] `GRD-AP-009` Consent modal plus `CONSENT_REQUIRED` handling in the shared query error path
- [ ] `GRD-AP-010` Payments: payer-scoped list plus child filter chips (`src/lib/payments/live.ts`, `use-payments.ts`, `payments/index.tsx`) — with `GRD-INT-001`
- [ ] `GRD-AP-011` Notices: child filter chips for guardians
- [ ] `GRD-AP-012` Chat entry points: class teacher DM and school office DM (G1); guardian group (G2)
- [ ] `GRD-AP-013` `(tabs)/you.tsx`: "My children" (guardian) and "My guardians" (student), plus `/me/guardians` screen
- [ ] `GRD-AP-014` Onboarding: `RELATIONS` widened (`src/schemas/register.ts`, `contact.tsx`) and `PendingScreen` guardian copy
- [ ] `GRD-AP-015` Invite claim: onboarding post-OTP step plus home `PendingInviteRow` (G2)
- [ ] `GRD-AP-016` Push routing for the 3 new push types (existing notification router)
- [ ] `GRD-AP-017` Jest: `ChildCard` render (bn digits, masked data absent), switcher fallback when the active child is removed, consent gate, add-child zod rules, payments uses the payer endpoint; Maestro flow `guardian-golden-path.yaml` (run by the owner)
