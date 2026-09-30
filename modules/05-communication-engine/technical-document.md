# Communication Engine — Technical Document

**Module:** `05-communication-engine` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Overview

### 1.1 Purpose

The real-time communication core: hierarchy-driven group chat (official / custom "club" / DMs) over
the Go WebSocket gateway, one-way notice boards, Message Requests for out-of-network DMs, and media
messaging (image/PDF/voice) via Cloudflare R2 — optimistic, offline-tolerant, bilingual. Serves
`brd.md` §2 Goal 1 (replace chaotic WhatsApp groups) and BR-01; the Phase-1 exit criterion (`README.md`).

### 1.2 Scope

**In:** group chat `official` (section-bound, created by 04) / `custom` (clubs, School-Admin
approved) / `dm` (cross-school only after an accepted request) · WS gateway (gorilla rooms + Redis
pub/sub), presence, typing, read receipts · text/image/PDF/voice with optimistic UI, `client_msg_id`
idempotency, offline queue, tombstone deletes · Message Requests · one-way notices (pin, soft
delete, one attachment) · R2 upload service (`PresignUpload`/`ConfirmUpload`, magic-byte sniffing)
reused by 08/11/12 · 90-day media archival.
**Out:** push delivery (06) · campaigns rendering (13, seam COM-US-012) · web notice composer (07) ·
live calls (`brd.md` §4) · E2E encryption (rejected, `02` §10) · AI over chat content (09 gets
aggregates only).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations + 02 design-system | OpenAPI codegen, error envelope, job runner, rate limiter, Redis client · bn/en catalogs (`chat.*`, `notices.*`, `validation.*`), tokens, RN primitives |
| consumes | 03 + 04 | Verified gate (`NOT_VERIFIED`), JWT auth chain, five roles · section/school nodes, enrollments, `hierarchy.ResolveUserNodes` (WS room resolution, notice scoping) |
| consumes / consumed by | 06 notifications | We call `notify.BroadcastTopic(topic, payload)` for notice pushes; no other coupling |
| consumed by | 04 organization-hierarchy | calls `chat.JoinSectionGroups` / `chat.ArchiveSectionGroups` (on verification / migration) |
| consumed by | 07 / 08 / 11 / 12 | 07: REST #11–#15 + club approval via generated client · 08/11/12: `media.PresignUpload` / `ConfirmUpload` |
| consumed by | 09 / 10 | 09: `chat.GroupMembers` (aggregates only) · 10: DM deep link `/messages/{peerId}` |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| API runtime / contracts | Go 1.24+ · chi REST · `log/slog` · OpenAPI 3.1 → oapi-codegen | Resolved stack (`docs/tech-stack.md`); WS payloads mirror the OpenAPI DTOs | 20 REST endpoints + 1 WS gateway; `client_msg_id` + `message.ack` echo frozen |
| Realtime | gorilla/websocket gateway + Redis pub/sub fan-out | Rooms mirror the hierarchy; plain WS the RN client speaks natively (Socket.IO/Centrifugo rejected, `02` §10) | Channels `room:{id}`; presence keys TTL 60 s |
| Data access | sqlc + pgx/v5 · PostgreSQL 16 on Neon | Postgres is the source of truth — a Redis outage never loses messages | testcontainers-go for ITs |
| Cache / presence / jobs | Redis (go-redis) · In-DB `jobs` table + 01 worker | Notice lists (TTL 60 s, tags `notices:*`), presence, typing, rate limits · `media-archival` (daily), `message-request-expiry` (hourly), `pending-asset-cleanup` (daily), all idempotent | Redis down → single-instance delivery, never data loss |
| Media storage | Cloudflare R2 (S3 API) + magic-byte sniffing | Presigned PUT/GET, CopyObject archive/rehydrate; api never proxies bytes | Env `R2_*` |
| App / Web | App: plain WS client + optimistic UI; expo-image-manipulator + expo-av · Web: none in this module | Offline queue (zustand + MMKV); image ~1 MB target; voice record/play · 07 builds the notice composer + club approval queue against these REST endpoints | Reconnect backoff 1 s → 30 s cap · `COM-FE-001` contract handoff only |

---

## 3. Architecture

### 3.1 Component diagram

```text
Expo app (plain WS + REST)            07 web (notices/clubs, openapi-fetch)
  │ JWT upgrade GET /api/v1/ws             │ REST
  ▼                                        ▼
[chi REST] ──► [chat / notice / request / media services] ──► [tenant-scoped repos] ──► sqlc ──► PostgreSQL (Neon)
  │                   │                       ▲
[gorilla WS gateway] ─┤ rooms (group:/dm:)    │
  hub per room        ├─► 06 notify.BroadcastTopic · 04 hierarchy.ResolveUserNodes
  │                   └─► 01 jobs: media-archival · request-expiry · asset-cleanup
  ▼ publish/subscribe
Redis pub/sub room:{id} ──► other api instances ──► their room hubs ──► subscribed clients
Redis presence (TTL 60 s) · rate limits        Cloudflare R2: presign PUT/GET · CopyObject
```

WS gateway path: client → gorilla room hub → Redis pub/sub `room:{id}` → other instances → their rooms.

### 3.2 Boundary

**Owns (tables / services):** `chat_groups`, `chat_group_members`, `chat_messages`,
`message_requests`, `notices`, `media_assets` — plus the WS gateway (`gateway.Run`), the DM resolver
and the shared R2 upload service. **Reads (via exported service functions only):** 03 verification
status + role claims · 04 `hierarchy.ResolveUserNodes` + node lookups · 06 `notify.BroadcastTopic` ·
01 job runner, rate limiter, Redis client. Cache tags: `notices:school:{id}`, `notices:section:{id}`.

### 3.3 Request / data flows

```text
1. Send (WS): message.send{clientMsgId,…} → chat.SendMessage (verified + member + rate limit;
   idempotent upsert (sender_id, client_msg_id)) → Postgres insert → message.ack to sender;
   publish room:{groupId} → Redis pub/sub → all instances → message.new
2. Media: compress → POST /media/upload-url → PUT R2 (TTL 15 min) → POST /media/{id}/confirm
   (magic-byte sniff) → send message referencing the asset
3. Notice: POST /notices → role→scope guard → bust notices:* tags → WS notice.new
   → 06 BroadcastTopic(school-{id} | section-{id})
4. Request: POST /chat/message-requests → pending (no room) → accept → DM room
   dm:{minUserId}:{maxUserId} created + linked → WS + push both sides
5. Reconnect: backoff 1→30 s → re-subscribe resolved rooms → REST catch-up from latest cursor
   → replay offline queue (dedupe by client_msg_id)
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| Message — client view / server | SENDING → SENT → DELIVERED → SEEN / confirmed → visible → TOMBSTONED | server insert + `message.ack` (echoes `client_msg_id`); DELIVERED derived (peer online), not stored; SEEN when peer `last_read_message_id` ≥ message; delete = author ≤ 15 min / moderator-owner-School Admin anytime — soft delete only (`deleted_at`), never row removal |
| `media_assets.status` | pending → confirmed → archived | `ConfirmUpload` (magic-byte sniff OK, TTL ≤ 15 min, owner); 90-day job → archived (`archive/` prefix, rehydrate on demand) |
| `chat_groups[custom].status` | pending_approval → active → archived | same-tenant School Admin approves; creator becomes `owner` (approval default ON — `TODO: Confirm` OQ-2) |
| `message_requests.status` | pending → accepted / declined / expired | accept creates the linked dm room; 7-day expiry job (default, OQ-3) |

---

## 4. Data Model (summary)

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `chat_groups` | Conversation room: `official` / `custom` / `dm` | `school_id` (NULL only for dm — cross-tenant by design) | `(school_id, kind, status)` · `(section_id)` · unique `(dm_min_user_id, dm_max_user_id)` | CHECK: `kind='dm'` ⇔ `school_id IS NULL`; official ⇒ `section_id NOT NULL` |
| `chat_group_members` | Membership + role + read pointer | `school_id` = the member's school | `(group_id)` · `(user_id)` · `(group_id, last_read_message_id)` | unique `(group_id, user_id)`; `last_read_message_id` drives seen counts |
| `chat_messages` | Messages: text/image/pdf/voice/system | `school_id` mirrors group's (NULL for dm; access by membership) | `(group_id, created_at DESC, id DESC)` (hot) · unique `(sender_id, client_msg_id)` · `(group_id, deleted_at)` | `client_msg_id` idempotency (BR-008); `deleted_at` tombstone |
| `message_requests` | Out-of-network DM gate | None — cross-tenant by nature; row-level `from`/`to` authorization | `(to_user_id, status)` · `(from_user_id, status)` · `(status, expires_at)` | CHECK `from ≠ to`; at most one `pending` per pair (partial unique); `expires_at = created_at + 7d` |
| `notices` | One-way board, `scope = school \| section` | `school_id` tenant column | `(school_id, scope, section_id, pinned DESC, published_at DESC)` · partial `(school_id) WHERE deleted_at IS NULL` | Immutable except `pinned` + soft delete (BR-006); optional confirmed attachment |
| `media_assets` | R2 objects (image/pdf/voice) | `school_id` = owner's school | `(owner_id)` · `(status, created_at)` · `(school_id, status)` | `mime` sniffed at confirm, not client-declared; `r2_key` `hot/{tenant}/{assetId}` → `archive/…` |

---

## 5. Contracts

### 5.1 REST endpoints

All under `/api/v1`; auth chain on every route (authenticate → role claims → tenant-scope → verified
gate); shapes in `03-backend-tasks.md` §2. Rate class `messaging` on sends/history/media; stricter
sub-limit on message-request creation (anti-spam).

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | GET `/chat/groups` · GET `/chat/groups/{id}/messages?before=&limit=` | Verified user / member | My groups + unread counts · history, 50/page, cursor `before` | `FORBIDDEN` non-member | COM-US-001 |
| 2 | POST `/chat/groups` · `POST·DELETE·PATCH /chat/groups/{id}/members[/{userId}]` | Verified user (create) · owner/mod/School Admin (members) | Custom club → `pending_approval`; membership management | `VALIDATION_FAILED`, `FORBIDDEN` | COM-US-013/014 |
| 3 | GET `/chat/dm/{peerId}` | Verified user | Open/create DM (same-school instant; cross-school without accepted request → hint) | `NOT_FOUND` | COM-US-008/009 |
| 4 | POST · GET `/chat/message-requests`; POST `…/{id}/accept` · `…/decline` | Verified user / recipient | Out-of-network request + inbox/sent · accept → create DM room / decline politely | `CONFLICT` dup-pending/non-pending, `RATE_LIMITED` | COM-US-009 |
| 5 | POST `/chat/messages` | Verified member | REST fallback send (+ media sync path) | `VALIDATION_FAILED`, `RATE_LIMITED`, `CONFLICT` archived group | COM-US-002/015 |
| 6 | DELETE `/chat/messages/{id}` · PATCH `/chat/groups/{id}/read` | Author ≤ 15 min / mod+ · member | Tombstone delete / set `last_read_message_id` | `FORBIDDEN`, `CONFLICT` window elapsed | COM-US-006/014 |
| 7 | GET `/notices?scope=` · POST `/notices` · DELETE `/{id}` · PATCH `/{id}/pin` | Read: tenant member · write: School Admin (school) / Teacher (own section); delete/pin: author / School Admin | One-way board: pinned-first list · publish (+ bust tags + `BroadcastTopic`) · soft delete / pin (only mutations, BR-006) | `FORBIDDEN` role/scope matrix | COM-US-010/011/012 |
| 8 | POST `/media/upload-url` · POST `/media/{id}/confirm` | Verified owner | Presigned R2 PUT (TTL 15 min) → magic-byte sniff → `confirmed` | `VALIDATION_FAILED` kind/size/mismatch/TTL | COM-US-003/004/005 |

### 5.2 Realtime / jobs

WS gateway `GET /api/v1/ws` (gorilla upgrade; JWT in `Authorization`; unverified → close 4401). The
server **resolves** rooms from hierarchy + memberships — non-member room requests are ignored +
logged; unknown server events are ignored by clients (additive).

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| WS connect · `subscribe` / `unsubscribe` | client after JWT upgrade | `{rooms: ["group:{id}", "dm:{min}:{max}"]}` — intersected with the membership-derived set | gateway room hubs | resolve failure (04 down) → disconnect; REST falls back to cached memberships |
| WS `message.send` → `message.new` / `message.ack` | member send (same service path as REST #7) | full message DTO on `room:{id}`; ack echo `{clientMsgId, id, createdAt}` to sender | room subscribers; optimistic UI swap | Redis down → single-instance delivery; Postgres-first, catch-up heals |
| WS `message.read` · `message.deleted` · `presence.update` · `typing` | `PATCH` read or WS wrapper · tombstone delete · heartbeat ≤ 30 s (presence TTL 60 s) · client ≤ 1/3 s per group (4 s expiry) | seen counts (`lastReadMessageId`) · tombstone swap (`{groupId, id, deletedAt}`) · `{groupId, userId, online}` · typing state | room subscribers | next read / catch-up heals; DB is source of truth; Redis down → presence/typing off (degraded) |
| WS `notice.new` · `error` | notice publish · rate flood | notice DTO summary (invalidates `notices:*`) · RFC-7807-shaped `{type, title, status}` | tenant members (push handled by 06) · sender | in-app list refetch; client backs off |
| job `media-archival` (`COM-BE-025`) | daily, 01 runner | confirmed assets > 90 d: copy `hot/…` → `archive/…`, `status='archived'`; messages stay linkable, rehydrate on demand | R2 cost control | Idempotent/status-checked; resume next run; alert after 3 failures; never deletes objects |
| jobs `message-request-expiry` (`COM-BE-026`, hourly) · `pending-asset-cleanup` (`COM-BE-027`, daily) | 01 runner schedules | `pending` requests past `expires_at` → `expired` · `pending` assets > 24 h → delete row + reap orphan R2 object | request inbox · R2 hygiene | re-run safe; reap only if no confirmed row references the key |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — frozen for Phase 1; DTOs only; callers must not persist member lists.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `chat.JoinSectionGroups(userID, enrollment)` | 04 (on verification, BR-01) | `error` — idempotent; creates official group per section, teacher→moderator | domain errors wrapped; caller logs |
| `chat.PostNotice(actor, NoticeInput)` | 07 (School Admin composer) | `NoticeDTO`; busts tags + triggers `BroadcastTopic` | `FORBIDDEN`, `VALIDATION_FAILED`, `NOT_VERIFIED` |
| `media.PresignUpload(owner, in)` · `media.ConfirmUpload(owner, assetID, in)` | 08 notes · 11 product images · 12 receipts | `PresignResult{assetID, uploadURL, expiresAt}` (15-min TTL; asset `pending`) · `MediaAssetDTO` (sniffed mime, status) — the security boundary | `VALIDATION_FAILED` kind/size · magic-byte mismatch / expired / non-owner |
| `chat.GroupMembers(groupID)` | 09 (analytics sampling) | `[]MemberDTO{userID, role, sectionID}` — aggregates only, never message bodies | `NOT_FOUND` |
| `chat.ArchiveSectionGroups(schoolID, sessionYear)` | 04 year-end migration | archived count; idempotent | domain errors |
| `chat.NoticeStats(schoolID)` | 07 dashboard | aggregate notice counts | `TENANT_MISMATCH` |
| `chat.SectionQuestionSamples(sectionID, from, to, limit≤200)` | 09 | anonymized, PII-masked text samples from the official section group; never persisted by caller | `FORBIDDEN`, `VALIDATION_FAILED` |
| `media.PutObject(in)` | 12 receipts | `MediaAssetDTO` (`confirmed`); server-side put, kind `receipt_pdf` | `VALIDATION_FAILED` |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

N/A — chat is app-first; no web screens in this module. Module 07 implements the School Admin
surfaces against endpoints #9–#12 and #3: `/school/notices` (list + pin/delete), `/school/notices/new`
(composer), `/school/notices/[id]`, `/school/clubs` (approval queue) — via the generated
`openapi-fetch` client, never the database. `COM-FE-001` verifies the handoff.

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/chat` (+ `/(tabs)/chat/requests`) | Chat home — segments Official · Custom · DMs; unread badges; request banner; `VerifiedGate` · Message Request inbox (received + sent; accept/decline states) | none (tab root) · push `type=message_request` | Stale list from cache + offline banner · accept/decline refused offline (safety action) |
| `/groups/[id]` · `/messages/[peerId]` | Group chat / DM screen (same component) — optimistic bubbles SENDING→SENT→SEEN, bn date separators, composer, voice sheet, media viewer | push topic `section-{id}` · `type=dm` · tuition-match link (10) | Sends queued (clock bubble + banner); history from cache; catch-up refetch on reconnect |
| `/(tabs)/notices` · `/notices/[id]` | Notices list (pinned first, scope badges, campaigns section fed by 13) + detail/attachment viewer | push topics `school-{id}` / `section-{id}` · push `type=notice` | Stale-while-revalidate; "recovering attachment" for archived media |
| `/(modals)/media-viewer` · `/(modals)/group-new` | Shared image/PDF viewer · create-club modal (3–60 chars → pending-approval success) | in-app only | Viewer: retry on restore; club creation needs connectivity |

WS→store: `message.new` appends to Query cache; `message.ack` swaps the temp bubble by `client_msg_id`;
`message.read`/`presence`/`typing` patch zustand slices; `notice.new` invalidates `notices:*` (`05-app-tasks.md` §4).

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Cloudflare R2 | Media storage: presigned PUT/GET, CopyObject (archive/rehydrate), HEAD on confirm | S3 REST | `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` (envconfig) | 5 s control ops; 3× exp backoff (api-side control ops only; client does the PUT) | Media blocked; text chat + notices unaffected; client queues media sends |
| Redis | Pub/sub `room:{id}`, presence keys (TTL 60 s), rate limits | RESP (go-redis) | `REDIS_URL` | 2 s ops, 500 ms publish; 1× immediate then drop | Single-instance WS delivery; presence/typing off; limits fail-closed to defaults |
| FCM (via 06 only) · Nginx (HestiaCP) · expo-notifications | Notice pushes · WS reverse proxy · push receipt/routing | HTTPS Admin SDK · TLS termination · native | 06's `FCM_SERVER_KEY` · — · 06-owned config | 06-owned · — · — | No push → WS + in-app still deliver · Upgrade headers + 300 s read timeout in module 15 runbook (I-12) · topic join/leave retried by 06; chat works without push |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `R2_ACCESS_KEY_ID` | Yes | Cloudflare R2 access key | `media.PresignUpload` / archival / rehydrate |
| `R2_SECRET_ACCESS_KEY` | Yes | Cloudflare R2 secret | R2 S3 client |
| `R2_BUCKET` | Yes | e.g. `kushol-media` | All media object ops (`hot/…` → `archive/…`) |
| `REDIS_URL` | Yes | e.g. `redis://127.0.0.1:6379/0` | Pub/sub `room:{id}`, presence, rate limits, notice cache |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Media caps per kind (image 10 MB / PDF 20 MB / voice 5 min) | gorilla/websocket + Redis pub/sub architecture |
| Presigned URL TTL (default 15 min) | Magic-byte sniffing on confirm (security invariant) |
| Media archival age (default 90 days) | `client_msg_id` idempotency; tombstone-only deletes |
| Message Request expiry (default 7 days) | One-way notices; role→scope publish matrix |
| Messaging rate-limit class thresholds | Room naming (`school:`/`section:`/`group:`/`dm:`); presence TTL 60 s |
| Custom-group approval toggle per school (default ON — `TODO: Confirm`) | History page size 50 |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope on all REST routes + WS handshake (same JWT; unverified users may not connect — `NOT_VERIFIED`, close 4401) |
| Role matrix | Verified members read/post their groups · owner/mod manage members · class Teacher is section-group moderator + publishes section notices · School Admin publishes school notices, approves clubs, moderates any tenant group · students/guardians have no notice write path (BR-005) |
| Tenant scope | `school_id = caller.tenantId` on groups/notices/media; messages require `group_id ∈ caller's memberships ∧ tenant match`; the only cross-tenant path is a DM after an accepted request — authorized by membership, never by tenant query (BR-012, `COM-IT-001`); `message_requests` row-level `from`/`to` only |
| Rate limits | Class `messaging` on sends/paginated reads/media; stricter bucket on `POST /chat/message-requests` (anti-spam, BR-013) |
| Audit events | Club approval; member remove/role change; request accept/decline; notice publish/pin/delete; message delete; media sniff rejections (logged, no content); job runs |
| Privacy / minors | Message Request gating: out-of-school contact needs explicit acceptance; tombstones replace deletes (audit + sync); bodies plain text, stored as-is; no message content in logs; push payloads carry titles/ids only; guardians/minors reachable only inside school scope or after an accepted request (`brd.md` §6) |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `NOT_VERIFIED` | Pending account | Every chat/notice/media surface for unverified users (BR-001); WS connect refused | `VerifiedGate` full-screen state + how-to (module 03 copy) |
| `UNAUTHENTICATED` / `FORBIDDEN` | No JWT / not a member or role-scope denial | Protected routes; WS upgrade → HTTP 401 / close 4401; publish outside the role→scope matrix; deleting another's message as plain member; teacher targeting an untaught section | Route to login; hide actions; explain membership |
| `TENANT_MISMATCH` (404 body) | Cross-tenant read/write | Group/notice/media access across tenants (BR-012) | Never reveal existence |
| `VALIDATION_FAILED` | Bad input / bad media | Body 1–4000; `client_msg_id` required; media kind/size caps; **magic-byte mismatch on confirm** (exe renamed `.jpg` rejected, no message created); notice title/body lengths | Inline `validation.*` / `chat.*` / `notices.*` field errors (bn + en) |
| `CONFLICT` / `RATE_LIMITED` | State clash / throttled | Archived-group post (pointer to new group); dup-pending request; double accept/decline; delete window elapsed · messaging class, stricter on message requests | Toast + state refresh · back off; bubble stays SENDING with retry |
| `NOT_FOUND` / `INTERNAL` | No room / unexpected | Cross-school DM without an accepted request (hint to send one) / unhandled failures (incl. 04 down on room resolution) | Offer Message Request composer; generic error + retry |

All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via
each app's `src/i18n` catalogs — every key ships in **bn + en** (Bengali default); namespaces `chat.*`,
`notices.*`, `validation.*`.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | `slog` JSON, redacted — **no message content in logs**; sniff-mismatch rejections logged without content; media/job outcomes logged |
| Metrics / counters | WS connections (~600/instance pilot), messages/s fan-out (~50 peak), Redis degraded flag, archival job failures, pending-request backlog |
| Health contribution · jobs & retries | `/readyz` via 01 (DB + Redis); WS ping/pong ≤ 30 s, 2 missed → close; gateway crash → clients reconnect to a surviving instance (no room affinity lost) · `media-archival` daily (idempotent, alert after 3 failures, never deletes) · `message-request-expiry` hourly · `pending-asset-cleanup` daily (reap only unreferenced objects) |
| Runbook pointers | WS proxy: Upgrade headers + 300 s read timeout (module 15 / I-12) · Redis down → single-instance delivery, restart + catch-up heals · R2 down → media blocked, text unaffected · Neon degraded → pool alarm + failover path (01/15) · failure-matrix drills scripted in CI smoke (`COM-INT-011`) |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Magic-byte sniffer (JPEG/PNG/HEIC/PDF/AAC; exe→reject); idempotent send; DM key ordering; role→scope notice matrix; delete window; request state machine; room-resolution intersection/denial; Redis-failure persistence | `COM-UT-001`–`007`, `COM-UT-010`–`011` | `go test ./...` |
| Integration | **Cross-tenant group access denied** (`TENANT_MISMATCH`/404, no leak); unverified → `NOT_VERIFIED` everywhere; **`client_msg_id` replay (REST + WS) → no duplicates, same id**; request accept/decline flow; **magic-byte confirm rejects exe-renamed `.jpg`**; notice scoping school/section/tenant; 90-day archival + rehydrate; read-receipt fan-out; auth chain incl. WS 401/4401; `BroadcastTopic` topic correctness (06 stubbed); `JoinSectionGroups` idempotent | `COM-IT-001`–`011` (testcontainers Postgres) | green in CI |
| E2E (Maestro, app) | Online send SENDING→SEEN on a second device · airplane-mode send → banner → reconnect → replayed exactly once · notice published (07 API) → push → deep link `/notices/[id]` | `COM-E2E-001`–`003` | green in CI |
| CI | api: `go test`/`vet`/`golangci-lint` · app: `pnpm lint/typecheck/test` + Maestro specs (`COM-AP-020`) | — | per-app quality gate |

Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; cross-tenant
attempts return `TENANT_MISMATCH`/404; publish guard blocks `TODO:`; public reads never see drafts.

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot 3 schools × ~2,000 users; ~10% concurrent WS (~600 conns/instance); ~50 msg/s peak fan-out; single 2 vCPU VPS instance, second instance additive via Redis pub/sub |
| Hot paths + indexes | History pagination `chat_messages (group_id, created_at DESC, id DESC)`; seen counts `(group_id, last_read_message_id)`; board query `(school_id, scope, section_id, pinned DESC, published_at DESC)`; 50/page cursor `before` |
| Latency targets | History page (50 rows) p95 ≤ 150 ms server-side; **send→render p95 ≤ 800 ms on 4G, ≤ 2.5 s on 3G** (optimistic render is local ≈ instant; the budget applies to the confirmed state) — measured in `COM-IT` perf smoke + Maestro timings |
| Fan-out / caching / bundle | One Redis publish per message → O(members) WS writes, no N+1; presence/typing in Redis with TTL — no DB writes; notices Redis TTL 60 s bust on publish/pin/delete; chat history never page-cached, memory-only per group/cursor in-app; no new heavy app deps (`expo-image-manipulator` + `expo-av` already in the SDK) |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the readiness-check table; unconfirmed items keep `TODO: Confirm`.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Chat retention / media TTL (OQ-1); 90-day archive + rehydrate expectations (02 §11.5) | Storage cost; principals expecting instant year-old photos | Rahul | Open | Messages indefinite per tenant; media 90 days R2 hot then archived (linkable, rehydrate in seconds) |
| 2 | Must clubs wait for School Admin approval? (OQ-2); students/guardians never post to school-wide boards (OQ-5) | Oversight vs friction; one-way notice model | Rahul | Open — `TODO: Confirm` (OQ-2) | Approval required, creator becomes `owner`; notices one-way — only School Admin (school) / Teacher (section) publish |
| 3 | Message Request expiry window (OQ-3) | Anti-spam vs reach | Rahul | Open | 7 days, then `expired` |
| 4 | Media caps + presign TTL + voice length (OQ-4 + 02 §11.6) | Upload UX; longer lectures | Rahul | Open | image 10 MB / PDF 20 MB / voice 5 min; TTL 15 min — tunable config, raise deliberately |
| 6 | Pilot scale fits one VPS instance (≤ ~1k concurrent WS); Neon free tier absorbs chat write volume (02 §11.1/§11.2) | Latency at growth; cold starts / connection limits | Rahul | Assumption | Redis pub/sub + stateless gateway = horizontal add, load test before 10-school push; pgx pool batching + documented upgrade path |
| 7 | Clients honour `client_msg_id`; magic-byte sniffing covers our kinds (02 §11.3/§11.4) | Duplicate UX noise; exotic uploads rejected | Rahul | Assumption | Server-side unique index backstop (INV-3); strict allowlist JPEG/PNG/HEIC, PDF, AAC/m4a — expand deliberately with tests |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-01 — auto-joined section groups + notices (Phase-1 exit) | §5.1 | `COM-US-001`–`008`, `014`–`015` | `COM-BE-001`–`010`, `013`, `015`–`020`, `COM-INT-001`, `003`, `005`, `007`, `010` | `COM-UT-002`–`003`, `007`, `010`–`011`, `COM-IT-001`–`003`, `008`–`011`, `COM-E2E-001`–`002` |
| `brd.md` §6 — anti-spam + safety | — | `COM-US-009`, `014` | `COM-BE-007`–`008`, `013`, `021` | `COM-UT-005`–`006`, `COM-IT-004` |
| PRD §4B — one-way boards + clubs | §4B | `COM-US-010`–`013` | `COM-BE-005`, `011`–`012`, `022`–`024`, `COM-INT-002` | `COM-UT-004`, `COM-IT-005`–`007`, `010`, `COM-E2E-003` |
| Retention default (`02` §5) + media exports (08/11/12) + 09 aggregates | — | `COM-US-003`–`005`, `016` | `COM-BE-006`, `012`, `014`, `024`, `025`–`027`, `COM-INT-003`–`004`, `006` | `COM-UT-001`, `COM-IT-005`, `COM-IT-007` |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migrations re-versioned `20261003…`; exports `ArchiveSectionGroups` (already called by 04), `NoticeStats` (07), `SectionQuestionSamples` (09), `media.PutObject` (12) declared; `notify.BroadcastTopic` naming; UI direction = CircleUp layout + WhatsApp chat (`docs/design-reference/README.md` §6) | Claude |
