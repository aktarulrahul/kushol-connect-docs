# Communication Engine — Backend Tasks & Database Design

**Module:** `05-communication-engine`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** N/A for this module — the School Admin notice composer (module 07) consumes these REST endpoints via the generated `openapi-fetch` client
**Last updated:** 2026-09-30

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `chat_groups` (model `ChatGroup`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `kind` | `text` | no | — | `official` \| `custom` \| `dm` (CHECK) |
| `school_id` | `uuid` | yes | — | Tenant column → 04 school node; **NULL only for `dm`** (cross-school by design; CHECK: `kind='dm'` ⇔ `school_id IS NULL`) |
| `section_id` | `uuid` | yes | — | 04 section node; NOT NULL iff `kind='official'` |
| `name` | `text` | yes | — | Custom groups only; official auto-named from section |
| `status` | `text` | no | `active` | `active` \| `pending_approval` (custom) \| `archived` |
| `created_by` | `uuid` | no | — | 03 user |
| `dm_min_user_id` / `dm_max_user_id` | `uuid` | yes | — | DM pair, ordered; unique together, NULL for non-dm |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK kind/invariants above; UNIQUE `(school_id, name)` where active+custom;
UNIQUE `(dm_min_user_id, dm_max_user_id)`. **Indexes:** `(school_id, kind, status)` → group
lists per tenant; `(section_id)` → official-group lookup on verification; dm unique pair →
`GET /chat/dm/{peerId}`.

#### `chat_group_members` (model `ChatGroupMember`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `group_id` | `uuid` | no | — | FK → `chat_groups` |
| `user_id` | `uuid` | no | — | FK → 03 users |
| `school_id` | `uuid` | no | — | Tenant column = **the member's** school (dm members keep their own) |
| `role` | `text` | no | `member` | `owner` \| `moderator` \| `member` |
| `joined_at` | `timestamptz` | no | `now()` | |
| `last_read_message_id` | `uuid` | yes | — | Read receipts pointer |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(group_id, user_id)`. **Indexes:** `(group_id)` → member roster +
WS room resolution; `(user_id)` → "my groups"; `(group_id, last_read_message_id)` → seen counts.

#### `chat_messages` (model `ChatMessage`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `group_id` | `uuid` | no | — | FK → `chat_groups`; every query joins membership for this group |
| `school_id` | `uuid` | yes | — | Tenant column, mirrors group's `school_id` (NULL for dm; access by membership) |
| `sender_id` | `uuid` | no | — | 03 user; `system` kind uses the acting system user |
| `kind` | `text` | no | `text` | `text` \| `image` \| `pdf` \| `voice` \| `system` |
| `body` | `text` | yes | — | 1–4000 when kind=text/system; NULL for media kinds |
| `media_asset_id` | `uuid` | yes | — | FK → `media_assets`; required for image/pdf/voice |
| `client_msg_id` | `uuid` | no | — | Client-generated; optimistic UI + idempotent replay |
| `reply_to` | `uuid` | yes | — | FK → `chat_messages` (same group) |
| `deleted_at` | `timestamptz` | yes | — | Soft delete → tombstone (never row deletion) |
| `created_at` | `timestamptz` | no | `now()` | Cursor component |

**Constraints:** UNIQUE `(sender_id, client_msg_id)` (idempotency, BR-008); CHECK
media kinds require `media_asset_id`. **Indexes:** `(group_id, created_at DESC, id DESC)` →
history pagination (hot query); `(sender_id, client_msg_id)` UNIQUE → replay dedupe;
`(group_id, deleted_at)` → tombstone filtering.

#### `message_requests` (model `MessageRequest`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `from_user_id` | `uuid` | no | — | Sender (03 user, verified) |
| `to_user_id` | `uuid` | no | — | Recipient (03 user, verified) |
| `status` | `text` | no | `pending` | `pending` \| `accepted` \| `declined` \| `expired` |
| `dm_group_id` | `uuid` | yes | — | Set on accept → the created DM room |
| `created_at` / `decided_at` / `expires_at` | `timestamptz` | no/yes/yes | `now()` | `expires_at = created_at + 7d` default |

**Constraints:** CHECK `from_user_id <> to_user_id`; at most one `pending` per
`(from_user_id, to_user_id)` (partial unique index). **Indexes:** `(to_user_id, status)` →
request inbox; `(from_user_id, status)` → sender's sent requests; `(status, expires_at)` →
expiry job. **Tenant rule:** none — cross-tenant by nature; row-level authorization
(`from`/`to` only) replaces tenant scope (INV-4, `02` §1.3).

#### `notices` (model `Notice`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | Tenant column → 04 school node |
| `scope` | `text` | no | `school` | `school` \| `section` |
| `section_id` | `uuid` | yes | — | Required iff `scope='section'`; must be in `school_id` |
| `author_id` | `uuid` | no | — | School Admin (school) / Teacher (section) |
| `title` | `text` | no | — | 3–120 |
| `body` | `text` | no | — | 1–5000, plain text |
| `pinned` | `boolean` | no | `false` | Only mutable field besides `deleted_at` (BR-006) |
| `attachment_id` | `uuid` | yes | — | FK → `media_assets` (confirmed) |
| `published_at` | `timestamptz` | no | `now()` | Display + ordering |
| `deleted_at` | `timestamptz` | yes | — | Soft delete |

**Constraints:** CHECK scope/section pairing. **Indexes:** `(school_id, scope, section_id,
pinned DESC, published_at DESC)` → the one board query; partial `(school_id) WHERE
deleted_at IS NULL`.

#### `media_assets` (model `MediaAsset`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK; `POST /media/{id}/confirm` target |
| `school_id` | `uuid` | no | — | Tenant column = owner's school |
| `owner_id` | `uuid` | no | — | Uploader (03 user) |
| `kind` | `text` | no | — | `image` \| `pdf` \| `voice` (allowlist) |
| `mime` | `text` | no | — | **Sniffed** at confirm, not client-declared |
| `size_bytes` | `bigint` | no | — | Re-checked at confirm vs cap |
| `width` / `height` | `int` | yes | — | Images (thumbnail layout) |
| `duration_ms` | `int` | yes | — | Voice |
| `r2_key` | `text` | no | — | Object key (`hot/{tenant}/{assetId}` → `archive/…` after 90 d) |
| `status` | `text` | no | `pending` | `pending` \| `confirmed` \| `archived` |
| `created_at` / `confirmed_at` / `archived_at` | `timestamptz` | no/yes/yes | `now()` | |

**Constraints:** kind ∈ allowlist; status transitions only pending→confirmed→archived.
**Indexes:** `(owner_id)`; `(status, created_at)` → archival job batch; `(school_id, status)` →
tenant storage stats.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261003090000_com_chat_groups_members` (chat_groups + chat_group_members, CHECKs, unique dm pair) | ✅ |
| 2 | `20261003091000_com_chat_messages` (messages + idempotency unique + pagination index) | ✅ |
| 3 | `20261003092000_com_message_requests` (requests + partial unique pending + expiry index) | ✅ |
| 4 | `20261003093000_com_notices` (notices + board composite index) | ✅ |
| 5 | `20261003094000_com_media_assets` (assets + archival indexes) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| "Demo High School" (fictional, marked) + 1 section + official group, 3 club requests (pending/active/declined), 2 notices (1 pinned, 1 with PDF), sample text/image/voice messages | `DRAFT` (clearly fictional) | `prd.md` §5.1 shapes; `TODO:` none — all fictional demo data per `prompt.txt` §12 |

---

## 2. Server Contracts

### Endpoint summary (all Go handlers generated from the OpenAPI spec; auth chain on every route: authenticate → load role claims → tenant-scope)

| # | Endpoint | Purpose | Errors (beyond common) | Stories |
| --- | --- | --- | --- | --- |
| 1 | `GET /api/v1/chat/groups` | My groups (official/custom/dm) w/ unread counts | — | US-001 |
| 2 | `GET /api/v1/chat/groups/{id}/messages?before={cursor}&limit=` | History, 50/page, cursor = `created_at+id` | `FORBIDDEN` if not member | US-001 |
| 3 | `POST /api/v1/chat/groups` | Create custom club → `pending_approval` | `VALIDATION_FAILED` | US-013 |
| 4 | `POST /api/v1/chat/groups/{id}/members` | Add member (owner/mod/School Admin) | `FORBIDDEN` | US-013 |
| 5 | `DELETE /api/v1/chat/groups/{id}/members/{userId}` | Remove member (mod+) | `FORBIDDEN` | US-014 |
| 6 | `PATCH /api/v1/chat/groups/{id}/members/{userId}` | Change role (mod+/School Admin) | `FORBIDDEN` | US-013 |
| 7 | `GET /api/v1/chat/dm/{peerId}` | Open/create DM (same-school instant; else 404 + request hint) | `NOT_FOUND` (cross-school, no accepted request) | US-008/009 |
| 8 | `POST /api/v1/chat/message-requests` | Create out-of-network request | `CONFLICT` dup-pending; `RATE_LIMITED` | US-009 |
| 9 | `GET /api/v1/chat/message-requests` | My inbox (received) + sent | — | US-009 |
| 10 | `POST /api/v1/chat/message-requests/{id}/accept` | Accept → create DM room | `CONFLICT` non-pending | US-009 |
| 11 | `POST /api/v1/chat/message-requests/{id}/decline` | Decline | `CONFLICT` non-pending | US-009 |
| 12 | `POST /api/v1/chat/messages` | REST fallback send (+ media confirm sync path) | `VALIDATION_FAILED`, `RATE_LIMITED` | US-002/015 |
| 13 | `DELETE /api/v1/chat/messages/{id}` | Tombstone (author ≤15 min / mod+) | `FORBIDDEN`, `CONFLICT` window elapsed | US-014 |
| 14 | `PATCH /api/v1/chat/groups/{id}/read` | Set `last_read_message_id` | — | US-006 |
| 15 | `GET /api/v1/notices?scope=` | Board for my school (+ my sections) | — | US-012 |
| 16 | `POST /api/v1/notices` | Publish (School Admin school-scope / Teacher section-scope) | `FORBIDDEN` | US-010/011 |
| 17 | `DELETE /api/v1/notices/{id}` | Soft delete (author/School Admin) | `FORBIDDEN` | US-010 |
| 18 | `PATCH /api/v1/notices/{id}/pin` | Toggle pin | `FORBIDDEN` | US-010 |
| 19 | `POST /api/v1/media/upload-url` | Presigned R2 PUT (TTL 15 min) | `VALIDATION_FAILED` kind/size | US-003/004/005 |
| 20 | `POST /api/v1/media/{id}/confirm` | Magic-byte sniff → `confirmed` | `VALIDATION_FAILED` mismatch | US-003 |

Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` ·
`TENANT_MISMATCH` · `NOT_FOUND` · `NOT_VERIFIED` · `RATE_LIMITED` · `CONFLICT` · `INTERNAL`
(RFC-7807 `application/problem+json`). Rate-limit class `messaging` on 2/8/12/14/19/20;
stricter sub-limit on 8.

### Detailed endpoint blocks

### Endpoint `POST /api/v1/chat/messages` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope → verified gate |
| **Input** | `{groupId, kind, body?, mediaAssetId?, clientMsgId, replyTo?}`; contract-generated validator; request struct from `oapi-codegen` |
| **Result** | `{ "data": { message } }` (full DTO incl. canonical `id`); WS `message.ack` carries the same shape |
| **Errors** | `NOT_VERIFIED` · `FORBIDDEN` (non-member) · `VALIDATION_FAILED` (body/asset) · `RATE_LIMITED` · `CONFLICT` (archived group) |
| **Rate limit** | `messaging` (per user+group) |
| **Audit** | No (system-kind messages audit the acting admin) |
| **Stories** | COM-US-002/003/015 |

### Endpoint `POST /api/v1/media/upload-url` + `POST /api/v1/media/{id}/confirm`

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope → verified gate |
| **Input** | upload-url: `{kind, sizeBytes, mime?}` (declared; sniff is authoritative). confirm: path id; body `{width?, height?, durationMs?}` |
| **Result** | upload-url: `{assetId, uploadUrl, expiresAt}` (R2 presigned PUT, TTL 15 min). confirm: `{assetId, mime, sizeBytes, status:"confirmed"}` |
| **Errors** | `VALIDATION_FAILED` (kind/size cap, sniff mismatch, TTL expired, non-owner) · `NOT_VERIFIED` |
| **Rate limit** | `messaging` |
| **Audit** | Rejection of sniff-mismatched file logged (slog, no content) |
| **Stories** | COM-US-003/004/005 · guards BR-009/INV-6 |

### Endpoint `POST /api/v1/notices` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope |
| **Input** | `{scope, sectionId?, title, body, pinned?, attachmentId?}` |
| **Result** | `{ "data": { notice } }`; triggers tag bust `notices:*` + `notify.BroadcastTopic` |
| **Errors** | `FORBIDDEN` (role/scope matrix, INV-5) · `VALIDATION_FAILED` · `NOT_VERIFIED` |
| **Rate limit** | default class (admins/teachers only) |
| **Audit** | Yes — publish/pin/delete audited (school-sourced content) |
| **Stories** | COM-US-010/011 |

### WebSocket gateway protocol (`GET /api/v1/ws` → gorilla upgrade; documented contract, mirrored by the app client)

| Direction | Event | Payload (shape) | Notes |
| --- | --- | --- | --- |
| client → server | connect | JWT in `Authorization` header at upgrade | Reject: HTTP 401 / close 4401; unverified users may connect read-only **no** — connect refused with `NOT_VERIFIED` reason code |
| client → server | `subscribe` | `{rooms: ["group:{id}", "dm:{min}:{max}"]}` | Server **resolves** allowed rooms from hierarchy + memberships; requests for non-member rooms are ignored + logged |
| client → server | `unsubscribe` | `{rooms: []}` | |
| client → server | `message.send` | `{clientMsgId, groupId, kind, body?, mediaAssetId?, replyTo?}` | Same service path as REST #12 |
| client → server | `message.read` | `{groupId, lastReadMessageId}` | Thin wrapper over service (#14) |
| client → server | `typing` | `{groupId, state: "start"\|"stop"}` | Throttled ≤ 1/3 s per group |
| client → server | `ping` | — | Heartbeat ≤ 30 s; 2 missed → close; presence key TTL 60 s refreshed on activity |
| server → client | `message.new` | full message DTO | Fan-out via Redis pub/sub channel `room:{roomId}` |
| server → client | `message.ack` | `{clientMsgId, id, createdAt}` | Optimistic temp→confirmed swap (echo contract) |
| server → client | `message.read` | `{groupId, userId, lastReadMessageId}` | Drives seen counts |
| server → client | `message.deleted` | `{groupId, id, deletedAt}` | Tombstone swap |
| server → client | `presence.update` | `{groupId, userId, online}` | Presence from Redis keys (TTL 60 s) |
| server → client | `typing` | `{groupId, userId, state}` | Auto-expire 4 s client-side |
| server → client | `notice.new` | notice DTO (summary) | Invalidates notices cache; push handled by 06 |
| server → client | `error` | RFC-7807-shaped `{type, title, status}` | e.g. `RATE_LIMITED` on flood |

**Reconnect contract:** exponential backoff (1 s → 30 s cap, jitter) → re-auth → re-subscribe
resolved rooms → REST catch-up `GET …/messages?before={latestLocalCursor}` → replay offline
queue (dedupe by `client_msg_id`).

### Web Server Action / Route Handler (Next.js)

N/A — this module ships no web UI. Module 07 (`07-command-center-web`) implements the School
Admin notice composer and club approval queue as Next.js screens calling these endpoints via the
generated `openapi-fetch` client (never the database directly):

- `/school/notices` — list + pin/delete (endpoints #15/17/18)
- `/school/notices/new` — composer (endpoint #16, media #19/#20 for attachments)
- `/school/clubs` — custom-group approval queue (endpoints #3/#4/#6 with approve action)

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `COM-BE-001` | `chat.CreateOfficialGroups(section)` | Called via `chat.JoinSectionGroups` export; official group per section; teacher→moderator; students→member | — | No |
| `COM-BE-002` | `gateway.Run()` | JWT upgrade, room resolution (hierarchy+memberships), hub per room, Redis pub/sub bridge, presence TTL 60 s | — | No |
| `COM-BE-003` | `chat.SendMessage(sender, in)` | Verified + member + rate limit; media asset must be `confirmed` + owned; idempotent upsert on `(sender_id, client_msg_id)`; fan-out `message.new` + `ack` | — | No |
| `COM-BE-004` | `chat.ListMessages(groupID, cursor, limit)` | Member guard; tombstones included (marked) for renderers; cursor `before` pagination 50/page | — | No |
| `COM-BE-005` | `chat.CreateCustomGroup / ApproveCustomGroup / ListMyGroups` | Custom → `pending_approval`; approve = same-tenant School Admin; creator→`owner` | — | Yes (approve) |
| `COM-BE-006` | `chat.AddMember / RemoveMember / ChangeRole / GroupMembers(groupID)` | mod+ guards; School Admin within tenant; exports DTOs only | — | Yes (remove/role) |
| `COM-BE-007` | `chat.OpenDM(user, peerID)` | Same-school verified ⇒ open/create; cross-school ⇒ `NOT_FOUND` unless accepted request links a room; pair-order key `dm:{min}:{max}` | — | No |
| `COM-BE-008` | `chat.CreateMessageRequest / Accept / Decline / ListRequests` | No self/dup-pending; accept creates DM room + links; decline blocks politely; expiry job flips `expired` | — | Yes (accept/decline) |
| `COM-BE-009` | `chat.MarkRead(groupID, msgID)` + `chat.SeenCounts` | Member guard; updates `last_read_message_id`; fans out `message.read` | — | No |
| `COM-BE-010` | `presence.Set/Get` + `typing.Relay` | Redis TTL 60 s keys; typing throttled ≤1/3 s, 4 s client expiry | — | No |
| `COM-BE-011` | `chat.PostNotice(...) / PinNotice / DeleteNotice / ListNotices` | Role→scope matrix (INV-5); pin/delete = only mutations; list = pinned-first, tenant+section scoped | `notices:school:{id}` · `notices:section:{id}` | Yes |
| `COM-BE-012` | `media.PresignUpload / ConfirmUpload` | Caps per kind; TTL 15 min; sniff magic bytes server-side, re-check size, allowlist mime; pending cleanup 24 h | — | Yes (rejects) |
| `COM-BE-013` | `chat.DeleteMessage(msgID, actor)` | Author ≤ 15 min; mod/owner/School-Admin anytime; soft delete + `message.deleted` fan-out | — | Yes |
| `COM-BE-014` | `jobs.ArchiveMedia` (see §5) | Idempotent batch; hot→`archive/` prefix; status-guarded | — | Yes (job run) |
| `COM-BE-015` | `chat.WSCatchup(groupID, cursor)` | REST-shaped catch-up used after reconnect; same repository path as #4 | — | No |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `COM-BE-016` | `InsertGroup / GetGroupByID / ListGroupsForUser` | tenant-scoped SELECT/INSERT | `(school_id, kind, status)` · `(user_id)` via members join |
| `COM-BE-017` | `InsertMember / DeleteMember / UpdateMemberRole / UpdateLastRead` | tenant-scoped upsert/UPDATE | UNIQUE `(group_id, user_id)` |
| `COM-BE-018` | `InsertMessage` (`ON CONFLICT (sender_id, client_msg_id) DO NOTHING` + re-SELECT) | idempotent insert returning canonical row | UNIQUE `(sender_id, client_msg_id)` |
| `COM-BE-019` | `ListMessagesByGroup(groupID, before, limit)` | `WHERE group_id=$1 AND created_at<cursor ORDER BY created_at DESC, id DESC LIMIT 50` | `(group_id, created_at DESC, id DESC)` |
| `COM-BE-020` | `SoftDeleteMessage` | `UPDATE … SET deleted_at=now()` only | PK |
| `COM-BE-021` | `InsertRequest / UpdateRequestStatus / ListRequestsForUser / ExpireStaleRequests` | row-level from/to guard in WHERE | `(to_user_id, status)` · `(status, expires_at)` |
| `COM-BE-022` | `InsertNotice / UpdateNoticePin / SoftDeleteNotice / ListNoticesBySchool` | tenant + scope + section filter; pinned-first ORDER BY | `(school_id, scope, section_id, pinned DESC, published_at DESC)` |
| `COM-BE-023` | `InsertAsset / ConfirmAsset / ListStaleHotAssets / MarkArchived` | status-guarded transitions | `(status, created_at)` |
| `COM-BE-024` | `MembersOfGroup(groupID)` | join users for DTO (id, name, role) — export for 09 (aggregates only) | `(group_id)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `COM-BE-025` | `media-archival` — confirmed assets `created_at < now()-90d`: copy `hot/…` → `archive/…` in R2, then `status='archived'` + `archived_at` | Daily (module 01 job runner) | Yes — status-checked per asset; safe to re-run | Batch resumes next run; alert after 3 failures; never deletes objects |
| `COM-BE-026` | `message-request-expiry` — `pending` ∧ `expires_at < now()` → `expired` | Hourly | Yes | Re-run safe; no side effects beyond status |
| `COM-BE-027` | `pending-asset-cleanup` — `pending` ∧ `created_at < now()-24h` → deleted row + orphan object reaped | Daily | Yes | R2 object reaped only if no `confirmed` row references the key |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `COM-UT-001` | Magic-byte sniffer: JPEG/PNG/HEIC→image, `%PDF`→pdf, AAC/m4a→voice; EXE renamed `.jpg` → reject | Unit | BR-009 / INV-6 |
| `COM-UT-002` | Idempotent send: same `(sender, client_msg_id)` twice → one row, same canonical id | Unit | BR-008 / INV-3 |
| `COM-UT-003` | DM key ordering `dm:{min}:{max}` + pair uniqueness | Unit | INV-8 |
| `COM-UT-004` | Role→scope notice matrix (School Admin/school, Teacher/own section, student ⇒ denied) | Unit | BR-005 / INV-5 |
| `COM-UT-005` | Delete window: author 14:59 allowed, 15:01 refused; moderator anytime | Unit | BR-007 |
| `COM-UT-006` | Message-request state machine incl. double-accept/double-decline → `CONFLICT` | Unit | INV-4 |
| `COM-UT-007` | Room resolution: client-subscribed rooms intersected with membership-derived set | Unit | WS security (02 §6) |
| `COM-IT-001` | Cross-tenant group/notice/media access → `TENANT_MISMATCH`/404, no leak (testcontainers Postgres) | Integration | BR-012 / INV-1 |
| `COM-IT-002` | Unverified user cannot post, request, presign or publish → `NOT_VERIFIED` | Integration | BR-001 |
| `COM-IT-003` | Replay send over REST + WS with same `client_msg_id` → no duplicate rows, same id returned | Integration | BR-008 |
| `COM-IT-004` | Out-of-network DM blocked until request accepted; accept creates linked room; decline blocks with polite error | Integration | BR-004 / US-009 |
| `COM-IT-005` | Media confirm rejects exe-renamed-`.jpg`; correct file → `confirmed`; message referencing `pending` asset refused | Integration | INV-6 |
| `COM-IT-006` | Notice visibility: section notice invisible to other-section member of same school; school notice visible school-wide; other tenant → nothing | Integration | BR-012 / INV-5 |
| `COM-IT-007` | Archival job: 91-day asset → archived + key moved; message intact; re-run no-ops; rehydrate restores hot key | Integration | BR-011 / COM-BE-025 |
| `COM-IT-008` | Read receipts: `last_read_message_id` update fans out `message.read`; seen count correct for 3-member group | Integration | US-006 |
| `COM-IT-009` | Every protected endpoint unauthenticated → `UNAUTHENTICATED`; WS upgrade without JWT → 401/4401 | Integration | Auth chain |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
publish guard blocks `TODO:`; public reads never return drafts.

## 7. Task Checklist

### Schema

- [ ] `COM-BE-001` migrations 1–5 (groups/members, messages, requests, notices, media assets)
- [ ] `COM-BE-016`–`COM-BE-024` sqlc queries + tenant-scoped repositories

### Repository · Service · Entry points · Seed · Tests

- [ ] `COM-BE-002` WS gateway (hub, rooms, Redis bridge, presence, heartbeat)
- [ ] `COM-BE-003`/`COM-BE-004` send + history services; REST #12 + WS `message.send` wiring
- [ ] `COM-BE-005`/`COM-BE-006` group + membership services; `JoinSectionGroups`/`GroupMembers` exports
- [ ] `COM-BE-007`/`COM-BE-008` DM + message-request services
- [ ] `COM-BE-009`/`COM-BE-010` read receipts, presence, typing
- [ ] `COM-BE-011` notice service + `PostNotice` export + tag busts + `BroadcastTopic` call
- [ ] `COM-BE-012` `media.PresignUpload`/`ConfirmUpload` + sniffer
- [ ] `COM-BE-013` delete/tombstone service
- [ ] `COM-BE-025`–`COM-BE-027` jobs (archival, request expiry, pending-asset cleanup)
- [ ] `COM-BE-015` REST catch-up endpoint wiring
- [ ] OpenAPI paths #1–#20 + WS contract documented in `applications/api/openapi/`
- [ ] Seed: Demo High School dataset (fictional, marked)
- [ ] Tests: `COM-UT-001`–`007`, `COM-IT-001`–`009` green in CI
