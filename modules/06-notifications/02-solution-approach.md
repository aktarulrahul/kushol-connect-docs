# Notifications — Solution Approach

**Module:** `06-notifications` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `device_tokens` | One row per physical device: push token (Expo/FCM), `platform ios\|android`, `app_version`, `last_seen_at`, `pruned_at` soft state. Tenant scope via the owning user | Yes |
| `notification_deliveries` | One row per push dispatch: recipient (directed) or initiating actor + `topic_name` (topic send), `class`, `payload_key` + `payload_data` jsonb, `deep_link`, `status queued\|sent\|delivered\|opened\|failed`, `sent_at`, `opened_at` | Yes |
| `notification_preferences` | One row per (user, class ∈ `notices\|chat\|campaigns`) with `muted` — mirrors the three Android channels 1:1 | Yes |
| `fcm_topic_bindings` | `city-{id}` / `school-{id}` / `section-{id}` ↔ hierarchy node — the only source of topic names | No — module 04 |
| User (locale, status) | `users.locale bn\|en`, `PENDING/VERIFIED/SUSPENDED` — gates subscription and drives payload strings | No — module 03 |
| Notices / chat groups / DMs | The content the pushes point at (ids only ever enter payloads) | No — module 05 |

### 1.2 Relationships

```text
user (03) 1───* device_tokens                     (tenant scope via user)
user (03) 1───1..3 notification_preferences      (one per class, lazy-created)
user (03) 1───* notification_deliveries[directed] (user_id = recipient, topic NULL)
actor (03) 1───* notification_deliveries[topic]   (user_id = initiator, topic_name set)
city│school│section (04) 1───1 fcm_topic_bindings ──topic_name──▶ FCM topic fan-out
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-1 | `(token)` is globally unique and belongs to exactly one user; re-registration is an idempotent upsert | Unique index + `ON CONFLICT` upsert |
| INV-2 | `status` moves only forward: `queued → sent → (delivered →) opened`, or `* → failed` (terminal); `opened` only for directed rows | DB CHECK + service guard |
| INV-3 | Payloads carry key + ids + deep link only — never DM/chat bodies (`NTF-BR-003`) | Payload builder + `NTF-UT-001` |
| INV-4 | Topic names are accepted only if present in `fcm_topic_bindings` (`NTF-BR-009`) | `notify.BroadcastTopic` guard |
| INV-5 | At most one preference row per `(user_id, class)`; unknown class rejected | Unique index + CHECK |
| INV-6 | `opened_at` is write-once (idempotent open reports) | `UPDATE … WHERE opened_at IS NULL` |

## 2. Module Boundary

**Owns (writes):** `device_tokens`, `notification_deliveries`, `notification_preferences` — and
the provider client (FCM Admin SDK) which no other module may touch (04 holds no
FCM credentials; 05 only calls `notify.BroadcastTopic`).

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | Auth chain; `users.locale`, verification/status | Identity and locale are 03's source of truth |
| 04 | `fcm_topic_bindings` reads + `hierarchy.ResolveUserNodes(userId)` | Hierarchy is the data model (`brd.md` §6); bindings are 04's table |
| 05 | Trigger context (`chat.PostNotice` calls us; notice ids for deep links) | Notice authoring/moderation is 05's |
| 01 | `jobs.Enqueue`/worker registration, `audit.Record`, error envelope | Foundations own the plumbing |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4
(`notifications:devices:{userId}`, `notifications:prefs:{userId}`, `notify:bindings:{topicName}`).

## 3. Lifecycle

Fan-out flow (the module in one picture):

```text
mutation (05 PostNotice │ 10 tuition match │ 12 payment result │ 13 campaign │ 03 SLA reminder)
        │
        ▼
  notify service (06) ── payload builder: class + key + ids + deep link + bn/en strings (v1 schema)
        │
        ├─ MASS (school/section/city) ──▶ notify.BroadcastTopic(topic, payload)
        │        │ topic validated against 04 bindings (INV-4)
        │        └─▶ FCM Admin SDK topic message (fire-and-forget) ──▶ delivery row sent│failed
        │             (one row per dispatch — no per-recipient tracking, NTF-BR-005)
        │
        └─ DIRECTED (user ids) ──▶ notify.SendToUser(userId, payload)
                 ├─ prefs gate: class muted? → skip (server-side, NTF-BR-004)
                 ├─ resolve active devices (device_tokens WHERE pruned_at IS NULL)
                 ├─ delivery row per device: queued ──▶ FCM per-token send ──▶ sent
                 │        └─ client ack ▶ delivered │ invalid token ▶ failed + prune (INV-2)
                 └─ no devices → no-op (user still sees content in-app)
        │
        ▼
  01 jobs workers: fanout.send (batching, rate-aware) · tokens.prune (nightly) · topics.backfill
        │
        ▼
  app (expo-notifications): resolve key in device locale → render on the class's channel
        → tap → deep link → POST /notifications/deliveries/{id}/opened (directed only)
```

Delivery/token state machine:

```text
delivery: queued ──provider 2xx──▶ sent ──client ack──▶ delivered ──user tap──▶ opened
             └──provider 4xx invalid-token / hard error──▶ failed (terminal; token pruned if invalid)
token:    active ──provider rejection│stale(>90d)──▶ pruned (pruned_at set; never re-targeted)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| `queued` | provider accepts | `sent` | payload valid, devices active | `sent_at` set; retry cleared |
| `sent` | app message handler acks | `delivered` | directed rows only | client ack endpoint (best effort) |
| `delivered` | user taps push | `opened` | caller owns row; write-once | `opened_at` set (INV-6) |
| any | provider rejects / batch dead-letters | `failed` | retry budget exhausted | token pruned if invalid (`NTF-BR-006`) |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| App notification settings | TanStack Query → `GET/PATCH /notifications/preferences` | Stale-while-revalidate per device | `notifications:prefs:{userId}` |
| App notification history | TanStack Query paginated list | Never cached server-side (per-user audit surface) | — |
| Server device + topic-binding lookups (fan-out hot path) | — | Redis `notify:devices:{userId}` TTL 5 min · `notify:bindings:{topicName}` TTL 10 min | invalidates on register/prune · `hierarchy:school:{id}` (04's tags) |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Stale-token prune age (default 90 days) · delivery-row retention (default 180 days) | Three classes ↔ three Android channels, 1:1 (`NTF-BR-004`) |
| `fanout.send` batch size (default 500/batch FCM, 100/request Expo) · provider timeout/retry budget (10 s, ×3) | Topic naming `city-{id}/school-{id}/section-{id}` (04's contract) |
| Test-push rate limit (default 10/hour/admin) · quiet hours (future — Open Question 1) | Payload schema v1: key + ids + deep link + bn/en strings; bodies forbidden (`NTF-BR-003`) |
| — | Fire-and-forget semantics for topic sends (`NTF-BR-005`); deep-link route map additive only (`NTF-INT-007`); prefs gate: server-side for directed, on-device for topic classes |

## 6. Security

Entry points (all under `/api/v1`, RFC-7807 errors): `POST /notifications/devices`,
`DELETE /notifications/devices/{id}`, `GET|PATCH /notifications/preferences`,
`GET /notifications/deliveries`, `POST /notifications/deliveries/{id}/opened`,
`GET /school|admin/notifications/deliveries`, `POST /admin/notifications/test`. Every entry runs
**authenticate → load role claims → tenant-scope** (module 03 middleware).

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| Device register/delete | Verified or pending user (auth required) | Caller may only mutate own rows — `user_id = caller`; token uniqueness is the idempotency key |
| Preferences read/patch | Authenticated user | Own rows only — no tenant read path exists |
| Own deliveries | Authenticated user | `user_id = caller` on every query |
| Admin deliveries | `SCHOOL_ADMIN` → own school (claim) · `SUPER_ADMIN` → optional `schoolId` filter | Tenant-forced join through 04 enrollments; cross-tenant → `TENANT_MISMATCH`/404 (`NTF-BR-008`) |
| Test push | `SCHOOL_ADMIN`/`SUPER_ADMIN` | Target `self` or in-tenant section only (`NTF-BR-007`) |

Privacy: payloads carry keys + ids, never DM bodies (`brd.md` §6 — content fetched in-app after
auth); provider error logs redacted of tokens; minors/guardians reachable only via their school
scope — this module adds no cross-tenant path. Rate limits: default class on device/preference
routes; stricter bucket on test pushes. `audit.Record` on test sends and admin aggregate exports.

## 7. Accessibility & Motion

OS tray/channel rendering is platform accessibility surface; in-app surfaces are covered in
`05-app-tasks.md` §5/§7: a screen-reader-readable permission primer with bn/en explainers,
labelled switches ≥ 44 pt, and a foreground banner with an instant reduced-motion variant. No web
surfaces exist (`04-frontend-tasks.md` is N/A).

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | FCM 5xx / timeout or project-wide outage | Client error, 10 s timeout, error-rate alarm | Notice push delayed or absent | `fanout.send` retries ×3 backoff → dead-letter `failed`; notices remain fully in-app + WS (05) — push is an enhancement layer, never the source of truth; queue flushes on restore |
| 2 | FCM per-token send down / degraded | 5xx on send, 10 s timeout | Directed pushes stuck `queued` | Queue drains on recovery (status-scoped scan); senders unaffected (send already succeeded upstream) |
| 3 | Invalid/expired token | FCM `UNREGISTERED` / `INVALID_ARGUMENT` on send | That device unreachable | Prune immediately (`NTF-BR-006`), mark delivery `failed`, batch continues |
| 4 | Jobs worker down | Health/lag alarm on 01 runner | Deliveries pile up `queued`; prunes/backfills miss | Workers are idempotent (status-scoped); drain on restart; alert per runbook |
| 5 | `fcm_topic_bindings` missing (user unverified) | `ResolveUserNodes` empty | No topic subscription | `topics.backfill` subscribes after verification; directed pushes unaffected |

## 9. Performance

- Volumes (pilot, `brd.md` §2 Goal 1): 3 schools × ~2,000 users ≈ 6k devices; a school notice is
  **one** FCM topic message regardless of audience size (the scalability reason this module
  exists) — FCM performs the per-device fan-out. Directed volume is modest (DMs, matches,
  payment results ≈ tens/min at pilot). App dependencies: `@react-native-firebase/app` +
  `messaging` (native FCM token; EAS development builds, no Expo Go) alongside `expo-notifications`
  (`tech-stack.md`). Email volume (OTP + opted-in notifications) goes through HestiaCP SMTP and is
  paced by the `email.send` job.
- Budgets: topic dispatch accepted p95 ≤ 500 ms server-side; end-to-end push render p95 ≤ 5 s
  (FCM best-effort, measured with the pilot test-push tool); directed send→`sent` p95 ≤ 2 s.
- Hot queries: `device_tokens (user_id, pruned_at)` → directed fan-out; `unique(token)` →
  registration upsert; `notification_deliveries (user_id, created_at DESC)` → history;
  `(status, created_at)` → worker scans; admin aggregates join 04 enrollments (indexed there).
- Batching: FCM batch limit 500 tokens/message (topic subscribe + multicast) — `fanout.send`
  chunks and paces to stay inside provider quotas; retries carry only the un-sent remainder.

## 10. Alternatives Considered

### Option A — FCM topics only · Option B — per-device fan-out only · Option C — both, per class (chosen)

| | A: topics only | B: per-device only | C: both per class (chosen) |
| --- | --- | --- | --- |
| Advantages | One message fans out to thousands — `brd.md` §6 exactly; zero fan-out cost server-side | Full per-recipient tracking, prefs, personalization; no topic state to manage | Mass = cheap/scaleable; directed = trackable/personal |
| Disadvantages | Fire-and-forget: no delivered/opened, no per-user prefs at send time; DMs would leak content into topics | SendToUser must enumerate 6k+ devices per notice — minutes of fan-out, provider quota burn, no `brd.md` §6 story | Two providers/paths to test and monitor (mitigated: one service, two thin clients) |
| Complexity / weight | Low | High at scale | Medium — each class uses exactly one path |

**Recommendation:** C — mass classes (`notices`, `campaigns` broadcasts) go topic; directed
messages (DMs, matches, payment/test results, admin tests) go per-device via **FCM HTTP v1 token
sends** (same provider, see below). ADR in this module's `07-progress.md`.

### Option A — Expo push API for directed + FCM topics for mass · Option B — FCM for both (chosen, revised 2026-09-30)

| | A (original draft) | B (chosen) |
| --- | --- | --- |
| Advantages | Expo receipts built in | **One token per device serves both paths**; one provider, one credential; topics work on iOS |
| Disadvantages | **Broken for iOS topics:** FCM topic subscription needs an FCM registration token, but Expo push tokens are not FCM tokens and `getDevicePushTokenAsync` on iOS returns a raw APNs token that FCM topics cannot use — iOS users would never get notices. Two token kinds per device, two providers | Requires `@react-native-firebase/app` + `messaging` (Expo config plugin → EAS dev/prod builds, no Expo Go) and an APNs auth key uploaded to Firebase; `delivered` is a best-effort client ack instead of a provider receipt |

Resolution: the app obtains the **native FCM registration token** via
`@react-native-firebase/messaging` on both platforms; 06 uses the Firebase Admin Go SDK for topic
subscribe/unsubscribe, topic sends and per-token directed sends. `expo-notifications` stays for
permission primer, Android channels, foreground display and tap handling. Lifecycle: `queued →
sent` (FCM accepted) `→ delivered` (app's background/foreground message handler acks, best
effort) `→ opened` (tap). The Expo push API and `EXPO_ACCESS_TOKEN` are **not used**.

### Rejected: app polling instead of push

Polling was rejected: on the target 3G + low-end-device profile it means constant wake-ups,
battery drain, missed-critical-notice risk and server load at 20k users — against push's instant,
battery-friendly delivery, which is the product's trust promise to guardians. Provider outages
degrade push to in-app only (§8), which is the acceptable failure mode; recorded in
`07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | FCM topic sends cannot be tracked per recipient | Delivery stats for notices are send-level only | Accepted default (`NTF-BR-005`, OQ-3); admin dashboards present counts honestly |
| 2 | Locale rendering: payload carries key + pre-rendered bn/en pairs (server, from `users.locale`); device picks by stored app locale, falls back to `en` | OS-language ≠ app-language edge shows the other language's tray text | Client resolves key from on-device catalog first; pairs are a fallback, never raw content |
| 3 | FCM outage windows queue directed sends | DM push arrives late | In-app + WS delivery (05) is unaffected; queue drains with backoff |
| 4 | 90-day stale pruning could drop an inactive-but-valid device | User stops receiving pushes until next app open | `last_seen_at` refreshes on every foreground; threshold is config (OQ-4) |
| 5 | Topic fan-out reaches suspended/migrated users for seconds before unsubscribe | Stale push to a migrated student | Unsubscribe runs in the migration flow (04) + nightly reconcile job |
| 6 | FCM quota changes at 20k users | Batch pacing insufficient | Batch size + pacing are config (§5); load-test before Phase-2 scale-up |
