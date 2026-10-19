# Communication Engine — Integration Tasks

**Module:** `05-communication-engine` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `04-organization-hierarchy` | they call us | exported Go service fn `chat.JoinSectionGroups` (on verification / section creation) | degraded — group join retried via job; verification itself never blocked |
| I-2 | `06-notifications` | we call them | exported fn `notify.BroadcastTopic(topic, payload)` | degraded, never fatal — notices still in-app + WS |
| I-3 | `08-ai-study-hub` / `10-tuition-marketplace` | they call us | `media.PresignUpload` / `media.ConfirmUpload` | fatal to *their* media features only; text chat unaffected |
| I-4 | `09-teacher-analytics` | they call us | `chat.GroupMembers(groupID)` — aggregates only | degraded — analytics sampling skips |
| I-5 | `07-command-center-web` | they call us | REST endpoints #15–#20 (notices) + #3/#4/#6 (club approval) via generated client | degraded — composer shows API error |
| I-6 | api → app realtime | we notify | WS events (`message.*`, `notice.new`, `presence.update`, `typing`) over `room:{id}` Redis channels | degraded — catch-up via REST cursor |
| I-7 | `04` | we call them | `hierarchy.ResolveUserNodes(userId)` (room resolution, notice scoping) | fatal to WS room resolution (disconnect); REST reads 503-free via cached memberships |
| I-8 | `03` | we call them | verification/role claims (JWT middleware chain) | fatal to any write (by design — `NOT_VERIFIED`) |
| I-9 | Cloudflare R2 (external) | outbound | S3 API — presigned PUT (15 min TTL), object copy (archive/rehydrate), HEAD on confirm | degraded — media blocked, text chat unaffected |
| I-10 | Redis (external) | outbound | pub/sub `room:{id}` channels + presence keys (TTL 60 s) + rate limits | degraded — single-instance delivery, no presence/typing |
| I-11 | `01-foundations` | they host us | job runner registration (`jobs.Runner.Register`), error envelope, rate-limiter base | degraded — jobs delayed; limits fall back to safe defaults |
| I-12 | module 15 (ops) | we document | WS proxy requirements (Upgrade headers, 300 s read timeout) for the Nginx/HestiaCP templates | misconfig = broken upgrades; runbook item |

## 2. Exported Contract

```text
chat.JoinSectionGroups(userID uuid, enrollment EnrollmentDTO) error
chat.PostNotice(ctx, actor ActorClaims, in NoticeInput) (NoticeDTO, error)
media.PresignUpload(ctx, owner ActorClaims, in PresignInput) (PresignResult, error)
media.ConfirmUpload(ctx, owner ActorClaims, assetID uuid, in ConfirmInput) (MediaAssetDTO, error)
chat.GroupMembers(groupID uuid) ([]MemberDTO, error)
chat.ArchiveSectionGroups(ctx, schoolID uuid, sessionYear int) (archived int, err error)
chat.NoticeStats(ctx, schoolID uuid) (NoticeStatsDTO{PublishedLast30d, Pinned, LastPublishedAt}, error)
chat.SectionQuestionSamples(ctx, sectionID uuid, from, to time.Time, limit int) ([]ChatSample{Text, CreatedAt}, error)
media.PutObject(ctx, in PutInput{Bytes, Kind, SchoolID, OwnerID}) (MediaAssetDTO, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `chat.JoinSectionGroups(userID, enrollment)` | 04 (on verification, BR-01) | `error` | domain errors wrapped; caller logs | Idempotent — re-invocation no-ops if membership exists; creates official group per section, teacher→moderator |
| `chat.PostNotice(actor, NoticeInput)` | 07 (School Admin composer) | `NoticeDTO` | `FORBIDDEN`, `VALIDATION_FAILED`, `NOT_VERIFIED` | Same guard matrix as REST #16; busts tags + triggers I-2 push |
| `media.PresignUpload(owner, PresignInput)` | 08 notes · 11 product images · 12 receipts | `PresignResult{assetID, uploadURL, expiresAt}` | `VALIDATION_FAILED` (kind/size) | 15-min TTL; asset starts `pending` |
| `media.ConfirmUpload(owner, assetID, ConfirmInput)` | 08 · 11 · 12 | `MediaAssetDTO` (sniffed mime, status) | `VALIDATION_FAILED` (magic-byte mismatch, expired, non-owner) | The security boundary — sniffing is server-side only |
| `chat.GroupMembers(groupID)` | 09 (analytics sampling) | `[]MemberDTO{userID, role, sectionID}` | `NOT_FOUND` | **Aggregates only** — never message bodies; callers must not persist member lists |
| `chat.ArchiveSectionGroups(schoolID, sessionYear)` | 04 year-end migration | count archived | domain errors | Idempotent; archived groups become read-only (composer disabled, `CONFLICT` on send) |
| `chat.NoticeStats(schoolID)` | 07 School Admin dashboard | notice counts | `TENANT_MISMATCH` | Aggregate only |
| `chat.SectionQuestionSamples(sectionID, from, to, limit)` | 09 Pain Point Matrix (P1 chat source) | ≤ `limit` (max 200) text messages from the section's **official** group in the window | `FORBIDDEN` (non-tenant), `VALIDATION_FAILED` | Text kind only, deleted excluded; **no author ids, names or group ids**; phone numbers/emails/URLs masked server-side before return; caller must not persist samples — only 08-classified topic tags. `TODO: Confirm` (Rahul) whether schools must opt in before chat text reaches the AI provider |
| `media.PutObject(in)` | 12 receipt PDFs (server-generated files) | `MediaAssetDTO` (status `confirmed`) | `VALIDATION_FAILED` (kind/size) | Server-side put for api-generated files; kind allowlist extended with `receipt_pdf`; same R2 bucket/key scheme and archival rules as client uploads |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `hierarchy.ResolveUserNodes(userID)` — school/section membership for room resolution + notice scoping | 04 | WS: disconnect client (cannot resolve rooms safely); REST: refuse with `INTERNAL` + alert — never guess scope |
| `notify.BroadcastTopic(topic, payload)` — topics `school-{id}` / `section-{id}` on notice publish; `school-{id}` on accepted request (via 06) | 06 | Log + continue; in-app/WS delivery unaffected; 06 owns retry |
| `notify.SendToUser(userID, payload)` — directed @mention pushes (owner 2026-10-18): type `chat_mention`, class `chat` (NTF-BR-004 mute respected), deep link `/groups/{groupId}`, ids only (NTF-BR-003). Bound through 05's `MentionPusher` port; adapter in `cmd/api` | 06 | Degraded, never fatal — adapter logs; in-app/WS delivery unaffected |
| `jobs.Runner.Register(name, schedule, fn)` — archival, request-expiry, asset-cleanup jobs | 01 | Job misses logged; runner alarms; jobs are idempotent so late runs are safe |
| Verified/role claims middleware (`authenticate → load role claims → tenant-scope`) | 03 | Writes refused with `NOT_VERIFIED`/`FORBIDDEN` — the gate is the feature |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Notice publish / pin / delete | `notices:school:{schoolId}` · `notices:section:{sectionId}` |
| Custom-group approval (status → active) | `chat:groups:user:{userId}` for affected members (app-side query invalidation via WS `group.updated`) |
| Message send/read/delete | none (never page-cached; per-user membership queries) |
| Media confirm/archive | `media:asset:{id}` (short-lived presign memo) |

| Read | Tagged with |
| --- | --- |
| `GET /notices?scope=` (server, Redis, TTL 60 s) | `notices:school:{id}` + `notices:section:{id}` per requested scope |
| App notices query | subscribes to the same tags through the generated client's revalidation headers (07 shares them) |
| App chat history query | `chat:messages:group:{id}:{cursor}` — memory-only, never server-tagged |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Cloudflare R2 | S3 REST (presigned PUT/GET, CopyObject, HeadObject) | `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` (envconfig-parsed) | 5 s control ops | 3× exp backoff (api-side control ops only; client does the PUT) | Media upload/view blocked; text + notices unaffected; queued client retries |
| Redis | RESP (go-redis) pub/sub + keys | `REDIS_URL` | 2 s ops, 500 ms publish | 1× immediate then drop (next event heals) | Single-instance WS delivery; presence/typing/rate-limits off → fail-closed limits to defaults |
| FCM (via module 06 only) | HTTPS Admin SDK | 06's `FCM_SERVER_KEY` | 06-owned | 06-owned | No push; WS + in-app still deliver |
| Nginx (HestiaCP) | WS reverse proxy | TLS termination | — | — | Upgrade headers + 300 s read timeout configured in module 15 runbook |
| expo-notifications (app-side) | native push receipt | 06-owned config | — | — | Topic join/leave failures retried by 06; chat works without push |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Chat tab list | `GET /chat/groups` + WS rooms | Unread = server-computed counts; WS `message.new` patches rows |
| Group screen | WS `message.send`/`message.read`/`typing`; REST #2 history + #12 fallback + #14 read | Temp bubble keyed by `client_msg_id`; ack echo swaps id |
| Attach sheet | `POST /media/upload-url` → PUT R2 → `POST /media/{id}/confirm` → send message | Confirm returns sniffed mime; UI blocks send until `confirmed` |
| Voice recorder | same media flow, `kind=voice`, `durationMs` | Cap 5 min enforced client + server |
| Requests inbox | `POST/GET /chat/message-requests`, `…/accept\|/decline` | Accept response carries `dmGroupId` → navigate |
| Notices tab/detail | `GET /notices?scope=` | Pinned-first server ordering; `notice.new` WS invalidates |
| Notice push tap (06 payload) | deep link `/notices/[id]` | Payload carries ids + title only (privacy) |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. WS event payloads mirror the OpenAPI
message/notice DTOs (documented table in `03` §2) so app parsers are generated from the same
types; new WS event types are additive (unknown events ignored by clients). `client_msg_id`
semantics and `message.ack` echo are frozen — the optimistic UI contract of every future client
depends on them.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| R2 down | Text chat, notices (no attachment), requests, history of text | Media attach fails: "আপলোড ব্যর্থ — আবার চেষ্টা হবে / Upload failed — will retry"; archived attachment shows recovering state | Client queues media sends; presign retry; no data loss (messages without assets send normally) |
| Redis down | Message persistence (Postgres-first), REST history, sends | Live updates only from same-instance members; no typing/presence; stale unread counts | Chat degrades to single-instance delivery; reconnect catch-up heals missed events; alarm + Redis restart |
| FCM down (via 06) | WS + in-app delivery, notices tab | No push notification | 06's retry queue delivers on restore; badge counts correct on next app open |
| WS gateway instance crash | REST history/sends (fallback), other instance(s) via Redis | Socket closes → app banner → auto-reconnect (backoff) → rooms re-subscribe → catch-up | Clients land on surviving instance; zero message loss (Postgres source of truth) |
| Neon (Postgres) degraded | Nothing chat-side (by design — Postgres is the source of truth) | Errors on send/read | 01/15 runbooks: connection-pool alarm, Neon failover/upgrade path |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `COM-UT-010` | Redis publish failure → send still persists + ack; degraded flag set | Unit | Postgres-first invariant (02 §8.2) |
| `COM-UT-011` | Room-resolution denies unsubscribed room ids | Unit | WS security |
| `COM-IT-001` | Cross-tenant group access denied (`TENANT_MISMATCH`/404, no leak) | Integration | BR-012 |
| `COM-IT-002` | Unverified user cannot post (`NOT_VERIFIED` everywhere) | Integration | BR-001 |
| `COM-IT-003` | `client_msg_id` replay (REST + WS) → no duplicates, same id | Integration | BR-008 |
| `COM-IT-004` | Message-request flow: out-of-network blocked → accept opens room → decline blocks politely | Integration | BR-004 / US-009 |
| `COM-IT-005` | Magic-byte confirm rejects exe-renamed `.jpg`; valid flow end-to-end | Integration | INV-6 |
| `COM-IT-006` | Notice read access scoped to school/section; other tenant sees nothing | Integration | BR-012 / INV-5 |
| `COM-IT-007` | 90-day archival job: move + flag + rehydrate + idempotent re-run | Integration | BR-011 |
| `COM-IT-010` | Notice publish calls `BroadcastTopic` with correct topic (`section-{id}` vs `school-{id}`) — 06 stubbed | Integration | I-2 contract |
| `COM-IT-011` | `JoinSectionGroups` idempotent under 04's re-verification replay | Integration | I-1 contract |
| `COM-E2E-001` | Maestro: send message online — bubble SENDING → SEEN on second device | Maestro (app) | US-002/006 golden path |
| `COM-E2E-002` | Maestro: airplane-mode send → banner → reconnect → replayed exactly once (no dup) | Maestro (app) | US-015 / offline reconcile |
| `COM-E2E-003` | Maestro: notice published (07 API) → push received → deep link lands on `/notices/[id]` | Maestro (app) | US-010/012 + I-2 seam |

## 10. Task Checklist

- [x] `COM-INT-001` Implement + export `chat.JoinSectionGroups` (idempotent) and wire 04's call point — 2026-10-15
- [x] `COM-INT-002` Implement + export `chat.PostNotice` incl. tag busts + `BroadcastTopic` call — 2026-10-15
- [x] `COM-INT-003` Implement + export `media.PresignUpload` / `media.ConfirmUpload` (shared sniffer) — 2026-10-15
- [x] `COM-INT-004` Implement + export `chat.GroupMembers` (aggregate DTOs only) for 09 — 2026-10-15
- [x] `COM-INT-005` Consume `hierarchy.ResolveUserNodes` in WS room resolution + notice scoping — 2026-10-15
- [x] `COM-INT-006` Register jobs (archival / request-expiry / asset-cleanup) with 01 runner — 2026-10-15
- [x] `COM-INT-007` Redis pub/sub channels `room:{id}` + presence keys (TTL 60 s) + messaging rate-limit class — 2026-10-15
- [x] `COM-INT-008` R2 client: presign PUT/GET, CopyObject archive/rehydrate, env-parsed secrets — 2026-10-15
- [x] `COM-INT-009` Cache-tag contract live (`notices:school:{id}` / `notices:section:{id}`) + 07 handoff verified (`COM-FE-001`) — 2026-10-15
- [x] `COM-INT-010` WS reconnect contract documented + tested (backoff, re-subscribe, REST catch-up) — 2026-10-15
- [x] `COM-INT-011` Failure-matrix drills scripted (Redis down, R2 down, gateway kill) in CI smoke — 2026-10-15
- [ ] `COM-INT-012` Tests `COM-IT-001`–`011` + `COM-E2E-001`–`003` green in CI
- [x] `COM-INT-013` Implement + export `ArchiveSectionGroups` (04), `NoticeStats` (07), `SectionQuestionSamples` with PII masking + no-author guarantee (09), `media.PutObject` + `receipt_pdf` kind (12); contract tests per export — 2026-10-15
- [x] `COM-INT-014` Mentions + stars integration surface (owner 2026-10-18): `SendToUser` consumed-contract row above, OpenAPI #23–#25 + `mentions` on send/DTO, both clients regenerated (`sync:api-spec` + `generate:api` in web and app) — 2026-10-18
