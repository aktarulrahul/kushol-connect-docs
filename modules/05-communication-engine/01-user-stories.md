# Communication Engine — User Stories

**Module:** `05-communication-engine`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Provides the real-time communication core of Kushol Connect: hierarchy-driven group chat (official section groups, custom "club" groups, DMs) over the Go WebSocket gateway, one-way notice boards (school and section scope), Message Requests for out-of-network DMs, and media messaging (image/PDF/voice) via Cloudflare R2 — all optimistic, offline-tolerant and bilingual. Serves `brd.md` §2 Goal 1 (replace chaotic WhatsApp groups with an organised, hierarchy-based platform) and BR-01, and is the Phase-1 exit criterion in `docs/modules/README.md` ("verified student auto-joins section group, receives a notice by push").

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Can open Chat/Notices tabs but sees the NOT_VERIFIED gate; cannot read or post (`prd.md` §5.1) |
| Student | Reads/posts in their section group and approved clubs; DMs (same-school instantly, out-of-network via Message Request); reads notices; sends media |
| Guardian | Same chat capabilities as Student for their own memberships; primary consumer of school notices |
| Teacher | Everything a Student does; is **moderator** of their section's official group; publishes **section notices** |
| School Admin | Governs only their own school (tenant); publishes **school notices** (one-way board); approves custom club groups; moderates any tenant group |
| Super Admin | No direct chat surface in this module; platform-level oversight only (module 07/13 tooling) |
| Vendor / EdTech brand | N/A — vendors never participate in chat or notices; they reach students only via module 13 campaigns |
| System (jobs, webhooks) | Media archival job (90 days), message-request expiry job, WS presence TTLs, Redis pub/sub fan-out |

## 3. Scope

**In scope**

- Group chat across three kinds: `official` (bound to a section node from module 04), `custom` (clubs, School-Admin-approved), `dm` (1:1, incl. cross-school after an accepted request).
- Go WebSocket gateway (gorilla rooms + Redis pub/sub), presence, typing, read receipts.
- Text/image/PDF/voice messages with optimistic UI, `client_msg_id` idempotency, offline queue, tombstone deletes.
- Message Requests: pending → accepted/declined/expired, gating out-of-network DMs.
- One-way notice boards (school + section) with pin, soft delete, one attachment.
- R2 upload service owned here and reused by 08/11/12: `media.PresignUpload`/`ConfirmUpload` with server-side magic-byte sniffing; 90-day media archival job.

**Out of scope** (explicit — prevents scope drift)

- Push delivery itself (FCM topics, deep links) — module 06; this module only calls `notify.BroadcastTopic` when a notice is published.
- City-wide campaigns/events shown alongside notices — module 13 (arrive via 06 push, not the `notices` table — seam documented in COM-US-012).
- The School Admin web notice composer UI — module 07 (this module ships the APIs it calls).
- Live video/voice calls — `brd.md` §4 out of scope.
- Client-side end-to-end encryption — rejected alternative (`02-solution-approach.md` §10).
- AI features over chat content — module 09 consumes via `chat.GroupMembers` aggregates only.

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | OpenAPI codegen pipeline, error envelope, job-runner base, test harness |
| 02 design-system | bn/en catalogs (`chat.*`, `notices.*`, `validation.*`), tokens, RN primitives |
| 03 identity-access | Verified-user gate (`NOT_VERIFIED`), JWT auth chain, five roles |
| 04 organization-hierarchy | Section/school nodes, enrollments, `ResolveUserNodes`, auto-group hook point |

---

## 4. User Stories

### `COM-US-001` — Verified student lands in their section group with history

**Priority:** P0 · **Traces:** BR-01 (`brd.md` §5) / PRD §5.1 · **Depends on:** 04

**Story** — As a **verified student**, I want **to be placed automatically in my class (section) group**, so that **I can read my class's conversation the moment I open Chat**.

**Acceptance criteria**

- **Given** my enrollment was verified (module 03/04), **when** I open Chat → Official, **then** my section's official group is listed with me as `member` and the class Teacher as `moderator`.
- **Given** the group has history, **when** I open it, **then** the latest 50 messages load and older pages load on scroll (cursor `before`, 50/page) with Bengali date separators.
- **Given** my membership is revoked, **when** I try to read or post, **then** I get `FORBIDDEN` and the group disappears from my list.

**Notes** — group creation is module 04's job via the `chat.JoinSectionGroups` export (`06` §2).

### `COM-US-002` — Send a text message with optimistic UI

**Priority:** P0 · **Traces:** PRD §5.1 · **Depends on:** COM-US-001

**Story** — As a **group member**, I want **my message to appear instantly and settle into confirmed state**, so that **chat feels instant even on 3G**.

**Acceptance criteria**

- **Given** I am a verified member and online, **when** I send text, **then** the bubble renders immediately in SENDING state (clock) with a locally generated `client_msg_id`.
- **Given** the server accepted it, **when** `message.ack` echoes my `client_msg_id` with the real id, **then** the bubble switches to SENT (✓) without duplicating or reordering.
- **Given** the send fails, **when** the error returns, **then** the bubble shows retry and my input text is never lost.

### `COM-US-003` — Send an image message

**Priority:** P0 · **Traces:** PRD §5.1 (images) · **Depends on:** COM-US-002

**Story** — As a **group member**, I want **to share photos compressed before upload**, so that **sending works on mobile data without blowing through my plan**.

**Acceptance criteria**

- **Given** I pick an image, **when** I send, **then** the client compresses to a ~1 MB target (≤ 10 MB cap), calls `POST /media/upload-url`, PUTs to R2 (TTL 15 min), then `POST /media/{id}/confirm`.
- **Given** confirm succeeds (magic-byte sniff = image), **when** the message sends, **then** the bubble shows a thumbnail and taps open the in-app viewer.
- **Given** an executable renamed `.jpg`, **when** confirm sniffs it, **then** it is rejected (`VALIDATION_FAILED`) and no message is created.

### `COM-US-004` — Record, send and play a voice note

**Priority:** P0 · **Traces:** PRD §5.1 (voice) · **Depends on:** COM-US-003

**Story** — As a **group member**, I want **to record a voice note and play others'**, so that **I can communicate naturally in Bangla without typing**.

**Acceptance criteria**

- **Given** I hold record, **when** I release ≤ 5 minutes, **then** the recording compresses client-side and sends through the media flow with `kind=voice`.
- **Given** a voice message, **when** I tap play, **then** it plays inline with duration/waveform and continues when the screen locks.
- **Given** a recording > 5 minutes, **when** I stop, **then** send is blocked with `validation.chat.voice_too_long` (bn + en).

### `COM-US-005` — Share a PDF

**Priority:** P0 · **Traces:** PRD §5.1 (PDF) · **Depends on:** COM-US-003

**Story** — As a **teacher or student**, I want **to share PDFs (question banks, syllabi)**, so that **materials circulate inside the school's own platform instead of WhatsApp**.

**Acceptance criteria**

- **Given** I attach a PDF ≤ 20 MB, **when** I send, **then** the bubble shows filename + size + PDF icon with the same optimistic states as text.
- **Given** a PDF message, **when** tapped, **then** it opens in the system viewer via a short-lived R2 download URL.
- **Given** a non-PDF sniff result, **when** confirm runs, **then** it is rejected (`VALIDATION_FAILED`).

### `COM-US-006` — Read receipts (seen states)

**Priority:** P1 · **Traces:** PRD §5.1 (`prompt.txt` §3) · **Depends on:** COM-US-002

**Story** — As a **message sender**, I want **to see whether my message was seen**, so that **I know my class or teacher received it**.

**Acceptance criteria**

- **Given** I view the latest messages, **when** the client reports read (WS `message.read` or `PATCH /chat/groups/{id}/read`), **then** my `last_read_message_id` updates and senders' seen counts increment live.
- **Given** my own message seen by all other members, **when** their `last_read_message_id` ≥ it, **then** the bubble shows the SEEN state (✓✓/accent).
- **Given** I read while offline, **when** connectivity returns, **then** the read report replays like a send.

### `COM-US-007` — Typing indicator

**Priority:** P2 · **Traces:** PRD §5.1 · **Depends on:** COM-US-002

**Story** — As a **group member**, I want **to see when someone is typing**, so that **chat feels alive and I wait before re-sending**.

**Acceptance criteria**

- **Given** a peer is typing, **when** their client emits `typing` (≤ 1 per 3 s), **then** I see "টাইপ করছেন… / typing…" within a second.
- **Given** no event for 4 s, **when** the TTL lapses, **then** the indicator clears (no stuck state).

### `COM-US-008` — DM a same-school member instantly

**Priority:** P0 · **Traces:** PRD §5.1 · **Depends on:** COM-US-001

**Story** — As a **verified user**, I want **to DM anyone verified in my own school instantly**, so that **in-school coordination is friction-free**.

**Acceptance criteria**

- **Given** both users are verified in the same school, **when** I call `GET /chat/dm/{peerId}`, **then** the DM room opens/creates immediately (`dm:{minUserId}:{maxUserId}`) with no request step.
- **Given** an existing DM room, **when** either side opens it again, **then** the same room is returned (no duplicates).

### `COM-US-009` — Message Request for out-of-network DMs

**Priority:** P0 · **Traces:** `brd.md` §6 (anti-spam) · **Depends on:** COM-US-008

**Story** — As a **verified user**, I want **out-of-school contact to require my explicit acceptance**, so that **no stranger can reach my child or me uninvited**.

**Acceptance criteria**

- **Given** the peer is verified at a different school, **when** I attempt a DM, **then** a Message Request is created (`pending`) and no room exists; the peer sees an inbox banner "আপনাকে একটি মেসেজ রিকোয়েস্ট পাঠিয়েছে / sent you a message request".
- **Given** a pending request, **when** the recipient accepts, **then** the DM room opens for both sides and the sender's state flips to accepted with the room id.
- **Given** the recipient declines, **when** the sender retries, **then** they are blocked with "রিকোয়েস্টটি গ্রহণ করা হয়নি। / Your request wasn't accepted." — no room, rate-limited retries.
- **Given** a pending request past the expiry window (default 7 days — OQ-3), **when** the expiry job runs, **then** status becomes `expired` and the thread stays closed.

### `COM-US-010` — School Admin publishes a school notice

**Priority:** P0 · **Traces:** PRD §5.1/§4B (one-way boards) · **Depends on:** 04

**Story** — As a **School Admin**, I want **to publish a one-way, pinnable notice to my whole school**, so that **official information reaches every member from a verified, branded source**.

**Acceptance criteria**

- **Given** I am School Admin of school S, **when** I publish via `POST /notices` (scope `school`, optional pin/attachment), **then** it appears on every member's Notices tab pinned-first with `published_at` and school branding.
- **Given** it is published, **when** `notify.BroadcastTopic` runs for `school-{schoolId}`, **then** members receive the push "নতুন নোটিশ প্রকাশিত হয়েছে / New notice published" (06 owns delivery).
- **Given** a student/guardian views the board, **when** they look for a reply box, **then** none exists — read-only for non-admin roles.

### `COM-US-011` — Teacher publishes a section notice

**Priority:** P0 · **Traces:** PRD §5.1 · **Depends on:** COM-US-010

**Story** — As a **class Teacher**, I want **to publish notices scoped to only my section**, so that **class-level instructions don't spam the whole school**.

**Acceptance criteria**

- **Given** I teach section N, **when** I publish with `scope=section`, `sectionId=N`, **then** only section N members see it; push fans out to `section-{sectionId}`.
- **Given** a teacher targets a section they don't teach, **when** the request lands, **then** it is refused with `FORBIDDEN`.

### `COM-US-012` — Student reads the Notices tab

**Priority:** P0 · **Traces:** PRD §4B · **Depends on:** COM-US-010

**Story** — As a **student or guardian**, I want **one reliable place for all school notices**, so that **I never miss exam dates or fee deadlines buried in group chat**.

**Acceptance criteria**

- **Given** I open the Notices tab, **when** the list loads, **then** pinned notices appear first, then reverse-chronological; school + my sections' notices all appear with title, date, author, attachment indicator.
- **Given** a notice has an attachment, **when** I open the detail, **then** the viewer opens from a short-lived R2 URL.
- **Given** city-wide campaigns (module 13), **when** they arrive, **then** they reach me via 06 push and render as a **separate section fed by 13's API** — never rows in this module's `notices` table (documented seam).

### `COM-US-013` — Custom club group request → approval → live

**Priority:** P1 · **Traces:** PRD §4B (clubs) · **Depends on:** COM-US-001

**Story** — As a **verified student**, I want **to request a club group a School Admin approves**, so that **student-led groups stay under school oversight**.

**Acceptance criteria**

- **Given** I am a verified user of school S, **when** I create a club via `POST /chat/groups`, **then** it is `pending_approval`, visible only to the approval queue.
- **Given** the School Admin approves, **when** activation lands, **then** the group is `active`, I become its `owner`, and members within school S can join/post.
- **Given** the School Admin rejects, **when** I view my request, **then** it shows declined with the note; no group is live.

**Notes** — approval-before-activation is the default; `TODO: Confirm` (OQ-2).

### `COM-US-014` — Delete a message (tombstone)

**Priority:** P1 · **Traces:** `brd.md` §6 (safety) · **Depends on:** COM-US-002

**Story** — As a **message author (or moderator)**, I want **to delete a message — authors within 15 minutes, moderators anytime**, so that **mistakes and inappropriate content are retracted**.

**Acceptance criteria**

- **Given** I authored a message < 15 min ago, **when** I delete it, **then** it soft-deletes and every client swaps it for "মেসেজ মুছে ফেলা হয়েছে / Message deleted" via WS event.
- **Given** I am moderator/owner (or School Admin of the tenant), **when** I delete any message, **then** the same tombstone applies; a plain member deleting another's gets `FORBIDDEN`.
- **Given** a deleted media message, **when** the tombstone renders, **then** the media is unlinked from display (object follows the normal 90-day rule; no hard delete).

### `COM-US-015` — Offline send queue replays on reconnect

**Priority:** P0 · **Traces:** `prompt.txt` §3 · **Depends on:** COM-US-002

**Story** — As a **user on an unstable network**, I want **offline sends queued and delivered automatically**, so that **nothing I write is ever silently lost**.

**Acceptance criteria**

- **Given** the device is offline, **when** I send, **then** the message enters the local queue with its `client_msg_id` and a banner "অফলাইন — ইন্টারনেট চালু হলে পাঠানো হবে / Offline — will send when online".
- **Given** connectivity returns, **when** the socket reconnects (backoff), **then** queued sends replay in order, rooms re-subscribe, and catch-up runs from my REST cursor.
- **Given** a replayed send the server already accepted, **when** the same `client_msg_id` arrives twice, **then** the server returns the original message — no duplicate for anyone.

### `COM-US-016` — Media archival after 90 days

**Priority:** P1 · **Traces:** `02` retention default · **Depends on:** COM-US-003

**Story** — As the **platform operator**, I want **media older than 90 days moved off hot storage automatically**, so that **R2 costs stay predictable without losing any attachment**.

**Acceptance criteria**

- **Given** confirmed media older than 90 days, **when** the daily job runs, **then** objects move to the `archive/` prefix and `media_assets.status` becomes `archived`; messages stay intact and linkable.
- **Given** an archived asset, **when** a member opens it, **then** it rehydrates to the hot prefix on demand and serves a URL; UI shows "recovering attachment", never a crash.
- **Given** a failed run, **when** it retries, **then** it resumes idempotently — nothing lost or double-moved.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `COM-BR-001` | Only `VERIFIED` users (module 03) may read/write any chat/notice/media surface; others get `NOT_VERIFIED` | Service layer (every entry point) |
| `COM-BR-002` | Group membership is required to read/post; all message queries are tenant + group scoped | Service + tenant-scoped repository |
| `COM-BR-003` | Official groups bind 1:1 to a section node, auto-created by module 04; class Teacher is `moderator`; students auto-join as `member` | 04 calls `chat.JoinSectionGroups`; DB CHECK `kind=official ⇒ section_id NOT NULL` |
| `COM-BR-004` | DM rooms open instantly only for two verified same-school users; cross-school requires an `accepted` Message Request; room id `dm:{minUserId}:{maxUserId}` | Service (DM resolver) |
| `COM-BR-005` | Notices are one-way: School Admin publishes `scope=school` (own tenant); Teacher publishes `scope=section` (own section); Students/Guardians have no write path | Service + role guards |
| `COM-BR-006` | Notices are immutable after publish except pin/unpin and soft delete; no edit endpoint exists | API surface + service |
| `COM-BR-007` | Message delete: author ≤ 15 min; moderator/owner/School Admin anytime; soft tombstone, never row removal | Service |
| `COM-BR-008` | `(sender_id, client_msg_id)` unique: replay returns the original message, never a duplicate | DB unique index + upsert |
| `COM-BR-009` | Media caps: image ≤ 10 MB (client ~1 MB target), PDF ≤ 20 MB, voice ≤ 5 min; presign TTL 15 min; magic-byte sniff on confirm rejects mismatches | `media.PresignUpload`/`ConfirmUpload` |
| `COM-BR-010` | Custom groups stay `pending_approval` until same-tenant School Admin approval; creator becomes `owner` on activation | Service + DB status |
| `COM-BR-011` | Retention: messages indefinite per tenant; media 90 days R2 hot, then `archive/` prefix (linkable, rehydrate on demand) | Archival job (`COM-BE-025`) |
| `COM-BR-012` | Tenant isolation: official/custom/notices/media tenant-scoped; the only cross-tenant path is a DM after an accepted request, authorized by membership — never by tenant query | Repository (every query) + `COM-IT-001` |
| `COM-BR-013` | Chat endpoints + WS sends rate-limited under class `messaging`; Message Request creation stricter (anti-spam) | Redis rate limiter |

> Content-accuracy (`prompt.txt` §12): seeded demo groups/notices use clearly fictional data ("Demo High School") marked in `03` §1.3; real notices are authored only by verified School Admin/Teacher accounts, so no `TODO:` placeholder reaches a live board.

## 6. Validation Rules

| Field | Rule | Message key (`packages/shared` i18n catalog) |
| --- | --- | --- |
| Message `body` (text) | 1–4000 chars after trim; no control chars | `validation.chat.body_length` |
| Message `client_msg_id` | UUID v4, required on every send | `validation.chat.client_msg_id` |
| Message `mediaAssetId` | Required when `kind ∈ image\|pdf\|voice`; asset `confirmed` + owned by sender | `validation.chat.media_required` |
| Message `replyTo` | Optional; same-group message, not deleted | `validation.chat.reply_invalid` |
| Group `name` (custom) | 3–60 chars, unique among active tenant groups | `validation.chat.group_name_length` |
| Notice `title` / `body` | 3–120 chars / 1–5000 chars | `validation.notices.title_length` · `body_length` |
| Notice `scope` | `school` \| `section`; section requires in-tenant `sectionId`; caller role matches scope | `validation.notices.scope_invalid` |
| Media upload | `kind ∈ image\|pdf\|voice`; size ≤ cap; mime allowlist | `validation.media.kind_invalid` · `too_large` |
| Message Request `toUserId` | Not self; peer VERIFIED; no duplicate `pending` | `validation.chat.request_invalid` |
| Voice `durationMs` | ≤ 300000 (5 min) | `validation.chat.voice_too_long` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (app) generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED`, no side effect; WS close 4401 |
| 2 | Cross-tenant read/write attempt (group/notice/media) | `TENANT_MISMATCH` / 404, no leak (`COM-IT-001`) |
| 3 | Unverified user tries to post/join/request | `NOT_VERIFIED` + "how to get verified" guidance |
| 4 | Referenced media deleted / R2 object missing | Degraded placeholder ("attachment unavailable"), never a crash |
| 5 | Reduced motion enabled | Static form of bubble transitions, typing dots, state morphs |
| 6 | Offline action (app) | Queued with visible banner — never silently lost (US-015) |
| 7 | WS drops mid-send (ack lost) | Bubble stays SENDING; replay on reconnect dedupes by `client_msg_id` |
| 8 | Presigned URL expired (> 15 min) before PUT | Client re-requests upload-url; orphan `pending` asset reaped after 24 h |
| 9 | Both peers open the same DM simultaneously | Unique `(min,max)` pair — one room, both get the same id |
| 10 | Request to self or to an unverified peer | `VALIDATION_FAILED`; no row |
| 11 | Post into an archived group (year-end migration) | Reads allowed; post refused `CONFLICT` + pointer to new group |
| 12 | Notice deleted while being viewed | "নোটিশ সরিয়ে নেওয়া হয়েছে / This notice was removed" state |
| 13 | Voice recording interrupted by a phone call | Partial recording discarded; nothing uploads |

## 8. Reporting Needs

- School Admin dashboard (module 07) aggregates: notices published/month, active groups per school, weekly message volume per section — counts only, never content.
- Module 09 consumes `chat.GroupMembers(groupID)` for aggregate-only analytics sampling; no message bodies leave this module (`06` §2).

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Confirm chat retention / media TTL policy | Rahul | Open | Messages retained indefinitely per tenant; media 90 days R2 hot then archived (linkable, rehydrate on demand) |
| 2 | Must custom "club" groups wait for School Admin approval before activation? | Rahul | Open (`TODO: Confirm`) | Yes — approval required; creator becomes `owner` on approval |
| 3 | Expiry window for unanswered Message Requests | Rahul | Open | 7 days, then `expired` |
| 4 | Confirm media caps (image 10 MB / PDF 20 MB / voice 5 min) and presign TTL 15 min | Rahul | Open | As stated; tunable config, not code |
| 5 | Confirm students/guardians never post to school-wide boards (one-way notices) | Rahul | Open | One-way; only School Admin (school) / Teacher (section) publish |
