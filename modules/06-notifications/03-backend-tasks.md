# Notifications — Backend Tasks & Database Design

**Module:** `06-notifications`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below is designed until the schema is settled. Every table states its
tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `device_tokens` (model `DeviceToken`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → module 03 `users`; **tenant scope via user** — resolved through the user's enrollment (04), no school column by design |
| `token` | `text` | no | — | **Native FCM registration token** (from `@react-native-firebase/messaging`, both platforms) — the same token is used for topic subscription and directed sends; Expo push tokens and raw APNs tokens are rejected (`VALIDATION_FAILED`); globally unique (`NTF-BR-002`) |
| `platform` | `text` | no | — | `ios` / `android` |
| `app_version` | `text` | no | `''` | e.g. `1.0.3` — targeting + debugging |
| `last_seen_at` | `timestamptz` | no | `now()` | Refreshed on (re-)registration and app-foreground heartbeats |
| `pruned_at` | `timestamptz` | yes | — | Soft pruned state — provider-rejected or stale (`NTF-BR-006`); rows never deleted (audit) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** unique `(token)`; FK `user_id`; `CHECK (platform IN ('ios','android'))`.
**Tenant scope:** via user — every repository method takes the caller identity from claims; no
method accepts a caller-supplied `user_id` (jobs operate by row, never across users).
**Indexes:** unique `(token)` → idempotent registration + send-result pruning;
`(user_id, pruned_at)` → directed fan-out device lookup; `(last_seen_at) WHERE pruned_at IS NULL`
→ stale-token prune scan.

#### `notification_deliveries` (model `NotificationDelivery`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → 03 `users`; recipient for directed sends, initiating actor for topic sends |
| `topic_name` | `text` | yes | — | Set for topic fan-outs (`city-{id}` / `school-{id}` / `section-{id}` from 04 bindings); NULL for directed |
| `class` | `text` | no | — | `notices` / `chat` / `campaigns` / `account` (invites, resets — email only, not mutable) |
| `payload_key` | `text` | no | — | i18n key from the `notifications.*` catalog (e.g. `notifications.dm_new`) |
| `payload_data` | `jsonb` | no | `'{}'` | Ids + string args only — never message bodies (`NTF-BR-003`) |
| `deep_link` | `text` | no | — | App route per the deep-link map (`05-app-tasks.md` §2.4) |
| `channel` | `text` | no | `'push'` | `push` / `email` |
| `provider` | `text` | no | — | `fcm_topic` / `fcm_token` (push) · `smtp` (email via HestiaCP, `noreply@kusholconnect.com`) |
| `status` | `text` | no | `'queued'` | `queued` / `sent` / `delivered` / `opened` / `failed` (`NTF-BR-005`, forward-only) |
| `error` | `text` | yes | — | Provider error summary — redacted, never contains tokens |
| `sent_at` | `timestamptz` | yes | — | Provider accepted the dispatch |
| `opened_at` | `timestamptz` | yes | — | User tap (directed rows only; write-once) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** FK `user_id`; `CHECK` on `status`, `class`, `channel`, `provider`; `CHECK (channel='email' ⇒ provider='smtp' AND topic_name IS NULL)`; `CHECK (status =
'opened' ⇒ topic_name IS NULL)` — opened tracking is directed-only.
**Tenant scope:** recipient user (03) → enrollment (04); own reads filter `user_id = caller`,
admin reads tenant-forced by claim via the enrollments join — cross-tenant is `TENANT_MISMATCH`.
**Indexes:** `(user_id, created_at DESC)` → own history; `(status, created_at)` → worker
queued/retry scans; `(topic_name, created_at)` → per-topic dispatch audit.

#### `notification_preferences` (model `NotificationPreference`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → 03 `users`; **tenant scope via user** |
| `class` | `text` | no | — | `notices` / `chat` / `campaigns` — matches the Android channel strategy (README module 06 default) |
| `muted` | `boolean` | no | `false` | Server-side gate for directed sends; on-device display gate for topic classes (`NTF-BR-004`) |
| `email_enabled` | `boolean` | no | `false` | Opt-in email copy of this class (staff default on for `notices` via 07 settings); every non-`account` email carries `List-Unsubscribe` that flips this flag |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** unique `(user_id, class)`; FK `user_id`; `CHECK (class IN ('notices','chat','campaigns'))`.
**Tenant scope:** user-row only — preferences are never exposed cross-user; no tenant read path.
**Indexes:** unique `(user_id, class)` → GET (lazy-create) + PATCH upsert; no others.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261006090001_create_device_tokens` | ✅ |
| 2 | `20261006090002_create_notification_deliveries` | ✅ |
| 3 | `20261006090003_create_notification_preferences` | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| None — runtime data only: preferences default unmuted (lazy-created), devices/deliveries are per-user runtime rows; seeding demo tokens would create fictional devices | N/A | `NTF-BR-004`; `prompt.txt` §12 (nothing fabricated) |

---

## 2. Server Contracts

All routes live under `/api/v1`; errors use the shared RFC-7807 envelope.

### `POST /api/v1/notifications/devices` (register token)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope (caller identity; pending users allowed) |
| **Input** | `{ token, platform, appVersion? }`; contract-generated validator (`validation.notifications.*`) |
| **Result** | `{ "data": { id, platform, appVersion, lastSeenAt, topics: ["school-{id}", …] } }` — 201 first time, 200 on upsert; topic list reflects what was subscribed (empty while PENDING) |
| **Errors** | `UNAUTHENTICATED` · `VALIDATION_FAILED` · `RATE_LIMITED` · `INTERNAL` |
| **Rate limit** | default class (registration is idempotent, bucket generous) |
| **Audit** | none (non-destructive) |
| **Stories** | `NTF-US-001`, `NTF-US-002` |

### `DELETE /api/v1/notifications/devices/{deviceId}` (logout cleanup)

| | |
| --- | --- |
| **Auth** | authenticate → tenant-scope via user |
| **Input** | path uuid |
| **Result** | `{ "data": { "deleted": true } }` — token pruned + best-effort FCM unsubscribe |
| **Errors** | `UNAUTHENTICATED` · `NOT_FOUND`/`TENANT_MISMATCH` (not the caller's device) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none |
| **Stories** | `NTF-US-001`, `NTF-US-008` |

### `GET /api/v1/notifications/preferences` · `PATCH /api/v1/notifications/preferences`

| | |
| --- | --- |
| **Auth** | authenticate → tenant-scope via user |
| **Input** | GET none (three rows lazy-created unmuted) · PATCH `{ class, muted }` (single-class toggle, matches the settings screen) |
| **Result** | `{ "data": [ { class, muted }, … ] }` — always exactly three rows |
| **Errors** | `UNAUTHENTICATED` · `VALIDATION_FAILED` (`validation.notifications.class_invalid`) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none |
| **Stories** | `NTF-US-006` |

### `GET /api/v1/notifications/deliveries` (own, paginated) · admin variants

| | |
| --- | --- |
| **Auth** | own: authenticate → `user_id = caller` · school: authenticate → `SCHOOL_ADMIN` → tenant-scope by claim · platform: `SUPER_ADMIN` with optional `schoolId` filter (`GET /api/v1/school/notifications/deliveries`, `GET /api/v1/admin/notifications/deliveries`) |
| **Input** | query `page`, `pageSize` (≤ 100), optional `class`, `status` |
| **Result** | `{ "data": [ { id, class, payloadKey, topicName?, deepLink, status, sentAt?, openedAt? } ], "page": {…} }`; admin variants add status counts + `payload_key`-level aggregates — never bodies |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH`/404 (`NTF-BR-008`) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none (read-only; exports audited when consumed by dashboards) |
| **Stories** | `NTF-US-007` (admin variant) |

### `POST /api/v1/notifications/deliveries/{deliveryId}/opened`

| | |
| --- | --- |
| **Auth** | authenticate → tenant-scope via user |
| **Input** | path uuid; no body |
| **Result** | 204 — row flips `delivered → opened` (write-once `opened_at`); directed rows only |
| **Errors** | `UNAUTHENTICATED` · `NOT_FOUND`/`TENANT_MISMATCH` (not the caller's delivery) · `CONFLICT` (topic rows / terminal `failed`) · `INTERNAL` |
| **Rate limit** | default class |
| **Audit** | none |
| **Stories** | `NTF-US-007` |

### `POST /api/v1/admin/notifications/test` (pilot tooling)

| | |
| --- | --- |
| **Auth** | authenticate → role claim `SCHOOL_ADMIN` (own tenant) or `SUPER_ADMIN` |
| **Input** | `{ class, target: "self" \| "section", sectionId? }` — section must resolve to the caller's school (`NTF-BR-007`) |
| **Result** | `{ "data": { deliveryIds: […], devices: n } }` — directed send, payload `type=test`, visibly marked "টেস্ট / Test" |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` (other school's section) · `RATE_LIMITED` · `INTERNAL` |
| **Rate limit** | 10/hour per admin (config) |
| **Audit** | yes — `audit.Record` on every test send |
| **Stories** | `NTF-US-009` |

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web code. Module 07 (`command-center-web`) consumes the admin
endpoints above through the generated `openapi-fetch` client, and the Super/School Admin notice
surfaces live in 05/07 calling the `notify.*` exports server-side — never the database, never the
FCM SDK directly.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `NTF-BE-001` | `RegisterDevice` | Auth caller only; upsert on unique `token` (INV-1); resolve 04 `ResolveUserNodes` → subscribe bound topics when VERIFIED; `last_seen_at` refresh | `notifications:devices:{userId}` | no |
| `NTF-BE-002` | `DeleteDevice` / `PruneDevice` | Caller owns row; set `pruned_at`; best-effort FCM unsubscribe; never re-targeted (`NTF-BR-006`) | `notifications:devices:{userId}` | no |
| `NTF-BE-003` | `GetPreferences` | Lazy-create the three unmuted rows (INV-5) | `notifications:prefs:{userId}` | no |
| `NTF-BE-004` | `UpdatePreference` | Validate class; upsert `muted` (`NTF-BR-004`) | `notifications:prefs:{userId}` | no |
| `NTF-BE-005` | `ListOwnDeliveries` / `ListSchoolDeliveries` / `ListPlatformDeliveries` | Paging ≤ 100; own = caller filter; admin = claim-forced enrollment join + status counts (`NTF-BR-008`) | — | no |
| `NTF-BE-006` | `RecordOpened` | Caller owns delivery; directed rows only; write-once `opened_at` (INV-6) | — | no |
| `NTF-BE-007` | `notify.BroadcastTopic(topic, payload)` | Topic must exist in `fcm_topic_bindings` (`NTF-BR-009`, INV-4); FCM topic message fire-and-forget; one delivery row `sent`/`failed`; chunked multi-topic for city fan-outs | — | campaigns class only |
| `NTF-BE-008` | `notify.SendToUser(userId, payload)` | Prefs gate — skip muted class (`NTF-BR-004`); resolve active devices; delivery row per device `queued`; chunked Expo send (100/req); invalid token → prune + `failed`; SUSPENDED user → skip (`NTF-BR-001`) | `notifications:devices:{userId}` (prunes) | no |
| `NTF-BE-009` | `notify.RecordOpened(userId, deliveryID)` | Export wrapper over `NTF-BE-006` for the REST endpoint | — | no |
| `NTF-BE-010` | `SendTestPush` | Role + in-tenant target guard; `type=test` payload via `NTF-BE-011`; `audit.Record`; rate-limited (`NTF-BR-007`) | — | yes |
| `NTF-BE-011` | `BuildPushPayload` | Pure function: class + type + `notifications.*` key + ids-args + deep link + bn/en string pairs from the api's catalog (`applications/api/internal/i18n`); schema v1 (`NTF-BR-003`, INV-3) | — | no |
| `NTF-BE-012` | `RefreshTopicSubscriptions(userId)` | Idempotent subscribe/unsubscribe to exactly the bound topics (verification, migration, suspension paths) | `notifications:devices:{userId}` | no |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `NTF-BE-013` | `UpsertDeviceToken` (ON CONFLICT (token) DO UPDATE) / `GetDevice` / `MarkDeviceSeen` | upsert by token; caller-scoped reads | unique `(token)` |
| `NTF-BE-014` | `ListActiveDevicesByUser` | `WHERE user_id=$1 AND pruned_at IS NULL` | `(user_id, pruned_at)` |
| `NTF-BE-015` | `PruneDevice` / `ListStaleTokens` | `UPDATE … SET pruned_at`; `WHERE pruned_at IS NULL AND last_seen_at < $cutoff` | partial `(last_seen_at)` |
| `NTF-BE-016` | `InsertDelivery` / `UpdateDeliveryStatus` / `GetDelivery` | status forward-only guard in UPDATE (`WHERE status` pre-state) | `(status, created_at)` |
| `NTF-BE-017` | `ListDeliveriesByUser` | `WHERE user_id=$1` + filters + paging | `(user_id, created_at DESC)` |
| `NTF-BE-018` | `ListDeliveriesBySchool` / `CountDeliveriesBySchool` | claim-forced join `enrollments` (04) → tenant scope; `GROUP BY status` counts | `(user_id, created_at DESC)` + 04's enrollment indexes |
| `NTF-BE-019` | `UpsertPreference` / `GetPreferencesByUser` | `ON CONFLICT (user_id, class)` upsert | unique `(user_id, class)` |

Every query is tenant-scoped at the repository layer — devices/preferences/deliveries resolve
scope through the authenticated caller (or a claim-forced admin join), never a client-supplied id.

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `NTF-BE-020` | `fanout.send` worker | Enqueued by `SendToUser` (directed batches) and `BroadcastTopic` (topic dispatches) via 01 `jobs.Enqueue` | Yes — status-scoped: only `queued` rows claimed; per-chunk provider results update rows individually | ×3 backoff → `failed` + dead-letter report; invalid tokens pruned mid-batch (`NTF-BR-006`); FCM 500/batch, Expo 100/req pacing |
| `NTF-BE-021` | `tokens.prune` | Nightly schedule (01 runner) | Yes — `pruned_at IS NULL` guard | Missed runs self-heal next night; alert after 3 consecutive failures |
| `NTF-BE-022` | `topics.backfill` | Enqueued when a device registers while PENDING, or when subscribe fails during verification flow (`NTF-US-002`) | Yes — idempotent subscribe to the exact bound set | ×5 backoff → dead-letter + admin report; user experience unaffected (in-app always works) |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `NTF-UT-001` | `BuildPushPayload`: type → key/data/deep_link map + bn/en pairs; asserts no message-body fields; schema v1 shape | Unit | `NTF-BR-003`, INV-3, deep-link stability |
| `NTF-UT-002` | Prefs gating: muted class skips `SendToUser`; topic path documented as on-device gate | Unit | `NTF-BR-004` |
| `NTF-UT-003` | `RecordOpened` idempotent; topic rows rejected `CONFLICT`; forward-only status transitions | Unit | INV-2, INV-6 |
| `NTF-UT-004` | `BroadcastTopic` rejects names absent from bindings (no invented topics) | Unit | `NTF-BR-009`, INV-4 |
| `NTF-UT-005` | Request validation → `validation.notifications.*` keys (token/platform/class/target/paging) | Unit | §6 of `01-user-stories.md` |
| `NTF-IT-001` | Fan-out: notice publish → `BroadcastTopic` resolves `school-{id}`/`section-{id}` from `fcm_topic_bindings`; fake FCM accepts; delivery row `sent` | Integration (testcontainers Postgres + provider fakes) | `NTF-US-003`, I-1/I-3 contract |
| `NTF-IT-002` | Mute respected: muted `chat` user gets no directed send; prefs row drives the gate end-to-end | Integration | `NTF-US-006`, `NTF-BR-004` |
| `NTF-IT-003` | Invalid-token pruning: batch with one dead token → that row `failed` + token pruned, rest `sent`; re-send never targets it | Integration | `NTF-US-008`, `NTF-BR-006` |
| `NTF-IT-004` | Cross-tenant delivery read denied: School Admin A queries school B → `TENANT_MISMATCH`/404; own-user reads leak nothing | Integration | `NTF-US-007` admin AC, `NTF-BR-008` |
| `NTF-IT-005` | Auth chain on every endpoint: unauthenticated → `UNAUTHENTICATED`; wrong role on admin routes → `FORBIDDEN`; bad input → `VALIDATION_FAILED` | Integration | 02 §6 security |
| `NTF-IT-006` | Device register subscribes bound topics when VERIFIED; PENDING device back-fills via `topics.backfill` after verification | Integration | `NTF-US-002`, `NTF-BR-001` |
| `NTF-IT-007` | Test push: `self`/own-section only; other-tenant section → `TENANT_MISMATCH`; `type=test` in payload; audit row written | Integration | `NTF-US-009`, `NTF-BR-007` |
| `NTF-IT-008` | Directed lifecycle: `queued → sent` (FCM accepted) `→ delivered` (client ack) `→ opened`; prune job marks stale tokens; idempotent re-runs | Integration | `NTF-US-007`, `NTF-BR-005`, `NTF-BE-021` |

Always include: unauthenticated call denied for every protected entry point; validation rejects
bad input; cross-tenant read/write returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
no payload ever carries message bodies (`NTF-UT-001` guards the privacy invariant).

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [ ] Migrations 1–3 (§1.2) — prerequisite for every `NTF-BE-*` task below — ____

### Repository · Service · Entry points · Jobs · Tests

- [ ] `NTF-BE-013`–`015` sqlc: device_tokens (upsert, active-device scan, prune) — ____
- [ ] `NTF-BE-016`–`018` sqlc: notification_deliveries (insert, status transitions, lists, admin counts) — ____
- [ ] `NTF-BE-019` sqlc: notification_preferences (lazy-create + upsert) — ____
- [ ] `NTF-BE-011` payload builder (pure, table-driven) + `NTF-BE-006`/`009` RecordOpened — ____
- [ ] `NTF-BE-001`–`002` services: device register/delete/prune + topic subscription resolution — ____
- [ ] `NTF-BE-003`–`005` services: preferences + delivery lists (own/school/platform) — ____
- [ ] `NTF-BE-007`–`008` exports: `notify.BroadcastTopic` / `notify.SendToUser` (provider clients with fakes) — ____
- [ ] `NTF-BE-010`/`012` services: test push + `RefreshTopicSubscriptions` — ____
- [ ] Entry points: 7 endpoints per §2 (handlers over the services) + OpenAPI spec entries + contract regen — ____
- [ ] `NTF-BE-020`–`022` jobs: `fanout.send` + `tokens.prune` + `topics.backfill` registered with 01 runner — ____
- [ ] FCM Admin Go SDK client (topic subscribe/unsubscribe, topic send, per-token send) (timeouts, retries, redacted logging, env-parsed secrets) — ____
- [ ] `NTF-BE-023` email channel: `notify.SendEmail`, `email.send` job (OTP priority lane, never persists OTP content), bn/en templates under `notifications.email.*` in the api's catalog (`applications/api/internal/i18n`), `List-Unsubscribe` → `email_enabled=false`, SMTP client (STARTTLS 587, 10 s timeout) — ____
- [ ] Tests: `NTF-UT-001`–`005` · `NTF-IT-001`–`008` green in CI — ____
