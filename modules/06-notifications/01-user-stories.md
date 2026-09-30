# Notifications — User Stories

**Module:** `06-notifications`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Kushol Connect's push backbone: FCM topic fan-out mirroring City → School → Section for mass
messages (notices, city events, campaigns), per-device directed push via the Expo push API for
personal messages (DMs, tuition matches, payment/test results), deep links that land every tap on
the right screen, and a delivery log. The delivery half of the Phase-1 exit criterion ("a verified
student … receives a notice by push"), serving `brd.md` §6 Scalability — FCM topic fan-out at
scale is this module's reason to exist.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | May register a device, but hierarchy topics are not subscribed until verified (bindings only exist via module 04 on verification); directed pushes (e.g. verification reminder, module 03) can still reach them |
| Student | Receives notice/chat/match/test pushes; taps deep links; mutes a notification class in Settings |
| Guardian | Same as Student — primary consumer of school notices and fee-payment result pushes |
| Teacher | Same as Student; their section notice publishes fan out to `section-{id}` |
| School Admin | Governs only their own school (tenant); sends test pushes to self/one section; views per-school delivery aggregates (counts only) |
| Super Admin | Platform-level delivery oversight; sends test pushes; no per-school content access |
| Vendor / EdTech brand | N/A — vendors never send pushes directly; campaigns they fund reach users only via module 13 calling this module's exports |
| System (jobs, webhooks) | `fanout.send` batching worker, `tokens.prune` nightly cleanup, `topics.backfill` for devices registered pre-verification, provider receipt polling |

> The five roles (Super Admin / School Admin / Teacher / Student / Guardian) plus Vendors are
> defined by module 03 (`03-identity-access`). Verification gates every participatory action
> (`prd.md` §5.1) — here it gates topic subscription and delivery.

## 3. Scope

**In scope**

- `device_tokens`: registration (idempotent), refresh (`last_seen_at`), logout cleanup, pruning of invalid/expired tokens.
- Mass fan-out via **FCM topics** (`city-{cityId}` / `school-{schoolId}` / `section-{sectionId}`, bindings owned by module 04) for notices, city events and campaigns — fire-and-forget at scale.
- Directed per-device push via the **Expo push API** (DMs, tuition matches, payment results, test results, admin test pushes) — full lifecycle tracking queued → sent → delivered → opened.
- Deep-link payload contract: message KEY + ids only (never message bodies), resolved on-device so pushes render in the user's locale (bn default / en).
- `notification_preferences`: one muted flag per class (`notices` / `chat` / `campaigns`), aligned 1:1 with the three Android notification channels.
- Delivery log (`notification_deliveries`) + open reporting; own list + tenant-scoped admin aggregates; test-push endpoint for pilots (`POST /admin/notifications/test`).

**Out of scope** (explicit — prevents scope drift)

- Notice authoring/campaign creation UI — modules 05/07 (notices) and 13 (campaigns); they call `notify.BroadcastTopic`/`notify.SendToUser`, never FCM directly.
- Web push (module 07 uses in-app toasts only) and email/SMS channels (SMS is auth-OTP only, module 03).
- In-app notification inbox/center screen — Phase 1 delivers via system tray + deep links; an inbox is a future module.
- Quiet-hours scheduling (Open Question 1) and ad targeting/audience building (module 13 consumes module 04 segments).

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | `jobs.Enqueue` + worker registration, `audit.Record`, RFC-7807 error envelope, health endpoints |
| 02 design-system | bn/en catalogs (`notifications.*`, `validation.*`), tokens, RN primitives |
| 03 identity-access | Auth chain (authenticate → role claims → tenant-scope), `users` (locale bn/en, status PENDING/VERIFIED/SUSPENDED), `RequireVerified` |
| 04 organization-hierarchy | `fcm_topic_bindings` table + `hierarchy.ResolveUserNodes(userId)`; auto-grouping on verification is the subscription trigger point |
| 05 communication-engine | `chat.PostNotice(...)` triggers the notice push; notice scopes `school\|section`; in-app + WS delivery remains the fallback when push degrades |

---

## 4. User Stories

### `NTF-US-001` — Device registers for push on login

**Priority:** P0 · **Traces:** PRD §6 (push row, `tech-stack.md`) / `prompt.txt` §3 · **Depends on:** 03

**Story** — As a **logged-in user**, I want **my device registered for push automatically after I sign in**, so that **school messages reach me without any setup**.

**Acceptance criteria**

- **Given** I am authenticated and grant notification permission (via the in-context primer, `NTF-AP-002`), **when** the app obtains the push token, **then** `POST /notifications/devices` stores it with `platform` + `app_version`, and the same token re-registered updates `last_seen_at` without creating a duplicate row.
- **Given** I sign in on a second device, **when** both tokens exist, **then** directed pushes reach both devices; the settings screen shows my registered devices.
- **Given** I log out, **when** cleanup runs, **then** `DELETE /notifications/devices/{id}` removes my token from this device — no pushes go to a phone I no longer hold.

### `NTF-US-002` — Verified student's device auto-subscribed to city/school/section topics

**Priority:** P0 · **Traces:** BR-01 (`brd.md` §5) / `brd.md` §6 (FCM topics) · **Depends on:** 04

**Story** — As a **verified student**, I want **my device subscribed to my city, school and section topics automatically**, so that **official notices find me the moment they are published**.

**Acceptance criteria**

- **Given** I am verified (module 04 created enrollment + topic bindings), **when** my device registers, **then** the device is subscribed to exactly `city-{cityId}`, `school-{schoolId}` and `section-{sectionId}` resolved from `hierarchy.ResolveUserNodes` / `fcm_topic_bindings` — no other topics.
- **Given** my device registered while I was still PENDING, **when** verification completes, **then** the `topics.backfill` job subscribes the bound topics without me doing anything.
- **Given** a year-end migration moves me to a new section, **when** module 04 re-binds, **then** my devices land on the new `section-{id}` topic and leave the old one.

### `NTF-US-003` — School Admin notice reaches all school members as push within seconds

**Priority:** P0 · **Traces:** PRD §5.1 / `brd.md` §6 (scalability) · **Depends on:** 05

**Story** — As a **School Admin**, I want **my published notice pushed to every school member within seconds**, so that **exam dates and fee deadlines never depend on someone opening the app**.

**Acceptance criteria**

- **Given** module 05 publishes a school notice and calls `notify.BroadcastTopic("school-{schoolId}", payload)`, **when** FCM accepts the topic message, **then** every subscribed member device renders the push, p95 ≤ 5 s at pilot scale (3 schools ≈ 6k devices), and the send is recorded as one `sent` delivery row.
- **Given** FCM returns 5xx, **when** the dispatch fails, **then** the job retries with backoff (×3 → dead-letter) and the notice is still fully visible in-app (`NTF-BR-005`, degraded never fatal).
- **Given** the notice is section-scoped, **when** it publishes, **then** only `section-{sectionId}` devices receive it — the rest of the school is not disturbed.

### `NTF-US-004` — Tapping a push lands on the right screen (deep links)

**Priority:** P0 · **Traces:** PRD §5.4 / `prompt.txt` §3 · **Depends on:** NTF-US-003, NTF-US-005

**Story** — As a **push recipient**, I want **tapping a notification to open exactly the content it refers to**, so that **I never hunt through tabs for what buzzed my phone**.

**Acceptance criteria**

- **Given** a notice push, **when** I tap it (app cold, warm or background), **then** the app opens `/notices/{noticeId}` inside the Notices tab.
- **Given** a DM push, **when** I tap, **then** `/messages/{peerId}` opens; a payment-result push opens the receipt; a tuition-match push opens the chat with the requester; a test-result push opens the AI Hub test.
- **Given** a push with an unknown/unroutable type or a deleted target, **when** I tap, **then** the app opens the home tab with a gentle fallback message — never a crash or a blank screen (full map in `05-app-tasks.md` §2.4, schema-frozen by `NTF-INT-007`).

### `NTF-US-005` — Directed push renders in the user's locale

**Priority:** P0 · **Traces:** `prompt.txt` §2 #6 (bilingual) · **Depends on:** NTF-US-001

**Story** — As a **guardian whose app language is Bangla**, I want **pushes to appear in Bangla**, so that **the notification feels like my app, not a foreign system**.

**Acceptance criteria**

- **Given** the payload carries message key `notifications.dm_new` + bn/en string pairs, **when** my device (locale bn) renders it, **then** the tray shows "করিম আহমেদ আপনাকে একটি মেসেজ পাঠিয়েছে" — resolved on-device, no network round-trip.
- **Given** the same push reaches an en-locale device, **when** it renders, **then** it shows "Karim Ahmed sent you a message".
- **Given** a key missing from the on-device catalog (old app version), **when** rendering falls back, **then** the generic app title + the `en` body render — never raw key text like `notifications.dm_new`.

### `NTF-US-006` — User mutes a notification class in settings

**Priority:** P1 · **Traces:** README module 06 default (channel strategy) · **Depends on:** NTF-US-001

**Story** — As a **student drowning in campaign buzzes**, I want **to silence one notification class (e.g. campaigns) without losing notices**, so that **my phone serves my priorities**.

**Acceptance criteria**

- **Given** I toggle Campaigns off in Settings → Notifications, **when** the `PATCH /notifications/preferences` lands, **then** `notification_preferences(campaigns).muted = true` and the matching Android channel is disabled on-device — the two stay aligned.
- **Given** I muted `chat`, **when** a directed DM push is attempted, **then** the server skips my devices entirely (`NTF-BR-004`); for topic classes the device suppresses display (channel-aligned).
- **Given** I re-enable the class, **when** the next push arrives, **then** it renders normally — no restart needed.

### `NTF-US-007` — Delivery log records opened

**Priority:** P1 · **Traces:** module README row (delivery tracking) · **Depends on:** NTF-US-004

**Story** — As a **user**, I want **my notification history visible with what I opened**, so that **I can find a push I dismissed**.

**Acceptance criteria**

- **Given** a directed push was delivered, **when** I tap it, **then** the app reports `POST /notifications/deliveries/{id}/opened`, the row flips to `opened` with `opened_at`, and the call is idempotent on retry.
- **Given** I open Settings → Notification history, **when** `GET /notifications/deliveries` loads, **then** I see my own pushes newest-first, paginated (max 100/page) — never another user's.
- **Given** a School Admin reviews delivery aggregates, **when** they query the tenant-scoped admin variant, **then** they see status counts + a log for their school only (`TENANT_MISMATCH`/404 otherwise) — counts and metadata, never bodies.
- **Given** a topic (fire-and-forget) send, **when** anyone inspects history, **then** only `sent` state exists for it — no per-recipient tracking at scale (`NTF-BR-005`).

### `NTF-US-008` — Token refresh/expiry cleanup

**Priority:** P0 · **Traces:** `brd.md` §6 (operability) · **Depends on:** NTF-US-001

**Story** — As the **platform operator**, I want **invalid and stale device tokens pruned automatically**, so that **fan-out never wastes provider quota on dead devices and delivery stats stay honest**.

**Acceptance criteria**

- **Given** a provider rejects a token as invalid/unregistered (app uninstalled), **when** the send result returns, **then** the token is pruned (`pruned_at` set), its delivery marked `failed`, and it is never targeted again.
- **Given** a token with `last_seen_at` older than the prune threshold (default 90 days), **when** the nightly `tokens.prune` job runs, **then** it is pruned idempotently.
- **Given** the same user reinstalls the app, **when** a fresh token registers, **then** delivery resumes with no residue of the old token.

### `NTF-US-009` — Admin sends a test push (pilot tooling)

**Priority:** P1 · **Traces:** README Phase-1 exit (pilot 2–3 schools) · **Depends on:** NTF-US-002

**Story** — As a **School Admin onboarding a pilot school**, I want **to send a clearly-marked test push to myself or one section**, so that **I can prove end-to-end delivery before the principal asks**.

**Acceptance criteria**

- **Given** I am School Admin, **when** I call `POST /admin/notifications/test` with `target=self` or `target=section` (my own tenant only), **then** the chosen devices receive a push visibly marked "টেস্ট / Test" with the chosen class's channel.
- **Given** a School Admin targets another school's section, **when** the request lands, **then** it is refused with `TENANT_MISMATCH` — no cross-tenant sends.
- **Given** repeated test sends, **when** the rate limit trips, **then** further calls return `RATE_LIMITED` (pilot tooling must not become a spam channel).

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `NTF-BR-001` | Only VERIFIED users' devices are subscribed to hierarchy topics; subscriptions derive exclusively from module 04 bindings/`ResolveUserNodes` (PENDING → `topics.backfill` on verification; SUSPENDED → unsubscribed, no pushes) | Service + `topics.backfill` job |
| `NTF-BR-002` | Device registration requires authentication; a token belongs to exactly one user (unique), re-registration is an upsert; users may hold multiple devices | DB unique index + service |
| `NTF-BR-003` | Push payloads carry a message KEY, ids and deep link only — never DM/chat message bodies; content is fetched in-app after auth (`brd.md` §6 privacy) | Payload builder (`NTF-BE-011`), tested by `NTF-UT-001` |
| `NTF-BR-004` | Preferences gate by class: muted `chat`/directed sends are skipped server-side; muted topic classes (`notices`/`campaigns`) are suppressed on-device via the channel-aligned flag (topic fan-out cannot see per-user prefs) | `notify.SendToUser` + app display suppression |
| `NTF-BR-005` | Delivery tracking by path: topic sends are fire-and-forget (one `sent`/`failed` row per dispatch, no per-recipient tracking); directed sends track `queued → sent → delivered → opened`; both record `failed` terminal state | Service + `notification_deliveries` CHECK |
| `NTF-BR-006` | Invalid/expired tokens are pruned on first provider rejection; stale tokens (`last_seen_at` > prune age) by nightly job; pruned tokens are never re-targeted | `fanout.send` result handler + `tokens.prune` |
| `NTF-BR-007` | Test pushes: targets are `self` or one section of the caller's own tenant; payload visibly marked `type=test`; rate-limited per admin | `SendTestPush` + rate limiter |
| `NTF-BR-008` | Deliveries are readable by their recipient; admin variants are tenant-forced by claim (School Admin → own school, Super Admin → platform with optional filter); cross-tenant reads are `TENANT_MISMATCH`/404 | Tenant-scoped repository (every query) |
| `NTF-BR-009` | Topic names come only from module 04's `fcm_topic_bindings` (`city-{id}` / `school-{id}` / `section-{id}`); this module never invents or accepts client-supplied topic names | `notify.BroadcastTopic` guard (`NTF-UT-004`) |

> Content-accuracy (`prompt.txt` §12): this module authors no publishable content — payloads carry
> ids + i18n keys resolved from the shared catalogs, so no invented copy can leak into pushes;
> test pushes are visibly marked and rate-limited.

## 6. Validation Rules

| Field | Rule | Message key (`packages/shared` i18n catalog) |
| --- | --- | --- |
| Device `token` | Required, 1–4096 chars, no whitespace; `ExponentPushToken[…]` or FCM format | `validation.notifications.token_invalid` |
| Device `platform` | `ios` \| `android` (exact) | `validation.notifications.platform_invalid` |
| Device `appVersion` | Optional, ≤ 32 chars | `validation.notifications.app_version` |
| Preference `class` | `notices` \| `chat` \| `campaigns` (exact) | `validation.notifications.class_invalid` |
| Preference `muted` | Boolean, required on PATCH | `validation.notifications.muted_required` |
| Deliveries paging | `page ≥ 1`; `pageSize` 1–100 (default 20) | `validation.notifications.page_size` |
| Test push `target` | `self` \| `section`; `section` requires in-tenant `sectionId` | `validation.notifications.target_invalid` |
| Opened path `deliveryId` | UUID; delivery must belong to caller and be provider-directed | `validation.notifications.delivery_not_found` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (app)
> generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any `/notifications/*` endpoint | `UNAUTHENTICATED`, no side effect |
| 2 | Cross-tenant delivery read (School Admin A → school B) | `TENANT_MISMATCH`/404, no data leaked (`NTF-IT-004`) |
| 3 | Token invalid mid-batch (app uninstalled) | That device pruned + delivery `failed`; remaining devices in the batch still sent (`NTF-IT-003`) |
| 4 | FCM 5xx on topic dispatch | Retry ×3 backoff via `jobs`, then dead-letter; notice remains in-app + WS (degraded, never fatal) |
| 5 | Expo push API down | Directed sends stay `queued`; jobs drain on recovery; senders see nothing (send already succeeded upstream) |
| 6 | Device offline / app killed at send time | FCM/Expo hold and deliver on next connectivity — provider-side queuing, no server action |
| 7 | Same token registered twice (reinstall, re-login) | Upsert on unique token — one row, `last_seen_at` refreshed |
| 8 | Mute flipped while a topic send is in flight | Best-effort: in-flight push may render; every subsequent send respects the new state |
| 9 | Suspended user (module 03) | Devices unsubscribed; directed sends skipped; re-verification restores |
| 10 | Push with unknown `payload.type` or unroutable deep link | App opens home tab with fallback message; event logged; no crash |
| 11 | Deep link target deleted (notice removed) | Module 05 "নোটিশটি সরিয়ে নেওয়া হয়েছে / This notice was removed" state renders |
| 12 | Device registered while user PENDING | Token stored; no topic subscription until `topics.backfill` fires post-verification |

## 8. Reporting Needs

- Module 07 dashboards (School/Super Admin): pushes per day per school, delivery status counts
  (`sent`/`delivered`/`opened`/`failed`) — aggregates only via the admin deliveries endpoints,
  never message bodies.
- Module 13 campaign analytics: open rate per campaign (aggregates on `campaigns`-class directed
  deliveries), consumed read-only.
- This module ships no dashboard of its own.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Quiet hours for push delivery (e.g. 22:00–07:00 local, which classes)? | Rahul | Open (`TODO: Confirm`) | None at launch — pushes deliver immediately; Android channels let users silence classes per-OS |
| 2 | Android channel strategy final copy | Rahul | Open | ONE channel per class — `notices` / `chat` / `campaigns` (3 channels, bn+en names), matching `notification_preferences` 1:1 |
| 3 | Fan-out path + tracking semantics confirmation | Rahul | Open | Mass (school/section/city) via FCM topics fire-and-forget; directed via Expo push API tracked `queued→sent→delivered→opened` |
| 4 | Stale-token prune age | Rahul | Open | 90 days since `last_seen_at` (config, not code) |
| 5 | Delivery-row retention | Rahul | Open | 180 days, then aggregate-and-delete job (config) |
