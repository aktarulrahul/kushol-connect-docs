# Communication Engine — App Tasks (Mobile)

**Module:** `05-communication-engine`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
> English, 360px-first layouts.

> **Visual direction (owner, 2026-09-30):** CircleUp UI kit layout + WhatsApp chat behaviour, in
> Kushol teal. Chat list, chat screen, composer, group header and notice cards follow
> `docs/design-reference/README.md` §6.2–§6.3 (reference screens in `docs/design-reference/mobile-circleup/`).

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/chat` | Chat home — segmented Official · Custom · DMs | Verified (Pending → gate) | none (tab root) |
| 2 | `/(tabs)/chat/requests` | Message Request inbox (received + sent) | Verified | push `type=message_request` |
| 3 | `/groups/[id]` | Group chat screen (official & custom) | Verified member | push topic `section-{id}` / `message.new` payload |
| 4 | `/messages/[peerId]` | DM screen (same component as #3, dm room) | Verified (per request rules) | push `type=dm` · tuition-match deep link (module 10) |
| 5 | `/(tabs)/notices` | Notices list (pinned first; campaigns section fed by module 13) | Verified | push topic `school-{id}` / `section-{id}` |
| 6 | `/notices/[id]` | Notice detail + attachment viewer | Verified member of scope | push `type=notice` |
| 7 | `/(modals)/media-viewer` | Image/PDF viewer (shared) | Verified | in-app only |
| 8 | `/(modals)/group-new` | Create club group (custom) | Verified | none |

## 2. Screen Breakdown

### 2.1 Chat home — `/(tabs)/chat`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ কুশল            [🔔] [bn⇄en]  (header) │
│ ┌─────────┬─────────┬─────────┐        │
│ │ অফিসিয়াল │  ক্লাব   │  ডিএম   │ seg.  │
│ └─────────┴─────────┴─────────┘        │
│ ┌────────────────────────────────────┐ │
│ │ অবস বি১০ · বিজ্ঞান        (badge 3)│ │
│ │ স্যার: আগামীকাল টেস্ট আছে …  ১০:২৪ │ │
│ ├────────────────────────────────────┤ │
│ │ 🔒 মেসেজ রিকোয়েস্ট (২)  — banner   │ │  ← only when pending > 0
│ ├────────────────────────────────────┤ │
│ │ ডিবেট ক্লাব (approval: অপেক্ষায়)    │ │
│ └────────────────────────────────────┘ │
│ [ Chat ][ Notices ][ AI Hub ][ Market ]│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `SegmentedTabs` | Client | module 02 primitive; Official/Custom/DMs (PRD §4B) |
| `GroupRow` | Client (TanStack Query) | avatar, name, last message preview (bn font), unread badge, time via `Intl` bn |
| `RequestBanner` | Client | links to `/(tabs)/chat/requests`; hidden when zero pending |
| `ApprovalBadge` | Client | "অনুমোদনের অপেক্ষায় / Pending approval" chip on own pending clubs |
| `VerifiedGate` | Client | full-screen NOT_VERIFIED state (below) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton rows matching `GroupRow` layout; no blocking spinners |
| Empty | Official: "এখনো কোনো মেসেজ নেই — কথোপকথন শুরু করুন / No messages yet — start the conversation" · Custom: "ক্লাব তৈরি করুন / Create a club" primary action · DMs: "ক্লাসমেটদের সাথে কথা বলুন / Message a classmate" |
| Error | Retry + support path; cached rows stay visible |
| Offline | Stale list served from cache + offline banner (§8) |
| Pending verification | `VerifiedGate`: "আপনার অ্যাকাউন্ট এখনো ভেরিফাই হয়নি / Your account isn't verified yet" + how-to (module 03 copy) |
| Success | Unread badge clears on group open |

### 2.2 Group chat screen — `/groups/[id]` (also `/messages/[peerId]`)

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  অবস বি১০ · বিজ্ঞান   ✓ডেমো স্কুল     │ ← group name + verified school
│    ৩৮ জন · টাইপ করছেন…       [⌄]       │    branding (trust signal)
├────────────────────────────────────────┤
│ ── আজ, ৩০ সেপ্টেম্বর ──                │ ← bn date separators
│ ┌──────────────────────────┐           │
│ │ মিসেস রহিমা (শিক্ষক)      │           │
│ │ কেউ খাতা জমা দেয়নি?      │ ✓✓ দেখা হয়েছে│ ← moderator tag, seen state
│ │ ১০:০২                    │           │
│ └──────────────────────────┘           │
│           ┌──────────────────────────┐ │
│ │          │ আমি করেছি স্যার 🙏       │ │
│ │ 🕐 পাঠানো হচ্ছে… ১০:০৩   │           │ ← optimistic clock state
│           └──────────────────────────┘ │
│           ┌──────────────────────────┐ │
│ │          │ [🖼 ছবি]  ✓ ১০:০৪        │ │ ← confirmed image w/ thumb
│           └──────────────────────────┘ │
│ ┌────────────────────────────────────┐ │
│ │[📎][🖼][🎤]  মেসেজ লিখুন…    [➤]   │ │ ← composer, thumb zone
│ └────────────────────────────────────┘ │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `MessageList` (inverted FlatList) | TanStack Query infinite + WS events | 50/page, `before` cursor; date separators; Hind Siliguri everywhere |
| `MessageBubble` | Client | states: SENDING (clock) → SENT (✓) → SEEN (✓✓/accent); tombstone "মেসেজ মুছে ফেলা হয়েছে / Message deleted"; long-press → reply/copy/delete (within window) |
| `Composer` | Client | text input + attach image/PDF/voice buttons; keyboard-aware; disabled → `CONFLICT` (archived) shows notice |
| `VoiceRecorderSheet` | Client | hold-to-record, waveform, duration, cancel/send; ≤ 5 min enforced |
| `ImageViewer` / `PdfViewer` | Client modal | short-lived R2 URL; "recovering attachment" state when archived |
| `GroupHeader` | Client | member count, typing indicator, school verified badge (never fake) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton bubbles (alternating sides) matching final layout |
| Empty | "এখনো কোনো মেসেজ নেই — কথোপকথন শুরু করুন / No messages yet — start the conversation" |
| Error (history) | Inline retry row; cached page stays rendered |
| Error (send) | Bubble → red accent + tap-to-retry; input text never lost |
| Offline | Queued bubbles show clock + banner "অফলাইন — ইন্টারনেট চালু হলে পাঠানো হয়ে যাবে / Offline — will send when online" |
| Not a member / `FORBIDDEN` | "আপনি এই গ্রুপের সদস্য নন / You're not a member of this group" |
| Pending verification | `VerifiedGate` (read-only refused, `NOT_VERIFIED` copy) |
| Success | `message.ack` morphs temp bubble → confirmed (no flash/dup) |

### 2.3 Message Request inbox — `/(tabs)/chat/requests`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  মেসেজ রিকোয়েস্ট                     │
│ ┌────────────────────────────────────┐ │
│ │ করিম আহমেদ · অন্য স্কুল            │ │
│ │ "আসসালামু আলাইকুম, টিউশনের ব্যাপারে…" │ │
│ │ ✔ গ্রহণ করুন      ✕ বাতিল করুন     │ │
│ └────────────────────────────────────┘ │
│ (sent section: "পাঠানো: অপেক্ষায় / বাতিল")│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `RequestCard` | TanStack Query mutation | accept → navigates to `/messages/[peerId]`; decline → card flips to declined |
| `SentRequests` | Client | pending/expired/declined states of outgoing requests |

**States**

| State | Behaviour |
| --- | --- |
| Empty | "কোনো রিকোয়েস্ট নেই / No requests" |
| Accepted | Opens DM room instantly (BR-004) |
| Declined | Sender sees "রিকোয়েস্টটি গ্রহণ করা হয়নি। / Your request wasn't accepted." |
| Expired | "মেয়াদ শেষ / Expired" chip |

### 2.4 Notices — `/(tabs)/notices` and `/notices/[id]`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ নোটিশ ও ইভেন্ট                          │
│ ┌────────────────────────────────────┐ │
│ │ 📌 অর্ধবার্ষিক পরীক্ষার রুটিন      │ │ ← pinned first
│ │ ডেমো উচ্চ বিদ্যালয় · আজ ০৯:০০      │ │
│ │ [PDF সংযুক্ত]                      │ │
│ ├────────────────────────────────────┤ │
│ │ ক্লাস টেস্ট — অধ্যায় ৪         বি১০│ │ ← section scope tag
│ └────────────────────────────────────┘ │
│ ── সিটি ক্যাম্পেইন (মডিউল ১৩) ──        │ ← separate section, 13's API
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `NoticeRow` | TanStack Query (`notices:school:{id}` tag) | pin icon, scope badge (স্কুল/সেকশন), attachment chip, bn date |
| `NoticeDetail` | Client | title, author + role, `published_at`, body (plain text), attachment viewer |
| `CampaignSection` | Client | renders module-13 payloads (Events); **not** backed by `notices` (seam, US-012) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton rows |
| Empty | "কোনো নোটিশ নেই / No notices yet" |
| Removed | Detail shows "নোটিশটি সরিয়ে নেওয়া হয়েছে / This notice was removed" |
| Attachment archived | "সংযুক্তি পুনরুদ্ধার করা হচ্ছে… / Recovering attachment…" then viewer opens |
| Success | Push deep link lands directly on `/notices/[id]` |

### 2.5 Create club — `/(modals)/group-new`

Form: name (3–60) + optional description → `POST /chat/groups` → success screen
"অনুরোধ পাঠানো হয়েছে — অনুমোদনের অপেক্ষায় / Request sent — awaiting approval" (BR-010).

## 3. Forms & Input

| Field | Control | zod rule (from `packages/shared`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Message body | auto-growing text input | `validation.chat.body_length` (1–4000) | last draft (per group, persisted) | — |
| `client_msg_id` | generated uuid v4 per send | `validation.chat.client_msg_id` | new per message | — |
| Club name | text input | `validation.chat.group_name_length` (3–60) | — | create-club modal |
| Notice compose (teacher in-app section notices) | title + body inputs | `validation.notices.title_length` · `body_length` | — | teacher role only |
| Media pick | image picker / document picker / recorder | `validation.media.*` (kind, caps) | image compressed to ~1 MB target | attach buttons |

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

WS event → store mapping: `message.new` appends to the room's Query cache;
`message.ack` swaps the temp bubble by `client_msg_id`; `message.read`/`presence.update`/
`typing` patch lightweight zustand slices (never re-fetch); `notice.new` invalidates
`notices:*` queries. Catch-up after reconnect: refetch the newest page from the local
latest cursor, then continue older pagination lazily.

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Bubble send-state morph | opacity/size crossfade (≤ 150 ms) | `message.ack` / read event | temp→confirmed→seen progression | instant swap |
| New message insert | layout shift (FadeIn) | WS `message.new` | message arrival | instant append |
| Typing dots | 3-dot loop | `typing` events | peer activity | static "টাইপ করছেন… / typing…" text |
| Tombstone | fade-in | `message.deleted` | retraction | instant swap |
| Request banner | slide-down | pending > 0 | actionable inbox | instant show |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only,
unless the module's `02` §7 says otherwise.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; composer thumb-reachable; bubbles max ~78% width; seen ticks inline, not overflow |
| ≥ 600px (tablet) | Two-pane: group list + open conversation (chat home + `/groups/[id]`) |
| Low-end Android / 3G | Images compressed to ~1 MB target before upload; 50/page lists; Hermes; no blocking loads; media uploads cancellable |
| Bengali content | Hind Siliguri renders; no clipped glyphs; `Intl` bn dates/numerals (`১০:২৪`) |
| Voice playback | Continues when screen locks; respects silent mode on iOS |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)
- [ ] Bubbles announced as one unit ("বার্তা — <নাম>, <সময়>, <অবস্থা>"); date separators as headings
- [ ] Voice recorder announces recording state + duration live

## 8. Offline Behaviour

Chat is the module's core offline surface. The local queue (zustand + MMKV persist) stores full
payload + `client_msg_id`; replay order is per-group FIFO.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Send text/media message | Yes — bubble stays SENDING with banner | Replayed in order; server dedupes by `client_msg_id` (BR-008); ack swaps state |
| Mark read | Yes | Latest `last_read_message_id` wins (idempotent PATCH) |
| Accept/decline request | No — refused with offline notice (safety-relevant action) | — |
| Open media (archived/not cached) | No | Retry on restore; placeholder shown |
| Create club / publish notice | No — requires connectivity | Explained inline, input preserved |
| History pagination | Reads served from cache | Catch-up refetch from newest local cursor after reconnect |

## 9. Task Checklist

- [ ] `COM-AP-001` Chat home tab with Official/Custom/DMs segments + unread badges + request banner
- [ ] `COM-AP-002` WS client: connect/JWT, room subscribe, heartbeat, exponential backoff reconnect + re-subscribe + catch-up
- [ ] `COM-AP-003` Group chat screen: `MessageList`, date separators, Hind Siliguri, 360px layout
- [ ] `COM-AP-004` Optimistic `MessageBubble` with SENDING→SENT→SEEN states + `client_msg_id` echo swap
- [ ] `COM-AP-005` Composer + attach sheet (image/PDF/voice); keyboard-aware
- [ ] `COM-AP-006` Image pipeline: compress to ~1 MB target → presign → PUT R2 → confirm → send message
- [ ] `COM-AP-007` Voice recorder sheet (hold-to-record, ≤ 5 min, compress, background playback)
- [ ] `COM-AP-008` PDF picker + viewer (system viewer, short-lived URL)
- [ ] `COM-AP-009` Media viewer modal + "recovering attachment" archived state
- [ ] `COM-AP-010` Read receipts UI (own ticks + per-message seen counts) via `message.read`
- [ ] `COM-AP-011` Typing indicator (send throttle 1/3 s, 4 s expiry)
- [ ] `COM-AP-012` DM flow: same-school instant open; out-of-network → request composer + pending state
- [ ] `COM-AP-013` Message Request inbox screen (accept/decline/sent states)
- [ ] `COM-AP-014` Notices tab (pinned first, scope badges, campaign section seam) + notice detail + push deep links
- [ ] `COM-AP-015` Create-club modal with pending-approval success state
- [ ] `COM-AP-016` Message delete (long-press; author ≤ 15 min rule surfaced; tombstone render)
- [ ] `COM-AP-017` Offline queue (persisted) + offline banner + replay-on-reconnect
- [ ] `COM-AP-018` `VerifiedGate` + all bn/en strings from `chat.*`/`notices.*` catalogs
- [ ] `COM-AP-019` Reduced-motion variants for all §5 animations
- [ ] `COM-AP-020` Maestro specs for §9 of `06` (E2E golden paths)
