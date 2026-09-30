# Notifications — App Tasks (Mobile)

**Module:** `06-notifications`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table — push via **expo-notifications**) are binding: tokens only,
> every user-facing string in Bengali + English, 360px-first layouts.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(modals)/notifications-primer` | Permission primer (value-first explainer → OS permission ask in context) | Authenticated (post-login, pre-verification OK) | none (post-login flow) |
| 2 | `/settings/notifications` | Notification settings — 3 class toggles + registered devices | Verified | none (settings entry) |
| 3 | *(targets only — built by other modules)* | `/notices/[id]` (05) · `/messages/[peerId]` (05) · `/receipts/{paymentId}` (12) · `/ai-hub/test/[id]` (08) | per owner | push `payload.type` routing below |

## 2. Screen Breakdown

### 2.1 Permission primer — `/(modals)/notifications-primer`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│              (🔔 illustration)          │
│        নোটিফিকেশন চালু করুন             │
│     Stay updated — bn অথবা en           │
│ ┌────────────────────────────────────┐ │
│ │ 📢 নোটিশ — স্কুলের ঘোষণা, পরীক্ষার  │ │
│ │    রুটিন, ফি-এর তারিখ              │ │
│ │ 💬 চ্যাট — নতুন মেসেজ ও ডিএম        │ │
│ │ 🎯 ক্যাম্পেইন — ইভেন্ট ও অফার       │ │
│ └────────────────────────────────────┘ │
│ [     অনুমতি দিন / Allow         ]     │
│ [     পরে / Not now              ]     │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `PrimerClassRow` | Client | one row per class (📢💬🎯) with bn/en explainer from `notifications.primer.*` — the value before the ask |
| `AllowButton` | Client | triggers the OS permission dialog **in context** (after value shown); on grant → device registration (`NTF-AP-003`) |
| `LaterButton` | Client | dismisses; settings entry point stays reachable — never a dead end, never re-nags |
| `SettingsHint` | Client | permanent-denial state: "সেটিংসে চালু করুন / Enable in Settings" → OS app settings |

**States**

| State | Behaviour |
| --- | --- |
| Permission granted | Success → close + register device; settings screen reflects "চালু / On" |
| Permission denied | Explanation + path to OS settings; registration deferred, in-app still fully works |
| Permanently denied (OS) | `SettingsHint` opens the OS app-settings screen — no dead end |
| Registration fails (offline) | Primer closes; token registration queued and replayed when online (§8) — user never blocked |
| Already decided | Primer is shown exactly once per install unless permission state changes |

### 2.2 Notification settings — `/settings/notifications`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  নোটিফিকেশন সেটিংস                    │
│ ┌────────────────────────────────────┐ │
│ │ নোটিশ / Notices              [◉──] │ │
│ │ স্কুল ও সেকশনের ঘোষণা, ফি-এর তারিখ │ │
│ ├────────────────────────────────────┤ │
│ │ চ্যাট / Chat                 [◉──] │ │
│ │ নতুন মেসেজ ও ডিএম                  │ │
│ ├────────────────────────────────────┤ │
│ │ ক্যাম্পেইন / Campaigns       [──○] │ │
│ │ ইভেন্ট ও অফার (বিজ্ঞাপন)           │ │
│ └────────────────────────────────────┘ │
│ পরিবর্তন সাথে সাথে সংরক্ষিত হয়        │
│ (Android-এ সিস্টেম চ্যানেলের সাথে মিলিত)│
│ ── ডিভাইস ──                           │
│ 📱 Samsung A12 · Android · সক্রিয়      │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `PrefToggleRow` | TanStack Query + optimistic PATCH | switch ≥ 44 pt; label + description from `notifications.class_*`; toggles map 1:1 to the three Android channels (`§6`) |
| `ChannelNote` | Client | explains the Android system-channel alignment in bn/en |
| `DeviceRow` | Client | this device's registration state (`POST /devices` result cached); logout cleanup is automatic (`NTF-AP-004`) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton switch rows matching the final layout; no blocking spinners |
| Empty | N/A — the API always returns exactly three rows (lazy-created server-side) |
| Error | Retry inline; cached values stay visible with a stale banner |
| Offline | Toggle moves optimistically; "অনলাইনে সংরক্ষণ হবে / Will save when online" + queued PATCH (§8) |
| Success | Silent save + subtle confirmation; no navigation away |

### 2.3 Foreground & tap behaviour (no new screen — behaviour spec)

| Situation | Behaviour |
| --- | --- |
| App **foregrounded**, push arrives | No system tray duplicate; in-app banner slides down (class icon, bn/en body), auto-dismiss 5 s, tap = deep link |
| App **background/terminated** | System tray via the class's Android channel; iOS banner |
| Tap, app **cold** | Auth gate first → then deep link (`§2.4`); unauthenticated taps park the route until login |
| Tap, target deleted/unknown type | Fallback: home tab + "লিঙ্কটি আর কাজ করছে না / This link is no longer available" — never a crash |
| Badge | Per-class unread badge on the Notices tab; cleared when the tab/detail opens; server count respected |

### 2.4 Deep-link handling — `payload.type → route` map

The push payload is schema v1 (`02-solution-approach.md` §2/§10): key + ids + deep link + bn/en
strings — never message bodies. Directed payloads carry `deliveryId`; topic payloads do not
(fire-and-forget). Example (directed DM):

```json
{
  "v": 1,
  "class": "chat",
  "type": "dm",
  "key": "notifications.dm_new",
  "data": { "peerId": "0198…", "dmGroupId": "0199…" },
  "deepLink": "/messages/0198…",
  "deliveryId": "0197…",
  "strings": {
    "bn": { "title": "কুশল", "body": "করিম আহমেদ আপনাকে একটি মেসেজ পাঠিয়েছে" },
    "en": { "title": "Kushol", "body": "Karim Ahmed sent you a message" }
  }
}
```

| `payload.type` | Route (expo-router) | Screen owner | Payload data (ids only) |
| --- | --- | --- | --- |
| `notice` | `/(tabs)/notices` → `/notices/{noticeId}` | 05 | `{ noticeId }` |
| `dm` | `/messages/{peerId}` | 05 | `{ peerId, dmGroupId }` |
| `payment_result` | `/receipts/{paymentId}` (route frozen with module 12) | 12 | `{ paymentId }` |
| `tuition_match` | `/messages/{peerId}` — chat with the requester | 10 → 05 | `{ matchId, peerId }` |
| `test_result` | `/(tabs)/ai-hub` → `/ai-hub/test/{testId}` | 08 | `{ testId }` |
| `campaign` | `/(tabs)/notices` (campaigns section, fed by 13) | 13 | `{ campaignId }` |
| `test` (admin pilot) | `/(tabs)/chat` (home) + "টেস্ট নোটিফিকেশন / Test notification" toast | 06 | `{ testId }` |
| *(unknown)* | `/(tabs)/chat` + fallback toast; event logged | — | — |

On every directed tap the app fires `POST /notifications/deliveries/{deliveryId}/opened`
(fire-and-forget; idempotent server-side).

## 3. Forms & Input

| Field | Control | zod rule (from `packages/shared`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Preference `muted` per class | labelled switch (3 rows) | `validation.notifications.class_invalid` · `muted_required` | all unmuted | always |
| Device `token` / `platform` / `appVersion` | system-provided (expo-notifications), not user input | `validation.notifications.token_invalid` · `platform_invalid` | auto | post-permission |

Submission: same contract shape as the API · disable while pending · map field errors · never
lose input on error · toggles stay interactive (optimistic) with rollback + message on failure.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Preference read/write | TanStack Query → generated OpenAPI client → `GET/PATCH /notifications/preferences`; cache key `notifications:prefs:{userId}` (`06` §4) |
| Device registration | login (03) success → primer → `getDevicePushTokenAsync` → `POST /notifications/devices`; re-run on token rotation; foreground heartbeats refresh `last_seen_at` |
| Logout cleanup | `DELETE /notifications/devices/{id}` before token wipe — failure is retried silently and never blocks logout |
| Push receive | expo-notifications listener → key resolved from on-device `notifications.*` catalog → `strings` pair fallback → render on the class channel |
| Push tap | response listener → deep-link map (§2.4) → route → `POST …/opened` (directed only) |
| History | TanStack Query paginated `GET /notifications/deliveries` (settings sub-screen) |

Channel alignment rule: a muted preference also disables the matching Android channel
(`NTF-BR-004`); re-enabling restores it — the two never drift.

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Foreground banner | slide-down + fade (≤ 150 ms) | push received in foreground | message arrival, without stealing focus | instant show/hide |
| Preference switch | thumb spring (≤ 120 ms) | user toggle | state change committed optimistically | instant swap |
| Primer modal | fade + slight scale | post-login first run | a deliberate, calm ask | instant present |
| Badge increment | subtle scale pop | new class message | unread count changed | instant update |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only,
unless the module's `02` §7 says otherwise.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; primer and settings fit one thumb; rows full-width, actions right-aligned |
| ≥ 600px (tablet) | Centred column, max-width ~480 px for settings/primer |
| Low-end Android / 3G | No payload prefetch on receive (ids only — that is the design); history paginated 20/page; no blocking loads |
| Bengali content | Hind Siliguri renders; bn strings from `notifications.*`; bn numerals via `Intl` in history timestamps |

Android channels (registered at app start, `NTF-AP-001`; one per class — README module 06 default):

| Channel id | bn name | en name | Importance |
| --- | --- | --- | --- |
| `notices` | নোটিশ | Notices | HIGH (sound) |
| `chat` | চ্যাট | Chat | HIGH (sound) |
| `campaigns` | ক্যাম্পেইন | Campaigns | DEFAULT |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)
- [ ] Primer rows announced as one unit ("নোটিশ — স্কুলের ঘোষণা…"); switches announce state ("চালু / বন্ধ")
- [ ] Foreground banner is announced via accessibility live region without stealing focus

## 8. Offline Behaviour

Registration and preference writes are the offline surfaces; receiving pushes is provider-driven
and needs no app connectivity at send time.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Device registration (post-login/post-permission) | Yes — persisted intent, replayed on connectivity | Server upsert by unique token is idempotent — replay-safe |
| Preference toggle (PATCH) | Yes — optimistic UI + queue | Last write wins (single-user setting); server value refetched on reconnect |
| Logout device cleanup | Yes — retried silently | `DELETE` is idempotent (404 treated as success) |
| Opened report | No — fire-and-forget, dropped when offline | Idempotent server-side; a later duplicate tap is a no-op |
| Receiving pushes | n/a — FCM/Expo hold and deliver on reconnect (provider-side) | Nothing to reconcile in-app |

## 9. Task Checklist

- [ ] `NTF-AP-001` expo-notifications setup: 3 Android channels (bn+en names, §6 table) registered at app start; iOS permissions config
- [ ] `NTF-AP-002` Permission primer `/(modals)/notifications-primer` — value-first bn/en explainer, in-context OS ask, later/denied/permanent-denied states
- [ ] `NTF-AP-003` Device registration on login (idempotent `POST /notifications/devices`) + token-rotation re-register + foreground `last_seen_at` heartbeat
- [ ] `NTF-AP-004` Logout cleanup (`DELETE /notifications/devices/{id}`) — silent retry, never blocks logout
- [ ] `NTF-AP-005` Notification settings `/settings/notifications` — 3 `PrefToggleRow` switches, optimistic PATCH, channel alignment, device row
- [ ] `NTF-AP-006` Foreground behaviour — in-app banner (no tray duplicate), auto-dismiss, tap = deep link
- [ ] `NTF-AP-007` Deep-link handling per §2.4 map — cold/warm/background routes, auth gate parking, unknown-type fallback
- [ ] `NTF-AP-008` Opened reporting on directed tap (`POST /notifications/deliveries/{id}/opened`, fire-and-forget)
- [ ] `NTF-AP-009` Badge management — per-class unread on Notices tab, clear-on-open
- [ ] `NTF-AP-010` `notifications.*` + `validation.notifications.*` bn/en catalogs wired; payload key resolution with `strings` fallback
- [ ] `NTF-AP-011` Maestro specs for `06` §9 E2E: pilot test push → tap → lands on target; mute toggle suppresses display
