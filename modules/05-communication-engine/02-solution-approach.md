# Communication Engine — Solution Approach

**Module:** `05-communication-engine` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `chat_groups` | A conversation room: `kind ∈ official\|custom\|dm`. Official groups are bound to a section node (module 04); custom groups need School Admin approval; DMs are 1:1 (possibly cross-school after an accepted request) | Yes |
| `chat_group_members` | Membership with `role ∈ owner\|moderator\|member`, `joined_at`, `last_read_message_id` (drives read receipts) | Yes |
| `chat_messages` | Messages: `kind ∈ text\|image\|pdf\|voice\|system`; `client_msg_id` for idempotency/optimistic UI; `reply_to`; `deleted_at` soft delete (tombstone) | Yes |
| `message_requests` | Out-of-network DM gate: `from`/`to`, `status ∈ pending\|accepted\|declined\|expired` | Yes |
| `notices` | One-way board: `scope ∈ school\|section`, author role School Admin/Teacher, `pinned`, optional attachment (`media_assets`), `published_at`, soft delete | Yes |
| `media_assets` | R2 objects: `kind`, sniffed `mime`, `size`, `status ∈ pending\|confirmed\|archived`, owner, tenant, `r2_key` | Yes |
| User (verified) | Identity + verification status + role claims | No — module 03 |
| Hierarchy nodes (city/school/section) | Tenancy and official-group binding; FCM topic source | No — module 04 |
| Push fan-out | `BroadcastTopic` for notice pushes and new-message push on DMs | No — module 06 |

### 1.2 Relationships

```text
school (04) 1───* chat_groups (tenant_id)          section (04) 1───1 chat_groups[official]
chat_groups 1───* chat_group_members *───1 user (03)
chat_groups 1───* chat_messages *───0..1 media_assets
user (03) 1───* message_requests (from/to) ──accepted──▶ chat_groups[dm] (school_id NULL)
school (04) 1───* notices *───0..1 media_assets          (scope=section adds section_id)
media_assets *───1 owner user (03); tenant_id = owner's school
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-1 | A message exists only inside a group the author is a member of; every read/write query filters on membership + tenant | Service guard + repository WHERE clauses |
| INV-2 | `kind=official ⇒ section_id NOT NULL ∧ school_id NOT NULL`; `kind=custom ⇒ school_id NOT NULL`; `kind=dm ⇒ school_id NULL ∧ exactly 2 members` | DB CHECK constraints + service |
| INV-3 | `(sender_id, client_msg_id)` is unique — replays return the original row (idempotent optimistic UI) | Unique index + `INSERT … ON CONFLICT RETURN` |
| INV-4 | DM rooms exist only same-school, or after a `message_requests` row is `accepted` (request then links to the created room) | Service state machine |
| INV-5 | Notices are immutable except `pinned` flip and soft delete; only School Admin writes `scope=school`, only the section's Teacher writes `scope=section` | Service role guards (no edit endpoint) |
| INV-6 | A `media_assets` row must be `confirmed` (magic-byte-sniffed) before any message references it; mismatched sniff → `VALIDATION_FAILED` | `media.ConfirmUpload` |
| INV-7 | Deleting a message only sets `deleted_at` (tombstone); rows are never removed (audit + sync) | Repository (UPDATE only) |
| INV-8 | `dm:{minUserId}:{maxUserId}` room naming and the unique `(min_user_id, max_user_id)` pair prevent duplicate DM rooms | DB unique index + naming fn |

## 2. Module Boundary

**Owns (writes):** `chat_groups`, `chat_group_members`, `chat_messages`, `message_requests`,
`notices`, `media_assets` — and the R2 upload service (`media.PresignUpload`/`ConfirmUpload`)
that modules 08 (notes), 11 (product images) and 12 (receipts) reuse.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | Verification status + role claims (verified gate) | Verification is identity's source of truth (`prd.md` §5.1) |
| 04 | `hierarchy.ResolveUserNodes(userId)`, section/school node lookups | Hierarchy is the data model; official groups bind to its nodes |
| 06 | `notifications.BroadcastTopic` | FCM topic fan-out is module 06's job |
| 01 | Job runner, rate limiter, Redis client, error envelope | Foundations own the plumbing |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4
(`notices:school:{id}`, `notices:section:{id}`, chat read-through keys).

## 3. Lifecycle

Message — client-perceived vs server states:

```text
CLIENT:  SENDING ──ack──▶ SENT ──peer device online──▶ DELIVERED ──peer last_read ≥ msg──▶ SEEN
              │                            (delivered is derived, not stored)
SERVER:  (text)   INSERT confirmed ──▶ visible ──delete──▶ TOMBSTONED
         (media)  asset pending ──confirm(sniff)──▶ confirmed ──90d job──▶ archived
```

Other state machines:

```text
chat_groups[custom]: pending_approval ──School Admin approves──▶ active ──year-end/archive──▶ archived
message_requests:    pending ──▶ accepted (creates dm room) │ declined │ expired (7d job)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| SENDING (client) | server insert + ack | SENT | member + verified + rate limit | WS `message.ack` to sender; `message.new` fan-out to room via Redis pub/sub |
| asset pending | `ConfirmUpload` (sniff OK) | asset confirmed | owner + TTL ≤ 15 min + mime/kind match | message becomes sendable |
| message visible | delete (author ≤ 15 min / mod anytime) | TOMBSTONED | role + time window | WS `message.deleted`; clients swap tombstone |
| request pending | recipient accept | accepted | recipient only, not expired | DM room created; WS + push to both |
| request pending | 7-day expiry job | expired | job | sender sees expired state |
| notice draft (implicit) | `PostNotice` publish | published | role/scope guard | tag revalidate `notices:*`; `BroadcastTopic` push |
| media confirmed | 90-day archival job | archived | job, idempotent | object → `archive/` prefix; rehydrate on demand |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| App chat lists | TanStack Query infinite lists (50/page, cursor `before`) + WS `message.new` appends / invalidation | SQLite-less memory cache; last page per group cached offline | `chat:messages:group:{id}:{cursor}` (memory) |
| App notices tab | TanStack Query list + detail; WS `notice.new` invalidates | Stale-while-revalidate; pinned-first ordering done server-side | `notices:school:{id}` · `notices:section:{id}` |
| Server notice lists | Cacheable per school/section (they change rarely, read often) | Redis, TTL 60 s, bust on publish/pin/delete | `notices:school:{id}` |
| Server group/message queries | Never page-cached (per-user membership); only presence/typing in Redis with TTL | Redis presence key TTL 60 s | `presence:user:{userId}` |
| Media delivery | Presigned R2 GET URLs (15 min), generated per request — api never proxies bytes | n/a (R2 edge) | n/a |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Media caps per kind (image 10 MB / PDF 20 MB / voice 5 min) — defaults per Open Question 4 | gorilla/websocket + Redis pub/sub architecture |
| Presigned URL TTL (default 15 min) | Magic-byte sniffing on confirm (security invariant) |
| Media archival age (default 90 days) | `client_msg_id` idempotency; tombstone-only deletes |
| Message Request expiry (default 7 days) | One-way notices; role→scope publish matrix |
| Messaging rate-limit class thresholds | Room naming scheme (`school:`/`section:`/`group:`/`dm:`); presence TTL 60 s |
| Custom-group approval toggle per school (default ON — `TODO: Confirm`) | History page size 50 |

## 6. Security

Entry points: 20 REST endpoints under `/api/v1/chat|notices|media` + one WS gateway
(`/api/v1/ws`). Every entry runs **authenticate → load role claims → tenant-scope**; the WS
handshake validates the same JWT and resolves subscribable rooms server-side (a client can never
subscribe to a room it has no membership for — the server resolves room sets from hierarchy +
memberships, never from client requests beyond referencing an allowed room id).

| Surface | Auth | Tenant-scope rule |
| --- | --- | --- |
| `chat_groups` (official/custom) | Verified + member to read; owner/mod/School Admin to mutate members | `school_id = caller.tenantId` on every query |
| `chat_groups` (dm) | Verified + the 2 members only | Authorized by membership, not tenant (cross-school by design); queries filter `min_user/max_user` |
| `chat_messages` | Verified member of the message's group | `group_id ∈ caller's memberships ∧ tenant match` |
| `message_requests` | From/to users only | Row-level: `from_user_id = caller ∨ to_user_id = caller` |
| `notices` | Read: tenant member; write: role→scope matrix (INV-5) | `school_id = caller.tenantId`; section scope additionally `section ∈ caller's sections` |
| `media_assets` | Presign/confirm: owner only (verified); download: members of a group/notice referencing the asset | `tenant_id = caller.tenantId` (dm media: via referencing message's membership) |

Sanitisation: message/notice bodies are plain text (no markdown rendering at MVP) — stored
as-is, rendered as text; attachment names length-capped and extension-inspected before display.
Rate limits: class `messaging` on sends/reads-paginated; stricter bucket on
`POST /chat/message-requests` (anti-spam, BR-013). Upload hardening lives in
`media.ConfirmUpload` (magic bytes, size re-check, kind/mime allowlist). Privacy: no message
content in logs; push payloads carry titles/ids only; guardians/minors are reachable only inside
their school scope or after an accepted request (`brd.md` §6).

## 7. Accessibility & Motion

Chat is a high-frequency surface, so motion is limited to purposeful feedback: bubble
send-state morphs (clock → check → seen), typing dots, tombstone fade-in — all with instant
static variants under reduced motion (details + 360px layouts in `05-app-tasks.md` §5).
Screen reader: each bubble is one semantic unit ("message from <name>, <time>, <state>");
date separators are headings; the composer is labelled in bn + en; voice notes expose
play/pause with accessible duration. Keyboard behaviour is an app concern (mobile), covered in
`05` §7.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | WS connection drops (network switch, gateway restart) | Client ping/pong timeout | Live updates pause; sends may hang in SENDING | Client reconnects with exponential backoff (≤ 30 s cap), re-subscribes rooms, catch-up via REST cursor; REST fallback send; optimistic dedupe by `client_msg_id` |
| 2 | Redis down (pub/sub + presence) | Client errors on publish | Single-instance delivery only: members on the same gateway instance still receive messages; presence/typing stop | Messages persist to Postgres first (source of truth), so catch-up on reconnect heals missed fan-out; alert + restart Redis |
| 3 | R2 down / presign fails | 5xx from R2/confirm | Media upload blocked | Text chat unaffected; client queues media sends with retry; user sees "upload failed — will retry" |
| 4 | Archival job failure mid-batch | Job error + alert | Media stays hot past 90 days (cost, not data) | Job is idempotent/status-checked; retries next run — never data loss |
| 5 | FCM down (via module 06) | BroadcastTopic error | No push for a notice | In-app Notices tab + WS `notice.new` still deliver; 06 retries its own queue |
| 6 | WS gateway instance crash | Health check + client disconnects | Connected clients drop | Clients reconnect to surviving instance; Redis pub/sub means no room affinity is lost; zero message loss (Postgres persisted) |
| 7 | Duplicate send replay after ack loss | Unique index hit | None | Return original row (BR-008) |

## 9. Performance

- Volumes (pilot): 3 schools × ~2,000 users; peak ~10% concurrent WS (~600 conns/instance);
  ~50 msg/s peak fan-out. Single 2 vCPU VPS instance handles this; Redis pub/sub makes a second
  instance additive.
- Hot query: history pagination — `chat_messages (group_id, created_at DESC, id DESC)` index;
  p95 ≤ 150 ms server-side for a 50-row page on Neon.
- Send→render p95: ≤ 800 ms on 4G, ≤ 2.5 s on 3G (optimistic render is local ≈ instant; the
  budget applies to the confirmed state) — measured in `COM-IT` perf smoke + Maestro timings.
- Presence: Redis key per user, TTL 60 s, refreshed by heartbeat — no DB writes.
- Fan-out: one Redis publish per message; receivers get at most one event per room subscription —
  O(members) WS writes, no N+1 queries.
- App bundle impact: no new heavy deps (plain WebSocket client per `tech-stack.md`); compression
  uses `expo-image-manipulator` + `expo-av` (already in the Expo SDK).

## 10. Alternatives Considered

### Option A — gorilla/websocket + Redis pub/sub · Option B — Socket.IO / Centrifugo

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Plain WS the RN client speaks natively; rooms map 1:1 to the hierarchy; tiny surface area; already the resolved stack (`tech-stack.md`) | Batteries-included rooms/reconnect; Centrifugo has presence/history built-in |
| Disadvantages | We implement ack/reconnect/resubscribe ourselves (documented here) | Extra protocol layer/JS client polyfill on RN; Socket.IO's custom framing fights plain-WS infra (Nginx, health checks); another moving service if Centrifugo |
| Complexity / weight | Low–medium | Medium–high |

**Recommendation:** A — rejected B per `tech-stack.md` ("Socket.IO … less machinery"). ADR: note
in this module's `07-progress.md`.

### Option A — Redis pub/sub fan-out · Option B — Postgres-only fan-out (polling/NOTIFY)

| | A (chosen) | B |
| --- | --- | --- |
| Advantages | Sub-ms cross-instance fan-out; presence TTLs for free; Redis already required for cache/limits | One less moving part; LISTEN/NOTIFY is built into Postgres |
| Disadvantages | Redis is a dependency (degraded-mode documented in §8.2) | NOTIFY has no at-least-once guarantee under reconnects → missed events; polling history per client is wasteful at scale |
| Complexity / weight | Low (go-redis already in stack) | Low code, high operational surprise |

**Recommendation:** A; Postgres remains the source of truth so a Redis outage degrades to
single-instance delivery, never data loss.

### Rejected: client-side end-to-end encryption for chat

| | E2E (rejected) | Server-side TLS-only (chosen) |
| --- | --- | --- |
| Advantages | Strongest privacy vs platform insiders | Simple; enables school oversight + module 09 aggregates |
| Disadvantages | **Breaks the product's core promise:** schools must be able to moderate (BR-013 safety, tombstones, notice oversight); key recovery/backup across device loss is unsolved for this user base; module 09 analytics becomes impossible | Messages readable by the platform (mitigated by tenant isolation + access audits) |

**Recommendation:** Reject E2E — the B2B buyer (the school) requires oversight, and
`brd.md` §6 frames privacy as tenant isolation + Message Requests, not crypto. Recorded as a
rejected alternative with reason here and in `07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Pilot scale fits one VPS instance (≤ ~1k concurrent WS) | Latency/degradation at growth | Redis pub/sub + stateless gateway = horizontal add; load test before 10-school push |
| 2 | Neon free tier absorbs chat write volume | Cold starts/connection limits bite | Messages batch via pgx pool; upgrade path documented (`tech-stack.md`) |
| 3 | Clients honour `client_msg_id` contract; old/rogue clients can't duplicate | Duplicated UX noise | Server-side unique index is the backstop (INV-3) |
| 4 | R2 magic-byte sniffing covers our kinds (JPEG/PNG/HEIC→image, PDF, AAC/m4a) | Exotic uploads rejected | Strict allowlist; expand deliberately with tests |
| 5 | 90-day archive + rehydrate meets school expectations | A principal expects instant year-old photos | Rehydrate is seconds, not days; Open Question 1 records the default |
| 6 | Voice ≤ 5 min covers real classroom use | Teachers want longer lectures → they share PDFs/links | Cap is config (`05` §5), raise deliberately |
