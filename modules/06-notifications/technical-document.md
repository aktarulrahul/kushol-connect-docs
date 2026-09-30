# Notifications — Technical Document

**Module:** `06-notifications` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Overview

### 1.1 Purpose

Kushol Connect's push backbone: FCM topic fan-out mirroring City → School → Section for mass
messages (notices, city events, campaigns), per-device directed push via FCM token sends for
personal messages (DMs, tuition matches, payment/test results), deep links that land every tap on
the right screen, and a delivery log. The delivery half of the Phase-1 exit criterion ("a verified
student … receives a notice by push"), serving `brd.md` §6 Scalability — FCM topic fan-out at scale
is this module's reason to exist.

### 1.2 Scope

**In:** `device_tokens` registration (idempotent upsert), refresh (`last_seen_at`), logout cleanup,
pruning · mass fan-out via FCM topics (`city-{id}` / `school-{id}` / `section-{id}`, bindings owned
by 04) · directed per-device push via FCM token sends with tracking (queued → sent → delivered →
opened) · deep-link payload contract (message KEY + ids only, never bodies; resolved on-device, bn
default / en) · `notification_preferences` — one muted flag per class, 1:1 with the three Android
channels · delivery log + open reporting (own list + tenant-scoped admin aggregates) · test-push
endpoint for pilots.
**Out:** notice/campaign authoring UI (05/07/13 — they call `notify.*`, never FCM directly) · web
push and email/SMS channels · in-app inbox screen (future module) · quiet hours (OQ-1) and ad
targeting (13 consumes 04 segments).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations + 02 design-system | `jobs.Enqueue` + worker registration (`fanout.send`, `tokens.prune`, `topics.backfill`), `audit.Record`, RFC-7807 envelope, health · bn/en catalogs (`notifications.*`, `validation.*`), tokens, RN primitives |
| consumes | 03 identity-access | Auth chain, `users` (locale bn/en, PENDING/VERIFIED/SUSPENDED), `RequireVerified` |
| consumes | 04 organization-hierarchy | `fcm_topic_bindings` reads + `hierarchy.ResolveUserNodes(userId)`; verification is the subscription trigger (04 never calls 06) |
| consumes / consumed by | 05 communication-engine | `chat.PostNotice(...)` triggers the notice push (in-app + WS stays the fallback); they call `notify.BroadcastTopic` (`school-{id}` / `section-{id}`) |
| consumed by | 10 / 12 / 13 / 03 / 07 / app | `notify.SendToUser` (matches, payment results, campaigns, SLA reminders) · 07: test-push control + delivery aggregates via admin endpoints · app (expo-notifications): devices, prefs, deliveries, opened REST |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| API runtime / contracts | Go 1.24+ · chi REST · OpenAPI 3.1 → oapi-codegen | Resolved stack (`docs/tech-stack.md`); payload schema v1 frozen for Phase 1 | 7 endpoints per `03` §2; unknown types → home-tab fallback |
| Push (mass) | Firebase Admin Go SDK → FCM topic subscriptions | One topic message fans out to any audience size (`brd.md` §6) | `FCM_SERVER_KEY` held by 06 only; topics from 04 bindings |
| Push (directed) + app | Firebase Admin Go SDK per-token send · `@react-native-firebase/messaging` (native FCM token) + expo-notifications (display/channels/taps) | One provider + one token for topics and directed on iOS and Android; `delivered` = client ack (revised 2026-09-30, `02` §10) | `FCM_SERVER_KEY` only; APNs auth key uploaded to Firebase; EAS builds (no Expo Go); 3 Android channels |
| Data access | sqlc + pgx/v5 · PostgreSQL 16 on Neon | testcontainers-go for ITs; tenant scope via user | `pruned_at` soft state; rows never deleted (audit) |
| Cache / queueing | Redis (go-redis) · In-DB `jobs` table + 01 worker | Fan-out hot path: `notify:devices:{userId}` TTL 5 min, `notify:bindings:{topicName}` TTL 10 min · jobs `fanout.send`, `tokens.prune` (nightly), `topics.backfill` | Deliveries/preferences never cached; jobs status-scoped, idempotent |
| Web | None — no web surfaces in this module | 07 dashboards consume the admin endpoints; `NTF-FE-*` items do not exist | `04-frontend-tasks.md` is N/A |

---

## 3. Architecture

### 3.1 Component diagram

```text
05 chat.PostNotice │ 10 match │ 12 payment │ 13 campaign │ 03 reminder      Expo app
        │ trigger (module export — never FCM directly)     ▲ devices / prefs / opened (REST)
        ▼                                                  │
[chi handlers] ──► [notify service (06)] ──► [payload builder: class + key + ids
                          │                 + deep link + bn/en strings, schema v1]
        MASS: notify.BroadcastTopic ── topic validated vs 04 bindings (INV-4)
              ──► FCM Admin SDK topic message (fire-and-forget)
        DIRECTED: notify.SendToUser ── prefs gate → active devices (pruned_at IS NULL)
              ──► FCM per-token send ── client ack ▶ delivered
                          │
  01 jobs: fanout.send (batching) · tokens.prune (nightly) · topics.backfill
  notification_deliveries (Postgres; tenant-scoped reads)   Redis: notify:devices / notify:bindings
```

Flow: mutation → notify service → FCM topic (mass) / Expo per-device (directed) → delivery log →
app renders on the class channel → tap → deep link → `POST …/opened` (directed only).

### 3.2 Boundary

**Owns (tables / services):** `device_tokens`, `notification_deliveries`, `notification_preferences`
— and the provider client (FCM Admin SDK), which **no other module may touch**
(04 holds no FCM credentials; 05 only calls `notify.BroadcastTopic`). **Reads (via exported service
functions only):** 03 auth chain + `users.locale`/status · 04 `fcm_topic_bindings` +
`hierarchy.ResolveUserNodes` · 05 trigger context (notice ids for deep links) · 01 `jobs.Enqueue`,
`audit.Record`, error envelope. Cache tags: `06-integration-tasks.md` §4.

### 3.3 Request / data flows

```text
1. Mass (topic): 05 publishes notice → notify.BroadcastTopic("school-{schoolId}", payload)
   → binding check → FCM topic message → one delivery row sent|failed (no per-recipient tracking)
2. Directed: notify.SendToUser(userId, payload) → prefs gate (muted class skipped server-side)
   → resolve active devices → delivery row per device queued → chunked Expo send → sent
   → client ack → delivered → user tap → RecordOpened (write-once opened_at)
3. Device lifecycle: login → primer → POST /notifications/devices (upsert on unique token)
   → VERIFIED: subscribe exactly city-/school-/section-{id} from bindings; PENDING: stored,
   subscribed later by topics.backfill · logout: DELETE → pruned + best-effort unsubscribe
4. Pruning: provider rejects token → prune + delivery failed mid-batch (rest still sent);
   last_seen_at > 90 d → nightly tokens.prune
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `notification_deliveries.status` | queued → sent → delivered → opened | provider 2xx → sent (`sent_at` set); client ack → delivered (directed rows only); user tap → opened (write-once `opened_at`, INV-6); any → failed (terminal; retry budget exhausted; token pruned if invalid). Topic sends only ever `sent`/`failed` (`NTF-BR-005`) |
| `device_tokens` (prune) | active → pruned | provider rejection or `last_seen_at` > 90 d (nightly job); `pruned_at` set; never re-targeted (`NTF-BR-006`) |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `device_tokens` | One row per physical device (Expo/FCM token) | Via user — resolved through the 04 enrollment; no school column by design | unique `(token)` · `(user_id, pruned_at)` · partial `(last_seen_at) WHERE pruned_at IS NULL` | Upsert on token (INV-1); `pruned_at` soft state; rows never deleted (audit) |
| `notification_deliveries` | One row per push dispatch | Recipient user (03) → enrollment (04); admin reads claim-forced join; cross-tenant `TENANT_MISMATCH` | `(user_id, created_at DESC)` · `(status, created_at)` · `(topic_name, created_at)` | `payload_key` + `payload_data` jsonb (ids only, never bodies); `CHECK status='opened' ⇒ topic_name IS NULL`; forward-only status |
| `notification_preferences` | One `muted` flag per class | User-row only — never exposed cross-user; no tenant read path | unique `(user_id, class)` | Classes `notices`/`chat`/`campaigns` ↔ 3 Android channels 1:1; lazy-created unmuted |
| `fcm_topic_bindings` | Topic-name source (`city-{id}`/`school-{id}`/`section-{id}`) | **Not owned** — module 04's table, read here | (04's unique indexes) | This module never invents or accepts client-supplied topic names (`NTF-BR-009`) |

No seed — runtime data only (demo tokens would fabricate devices, `prompt.txt` §12).

---

## 5. Contracts

### 5.1 REST endpoints

All under `/api/v1`; RFC-7807 errors; shapes in `03-backend-tasks.md` §2.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST `/notifications/devices` · DELETE `/notifications/devices/{deviceId}` | Authenticated (pending users allowed) · caller owns row | Register/upsert push token; subscribe bound topics when VERIFIED · logout cleanup: pruned + best-effort FCM unsubscribe | `VALIDATION_FAILED`, `RATE_LIMITED`, `NOT_FOUND`/`TENANT_MISMATCH` | NTF-US-001/002/008 |
| 2 | GET · PATCH `/notifications/preferences` | Authenticated user | Always exactly three rows (lazy-created unmuted); single-class mute toggle | `VALIDATION_FAILED` (`class_invalid`) | NTF-US-006 |
| 3 | GET `/notifications/deliveries` (own) · GET `/school│admin/notifications/deliveries` | Authenticated user (`user_id = caller`) · SCHOOL_ADMIN (claim-forced) / SUPER_ADMIN (optional `schoolId` filter) | Own history, paginated ≤ 100 · tenant/platform aggregates + status counts — never bodies | `VALIDATION_FAILED`, `TENANT_MISMATCH`/404 (`NTF-BR-008`) | NTF-US-007 |
| 4 | POST `/notifications/deliveries/{deliveryId}/opened` | Owner of row | Flip delivered → opened (write-once; directed only) | `CONFLICT` topic rows/terminal failed, `NOT_FOUND` | NTF-US-007 |
| 5 | POST `/admin/notifications/test` | SCHOOL_ADMIN / SUPER_ADMIN | Test push `target=self\|section` (own tenant only), visibly "টেস্ট / Test" | `TENANT_MISMATCH`, `RATE_LIMITED` (10/h) | NTF-US-009 |

### 5.2 Realtime / jobs

No WebSocket in this module (the WS `notice.new` path belongs to 05). Jobs run on the 01 runner.

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `fanout.send` (`NTF-BE-020`) | `SendToUser` (directed batches) + `BroadcastTopic` (topic dispatches) via 01 `jobs.Enqueue` | Claim only `queued` rows; FCM 500/batch pacing; per-chunk results update rows individually; receipt polling → delivered | delivery log; provider clients | ×3 backoff → `failed` + dead-letter report; invalid tokens pruned mid-batch; queue drains on provider recovery |
| `tokens.prune` (`NTF-BE-021`) | Nightly schedule | `pruned_at IS NULL ∧ last_seen_at < cutoff (90 d)` → pruned | provider quota hygiene; honest stats | Idempotent; missed runs self-heal; alert after 3 consecutive failures |
| `topics.backfill` (`NTF-BE-022`) | Device registered while PENDING, or subscribe failure during verification | Idempotent subscribe to the exact bound topic set | `NTF-US-002` post-verification path | ×5 backoff → dead-letter + admin report; user experience unaffected (in-app always works) |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — frozen for Phase 1; package `notify`. Payload schema v1:
`{v:1, class, type, key:"notifications.*", data:{ids + string args only}, deepLink, deliveryId? (directed only)}`.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `notify.BroadcastTopic(topic, payload)` | 05 (notice publish) · 13 (campaign broadcast) · 07 (admin composer, server-side) | One `DeliveryDTO`, `sent`/`failed` — fire-and-forget (`NTF-BR-005`) | `NOT_FOUND` (topic absent from 04 bindings, `NTF-BR-009`), `VALIDATION_FAILED` |
| `notify.SendToUser(userID, payload)` | 10 (match) · 12 (payment result) · 13 (targeted push) · 03 (SLA reminders) | `[]DeliveryDTO` per active device; prefs gate server-side; SUSPENDED skipped; zero devices → empty slice, not an error | `NOT_FOUND` (no user), `VALIDATION_FAILED` |
| `notify.RecordOpened(userID, deliveryID)` | REST `POST /notifications/deliveries/{id}/opened` (app) | `error` only; idempotent write-once `opened_at` (INV-6) | `NOT_FOUND`/`TENANT_MISMATCH` (not caller's row), `CONFLICT` (topic rows, terminal failed) |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

N/A — no web screens exist in this module; the mobile app is the only notification consumer. The
notice composer lives in 05/07 (server-side `notify.BroadcastTopic`); the pilot test-push control
and delivery aggregates belong to module 07, consuming `POST /admin/notifications/test` and the
admin deliveries endpoints via the generated `openapi-fetch` client (shapes frozen in `03` §2).

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(modals)/notifications-primer` | **Permission primer** — value-first bn/en explainer (📢 notices · 💬 chat · 🎯 campaigns) → OS permission ask in context; denied → OS-settings path; shown once per install | none (post-login flow) | Registration queued, replayed when online — user never blocked |
| `/settings/notifications` | **Settings** — 3 class toggles (≥ 44 pt switches, optimistic PATCH) aligned 1:1 with Android channels + registered-device row + paginated history | none (settings entry) | Toggle optimistic, "Will save when online" + queued PATCH; logout cleanup retried silently |

Deep-link map — `payload.type → route` (schema v1; ids only, never bodies; additive only,
`NTF-INT-007`): `notice` → `/notices/{noticeId}` · `dm` → `/messages/{peerId}` ·
`payment_result` → `/receipts/{paymentId}` · `tuition_match` → `/messages/{peerId}` ·
`test_result` → `/ai-hub/test/{testId}` · `campaign` → notices campaigns section · `test` → chat
home + toast · *(unknown)* → home tab + fallback toast, never a crash. Foreground pushes render an
in-app banner (no tray duplicate, auto-dismiss 5 s); background renders via the class's Android
channel (`notices`/`chat` HIGH, `campaigns` DEFAULT). Every directed tap fires `POST …/opened`.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM (Firebase Admin Go SDK, HTTP v1) | Mass topic fan-out (`city-/school-/section-{id}`); per-token subscribe/unsubscribe | HTTPS | Service account `FCM_SERVER_KEY` (envconfig; held by 06 only) | 10 s; ×3 exponential backoff via `fanout.send` → dead-letter | Topic dispatches queue in `jobs`; notices remain in-app + WS (05); never fatal |
| (R2, DeepSeek, payment gateways, SMS) | None — this module touches none of them (`06-integration-tasks.md` §5) | n/a | n/a | n/a | — |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `SMTP_HOST` / `SMTP_PORT` | Yes | `mail.kusholconnect.com` / `587` | email channel (HestiaCP Exim) |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | Yes | `noreply@kusholconnect.com` / mailbox password (host `.env` only) | SMTP auth |
| `EMAIL_FROM` / `EMAIL_REPLY_TO` | Yes | `Kushol Connect <noreply@kusholconnect.com>` / `hello@kusholconnect.com` | message headers |
| `FCM_SERVER_KEY` | Yes | Firebase service account (envconfig-parsed; held by 06 only — never 04, never 05) | FCM topic send + subscribe/unsubscribe |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Stale-token prune age (default 90 days) · delivery-row retention (default 180 days) | Three classes ↔ three Android channels, 1:1 (`NTF-BR-004`) |
| `fanout.send` batch size (500/batch FCM, 100/request Expo) · provider timeout/retry budget (10 s, ×3) | Topic naming `city-{id}/school-{id}/section-{id}` (04's contract) |
| Test-push rate limit (default 10/hour/admin) · quiet hours (future — OQ-1) | Payload schema v1: key + ids + deep link + bn/en strings; bodies forbidden (`NTF-BR-003`) |
| — | Fire-and-forget semantics for topic sends; deep-link route map additive only; prefs gate server-side (directed) / on-device (topic classes) |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope (module 03 middleware) on every `/notifications/*` entry point |
| Role matrix | Any authenticated user (incl. pending): own devices + prefs + deliveries · SCHOOL_ADMIN: own-school delivery aggregates, test push (`self`/own section) · SUPER_ADMIN: platform aggregates + test push; no per-school content access |
| Tenant scope | `user_id = caller` on device/preference/own-delivery queries; admin reads tenant-forced by claim via the 04 enrollments join — no method accepts a caller-supplied `user_id`; cross-tenant reads → `TENANT_MISMATCH`/404 (`NTF-BR-008`) |
| Rate limits | Default class on device/preference/delivery routes (registration bucket generous — idempotent); stricter bucket on test pushes (10/hour/admin) |
| Audit events | `audit.Record` on every test send, campaign-class broadcasts, and admin aggregate exports |
| Privacy / minors | **Payloads carry a message KEY, ids and deep link only — never DM/chat bodies** (`NTF-BR-003`, guarded by `NTF-UT-001`); content fetched in-app after auth; provider error logs redacted of tokens; minors/guardians reachable only via their school scope — this module adds no cross-tenant path |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `UNAUTHENTICATED` / `FORBIDDEN` | No credentials / wrong role | Any endpoint without auth; non-admin on test push / admin deliveries | Route to login (cold-start taps park the deep link until login); hide admin surfaces |
| `VALIDATION_FAILED` | Bad input | Token format (`ExponentPushToken[…]`/FCM), platform `ios\|android`, class/target enums, paging ≤ 100 (`validation.notifications.*`) | Inline field errors from the zod schemas generated from the contract |
| `TENANT_MISMATCH` (404 body) | Cross-tenant access | Admin delivery reads across schools; test push at another school's section; foreign device/delivery ids | Never reveal existence |
| `NOT_FOUND` / `CONFLICT` | Missing row / illegal transition | Unknown device/delivery/user · `opened` on topic rows or terminal `failed` rows | 404 treated as success on idempotent cleanup; app silently ignores (fire-and-forget report) |
| `RATE_LIMITED` / `INTERNAL` | Throttled / unexpected | Test pushes past 10/hour/admin · unhandled failures | Pilot tooling backs off; generic error |
| Provider token errors (server-side) | Invalid/unregistered token | Not surfaced to clients — token pruned, delivery `failed`, batch continues (`NTF-IT-003`) | Re-register on next app open resumes delivery |

All errors surface as RFC-7807 `application/problem+json`. User-visible strings resolve via
`packages/shared` catalogs — every key ships in **bn + en** (Bengali default); push payloads render
via the on-device `notifications.*` catalog with the bn/en `strings` pair as fallback, so raw key
text is never shown.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | `slog` JSON, redacted — never contains tokens; the delivery `error` column holds redacted provider error summaries |
| Metrics / counters | FCM/Expo error-rate alarms (10 s timeouts); `queued` delivery backlog; prune/backfill run outcomes; delivery status counts (`sent`/`delivered`/`opened`/`failed`) for 07 dashboards |
| Health contribution | Shared `/readyz` (01); jobs-worker lag alarm — deliveries piling up `queued` is the signal to watch |
| Jobs & retries | `fanout.send` ×3 backoff → `failed` + dead-letter report · `tokens.prune` nightly (alert after 3 consecutive failures) · `topics.backfill` ×5 → dead-letter + admin report; all status-scoped, drain on recovery |
| Runbook pointers | Push is an enhancement layer, never the source of truth — FCM/Expo outages degrade to in-app + WS (05) · queue flush on provider restore · Neon cold start → warm-up per 01/15 runbooks · load-test batch pacing before Phase-2 scale-up |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Payload schema v1 (type→key/data/deep_link map, **asserts no message-body fields**); prefs gating; `RecordOpened` idempotency + forward-only status; `BroadcastTopic` rejects unbound topic names; request validation keys | `NTF-UT-001`–`005` | `go test ./...` |
| Integration | Fan-out resolves `school-{id}`/`section-{id}` from bindings (fake FCM); mute respected end-to-end; invalid-token pruning mid-batch (never re-targeted); **cross-tenant delivery read denied**; auth chain on every endpoint; VERIFIED subscribe + PENDING back-fill; test push tenant-gated + audited; directed lifecycle queued→sent→delivered→opened + prune idempotency | `NTF-IT-001`–`008` (testcontainers Postgres + provider fakes) | green in CI |
| E2E (Maestro, app) | Admin test push → tray renders (bn) → tap lands on the mapped screen → `opened` recorded · mute `campaigns` → no banner/tray for that class | `NTF-E2E-001`–`002` | green in CI |
| CI | api: `go test`/`vet`/`golangci-lint` · app: `pnpm lint/typecheck/test` + Maestro (`NTF-AP-011`) | — | per-app quality gate |

Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; cross-tenant
attempts return `TENANT_MISMATCH`/404; **no payload ever carries message bodies** (`NTF-UT-001`).

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot 3 schools × ~2,000 users ≈ 6k devices; a school notice is **one** FCM topic message regardless of audience size (FCM performs the per-device fan-out); directed volume modest (tens/min) |
| Hot paths + indexes | `device_tokens (user_id, pruned_at)` → directed fan-out · unique `(token)` → registration upsert · `notification_deliveries (user_id, created_at DESC)` → history · `(status, created_at)` → worker scans · admin aggregates join 04 enrollments (indexed there) |
| Latency targets | Topic dispatch accepted p95 ≤ 500 ms server-side; end-to-end push render p95 ≤ 5 s at pilot scale; directed send→`sent` p95 ≤ 2 s |
| Batching / payload impact | FCM batch limit 500 tokens/message (topic subscribe + multicast) — `fanout.send` chunks and paces inside provider quotas; retries carry only the un-sent remainder; no payload prefetch on receive (ids only — that is the design); history paginated 20/page; no new app dependency |
| Caching | Redis `notify:devices:{userId}` TTL 5 min (invalidate on register/prune) · `notify:bindings:{topicName}` TTL 10 min (authoritative source is 04's table) · deliveries/preferences lists never cached server-side |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the readiness-check table; unconfirmed items keep `TODO: Confirm`.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Quiet hours for push delivery (OQ-1) | Night-time disturbance / opt-outs | Rahul | Open — `TODO: Confirm` | None at launch; Android channels let users silence classes per-OS |
| 2 | Android channel strategy final copy (OQ-2) | Tray presentation | Rahul | Open | One channel per class — `notices`/`chat`/`campaigns` (3 channels, bn+en names) |
| 3 | Fan-out path + tracking semantics (OQ-3); FCM topic sends not trackable per recipient (02 §11.1) | Delivery-stat honesty | Rahul | Open / accepted default | Mass via FCM topics fire-and-forget; directed via Expo tracked queued→sent→delivered→opened; dashboards present counts honestly |
| 4 | Stale-token prune age (OQ-4) + delivery-row retention (OQ-5) (02 §11.4) | Devices silently dropped; table growth | Rahul | Open | 90 days since `last_seen_at`; 180 days then aggregate-and-delete — both config |
| 5 | Locale rendering: OS-language ≠ app-language edge (02 §11.2); Expo outage queues directed sends (02 §11.3) | Tray text in the other language; DM push arrives late | Rahul | Assumption | On-device catalog first, bn/en pairs as fallback; in-app + WS (05) unaffected, queue drains with backoff |
| 6 | Topic fan-out reaches suspended/migrated users briefly (02 §11.5) | Stale push to a migrated student | Rahul | Assumption | Unsubscribe in 04's migration flow + nightly reconcile |
| 7 | FCM/Expo quota changes at 20k users (02 §11.6) | Batch pacing insufficient | Rahul | Assumption | Batch size + pacing are config; load-test before Phase-2 scale-up |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-01 — Phase-1 exit, delivery half ("receives a notice by push") | §5.1 | `NTF-US-002`, `NTF-US-003` | `NTF-BE-001`, `007`–`008`, `011`–`012`, `020`, `NTF-INT-001`, `004`–`005` | `NTF-UT-004`, `NTF-IT-001`, `006`, `NTF-E2E-001` |
| `brd.md` §6 — scalability (topic fan-out) + privacy (no bodies) | — | `NTF-US-003`, `005`, `008` | `NTF-BE-008`, `011`, `013`–`015`, `021`, `NTF-INT-006` | `NTF-UT-001`, `004`, `NTF-IT-003`, `008` |
| PRD §6 / §5.4 — push row + deep links | §5.4 | `NTF-US-001`, `004`, `005` | `NTF-BE-001`–`002`, `006`, `009`, `013`, `016`–`017`, `NTF-INT-003`, `007` | `NTF-UT-001`, `005`, `NTF-IT-005`, `NTF-E2E-001` |
| README module 06 defaults — channels, prefs, delivery tracking, pilot tooling | — | `NTF-US-006`–`009` | `NTF-BE-003`–`005`, `010`, `016`–`019`, `022` | `NTF-UT-002`–`003`, `NTF-IT-002`, `004`, `007`, `NTF-E2E-002` |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Email channel added: `notify.SendEmail` (OTP / account / notification kinds) over SMTP to HestiaCP as `noreply@kusholconnect.com`; OTP emails never persisted; `notification_deliveries.channel` + provider `fcm_topic`/`fcm_token`/`smtp` (stale `expo` value removed); `notification_preferences.email_enabled` + `List-Unsubscribe`; class `account` | Claude |
| 2026-09-30 | Push provider revised: FCM for topics **and** directed sends with one native FCM token per device (`@react-native-firebase/messaging`); Expo push API + `EXPO_ACCESS_TOKEN` dropped — Expo/APNs tokens cannot subscribe to FCM topics on iOS (`02` §10) | Claude |
