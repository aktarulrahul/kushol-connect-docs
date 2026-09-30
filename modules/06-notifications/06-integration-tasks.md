# Notifications — Integration Tasks

**Module:** `06-notifications` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `05-communication-engine` | they call us | exported Go fn `notify.BroadcastTopic(topic, payload)` on notice publish (`school-{id}` / `section-{id}`) | degraded — notice still in-app + WS; 06 owns retry |
| I-2 | `10-tuition-marketplace` · `12-payments` · `13-b2b-ads-events` · `03-identity-access` (SLA reminders) | they call us | exported fn `notify.SendToUser(userId, payload)` (directed: matches, payment results, campaigns, reminders) | degraded — their core flow unaffected; the result stays visible in-app |
| I-3 | `04-organization-hierarchy` | we call them | read `fcm_topic_bindings` rows + `hierarchy.ResolveUserNodes(userId)` (04 never calls 06) | degraded — topic subscription deferred via `topics.backfill`; bindings are durable |
| I-4 | `01-foundations` | we call them | `jobs.Enqueue`/worker registration (`fanout.send`, `tokens.prune`, `topics.backfill`), `audit.Record`, RFC-7807 envelope | degraded — deliveries stay `queued`; alert |
| I-5 | `03-identity-access` | we call them | auth middleware chain (authenticate → role claims → tenant-scope); `users.locale`, verification/status | fatal to entry points by design (`UNAUTHENTICATED`) |
| I-6 | FCM (external) | outbound | Firebase Admin Go SDK — topic send + per-token subscribe/unsubscribe | degraded, never fatal — jobs queue and retry |
| I-7 | Expo push API (external) | outbound | HTTPS push API (expo-server-sdk push client), access-token auth, chunked + receipts | degraded, never fatal — directed sends queue |
| I-8 | app (expo-notifications) | calls us | REST: `POST/DELETE /notifications/devices`, `GET/PATCH /notifications/preferences`, `GET /notifications/deliveries`, `POST /notifications/deliveries/{id}/opened` | degraded — app queues registration/prefs (05 §8); in-app unaffected |

## 2. Exported Contract

```text
notify.BroadcastTopic(ctx, topic string, payload PushPayload) (DeliveryDTO, error)
notify.SendToUser(ctx, userID uuid, payload PushPayload) ([]DeliveryDTO, error)
notify.RecordOpened(ctx, userID uuid, deliveryID uuid) error
```

```text
PushPayload{ v:1, class: notices|chat|campaigns,
             type: notice|dm|payment_result|tuition_match|test_result|campaign|test,
             key: "notifications.*", data: {ids + string args only},
             deepLink: string (route per 05-app-tasks §2.4 map),
             deliveryId?: uuid (directed rows only) }
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `notify.BroadcastTopic(topic, payload)` | 05 (notice publish) · 13 (campaign broadcast) · 07 (admin composer, server-side) | `DeliveryDTO` — one row, `sent`/`failed` (fire-and-forget, `NTF-BR-005`) | `NOT_FOUND` (topic absent from 04 bindings, `NTF-BR-009`), `VALIDATION_FAILED` (payload) | Package is `notify`; 05's docs reference this seam as `notifications.BroadcastTopic(topic, payload)` — same contract, naming settled here |
| `notify.SendToUser(userID, payload)` | 10 (match) · 12 (payment result) · 13 (targeted push) · 03 (SLA reminders) | `[]DeliveryDTO` per active device | `NOT_FOUND` (no user), `VALIDATION_FAILED` | Prefs gate server-side (`NTF-BR-004`); SUSPENDED user skipped; zero devices → empty slice, not an error |
| `notify.RecordOpened(userID, deliveryID)` | REST `POST /notifications/deliveries/{id}/opened` (app) | `error` only | `NOT_FOUND`/`TENANT_MISMATCH` (not caller's row), `CONFLICT` (topic rows, terminal `failed`) | Idempotent — write-once `opened_at` (INV-6) |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first. **No module other than 06 imports the FCM Admin SDK or
the Expo push client** (`tech-stack.md` — 04 holds no FCM credentials; 05 only calls the export).

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `fcm_topic_bindings` reads + `hierarchy.ResolveUserNodes(userID)` — the only topic-name source | 04 | Defer subscription via `topics.backfill`; never invent topic names; directed sends unaffected |
| `jobs.Enqueue` + worker registration (`fanout.send`, `tokens.prune`, `topics.backfill`) | 01 | Deliveries remain `queued`; workers are status-scoped and drain on recovery |
| `audit.Record` — test sends, campaign-class broadcasts | 01 | Audit failure logged, send not blocked |
| Auth chain + `users` (locale, `PENDING/VERIFIED/SUSPENDED`) | 03 | Chain failures propagate as designed (`UNAUTHENTICATED`/`FORBIDDEN`); SUSPENDED → unsubscribe + skip sends |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Device register / delete / prune | `notifications:devices:{userId}` (Redis `notify:devices:{userId}` invalidated) |
| `PATCH /notifications/preferences` | `notifications:prefs:{userId}` |
| Opened report / status transitions | none (delivery rows are never page-cached) |
| 04 binding changes (migration) | `notify:bindings:{topicName}` entries touched by 04's `hierarchy:*` mutations |

| Read | Tagged with |
| --- | --- |
| `GET /notifications/preferences` | `notifications:prefs:{userId}` (short TTL) |
| Device lookup on the fan-out hot path | `notify:devices:{userId}` (Redis, TTL 5 min) |
| Binding lookup before a topic send | `notify:bindings:{topicName}` (Redis, TTL 10 min; authoritative source is 04's table) |
| `GET /notifications/deliveries*` | never cached (per-user/tenant audit surface) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM (Firebase Admin Go SDK, HTTP v1) | HTTPS — topic send; per-token subscribe/unsubscribe | Service account `FCM_SERVER_KEY` (envconfig-parsed; held by 06 only) | 10 s | ×3 exponential backoff via `fanout.send` → dead-letter | Topic dispatches queue in `jobs`; notices remain in-app + WS (05); never fatal |
| Expo push API | HTTPS push API + push receipts (expo-server-sdk push client), chunk 100/request | `EXPO_ACCESS_TOKEN` (token auth; config-parsed) | 10 s | ×3 exponential backoff; invalid-token responses prune immediately | Directed sends stay `queued` and drain on recovery; senders unaffected |
| (R2, DeepSeek, payment gateways, SMS) | n/a | n/a | n/a | n/a | This module touches none of them |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Primer "Allow" (app) | `POST /api/v1/notifications/devices` | `{token, platform, appVersion}` → `DeviceDTO` + subscribed topics; 200-on-upsert idempotency |
| Logout (app, 03 flow) | `DELETE /api/v1/notifications/devices/{id}` | `{deleted:true}`; 404 treated as success (idempotent cleanup) |
| Settings toggles (app) | `GET/PATCH /api/v1/notifications/preferences` | Always exactly three rows; `validation.notifications.class_invalid` mapped inline |
| Directed push tap (app) | `POST /api/v1/notifications/deliveries/{id}/opened` | 204; idempotent; `CONFLICT` for topic rows silently ignored |
| Notice composer (07 web, School Admin) | server-side `notify.BroadcastTopic` via 05's `PostNotice` path | Topic from notice scope; payload `type=notice` |
| Test-push control + delivery aggregates (07 web) | `POST /api/v1/admin/notifications/test` · `GET /school│admin/notifications/deliveries` | Role-gated per 03 §2; counts only, never bodies |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. The **push payload schema is v1 and
frozen for Phase 1**: new `type` values and optional `data` fields are additive; unknown types
fall back to the home tab (05 §2.4), so old clients survive new senders. The deep-link route map
is additive only; `payment_result`'s receipt route is frozen jointly with module 12. Topic
naming (`city-{id}`/`school-{id}`/`section-{id}`) is owned by 04 (`ORG-BR-011`) and consumed
verbatim. Exported Go signatures above are frozen for Phase 1 consumers (05/10/12/13/03).

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| FCM down / degraded | Everything in-app: notices tab + WS (05), chat, preferences, device registration | No push banners; topic deliveries queue | `fanout.send` retries; drain on restore; push is an enhancement layer, never the source of truth (`NTF-IT-001` proven with fake) |
| Expo push API down | Topic pushes (FCM path), all REST surfaces | Directed pushes (DMs, matches, receipts) delayed | Queue drains ×3 backoff; receipts reconcile after |
| 01 jobs worker down | All REST reads/writes; providers reachable | Deliveries stuck `queued` | Status-scoped workers drain on restart; lag alarm per 01/15 runbooks |
| 04 bindings missing (user PENDING) | Directed pushes; token storage | No hierarchy-topic pushes yet | `topics.backfill` subscribes on verification (`NTF-IT-006`) |
| Provider rejects tokens (uninstall) | Everything else | That device silently skipped | Prune + `failed` row; re-register resumes (`NTF-IT-003`) |
| Neon (Postgres) cold start | Nothing DB-backed | Slow registration/preferences reads | Job retries; warm-up per 01/15 runbooks |
| R2 / DeepSeek / payment gateways | n/a — this module has no dependency on them | — | — |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `NTF-UT-001` | Deep-link payload schema v1: type → route map, key/args shape, no message bodies, additive-unknown handling | Unit | §7 stability + `NTF-BR-003` privacy |
| `NTF-IT-001` | Fan-out IT: notice publish → `BroadcastTopic` resolves `school-{id}`/`section-{id}` from `fcm_topic_bindings` (fake FCM); delivery row `sent` | Integration | I-1/I-3 contract; topic-per-node mirrors hierarchy (`brd.md` §6) |
| `NTF-IT-002` | Mute respected IT: muted class → `SendToUser` no-ops end-to-end; re-enable restores | Integration | `NTF-BR-004` |
| `NTF-IT-003` | Invalid-token pruning IT: dead token in batch → pruned + `failed`, remainder `sent`, never re-targeted | Integration | `NTF-BR-006`, provider-failure path |
| `NTF-IT-004` | Cross-tenant delivery read denied: School Admin A → school B `TENANT_MISMATCH`/404; own-user reads leak nothing | Integration | `NTF-BR-008` tenant isolation (mandatory) |
| `NTF-IT-006` | Device register subscribes bound topics (VERIFIED); PENDING device back-fills post-verification | Integration | I-3/I-8 degradation |
| `NTF-E2E-001` | Maestro: admin test push → tray renders (bn) → tap → app lands on the mapped screen → `opened` recorded | Maestro (app) | `NTF-US-004`/`NTF-US-009` golden path |
| `NTF-E2E-002` | Maestro: mute `campaigns` in settings → test push of that class shows no banner/tray | Maestro (app) | `NTF-US-006` channel alignment |

(Full unit/integration matrix — including `NTF-IT-005` auth-chain and `NTF-IT-007`/`008` — lives
in `03-backend-tasks.md` §6; rows here are the cross-module/integration set.)

## 10. Task Checklist

- [ ] `NTF-INT-001` Implement + export `notify.BroadcastTopic` (bindings guard, fake-able FCM client) — ____
- [ ] `NTF-INT-002` Implement + export `notify.SendToUser` (prefs gate, chunked Expo send, prune-on-invalid) — ____
- [ ] `NTF-INT-003` Implement + export `notify.RecordOpened` + wire `POST /notifications/deliveries/{id}/opened` — ____
- [ ] `NTF-INT-004` Consume 04 `fcm_topic_bindings` + `ResolveUserNodes`; register `topics.backfill` with 01 worker — ____
- [ ] `NTF-INT-005` Register `fanout.send` + `tokens.prune` jobs with 01 runner (status-scoped, idempotent) — ____
- [ ] `NTF-INT-006` FCM + Expo clients: timeouts (10 s), ×3 backoff, redacted logs, env-parsed secrets (`FCM_SERVER_KEY`, `EXPO_ACCESS_TOKEN`) — ____
- [ ] `NTF-INT-007` Freeze payload schema v1 + deep-link route map with 05/10/12/13 review; unknown-type fallback verified — ____
- [ ] `NTF-INT-008` Tests `NTF-UT-001`, `NTF-IT-001`–`004`, `NTF-IT-006`, `NTF-E2E-001`–`002` green in CI — ____
