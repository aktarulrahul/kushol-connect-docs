# 05-communication-engine — Build Progress

Module: communication-engine · Surfaces: api + app (web N/A — 07 builds the composer on these
endpoints) · Repos: `applications/api`, `applications/app` (branch `module/03-identity-access`
working tree — ADR-4) · **Last updated:** 2026-10-15

> Note: the build prompt parameter `TODAY=2026-10-01` lags the actual build date; dates are
> recorded truthfully as 2026-10-02 (same convention as module 04).

## Stage / gate status

| Stage                     | Status                                                                                                                                                                                       | Evidence (dated)                                                                                                                                                                                                                                           |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 Plan                    | ✅ approved 2026-10-02                                                                                                                                                                       | owner: "proceed" with recommended options                                                                                                                                                                                                                  |
| 2 UI (app, mock-driven)   | ✅ 2026-10-02                                                                                                                                                                                | COM-AP-001…019 on fixtures; app gate green (lint · typecheck · unit 176/176)                                                                                                                                                                               |
| Gate 1 (UI approval)      | ✅ owner 2026-10-15                                                                                                                                                                          | owner approved in session ("complete all from Gate 1") — covers the 2026-10-02 fixture hand-off **and** the 2026-10-09 Spartens restyle (ADR-9); device pass at 360px bn/en still recommended, recorded as gap G-9a                                        |
| 3 Docs sync               | ✅ 2026-10-02 · checklist sync 2026-10-15                                                                                                                                                    | this file, `08-gaps.md`, README row → 🚧; `03` backend + `06` integration checklists ticked 2026-10-15 (`COM-BE-001…027`, OpenAPI paths, tests; `COM-INT-001…011/013`). Open: seed item (no demo chat-group seed verified), `COM-INT-012` (E2E runs — G-1) |
| 4 Backend                 | ✅ code-complete 2026-10-02 (migrations · services · gateway · exports · handlers · wiring · unit tests) — Gate 2 hand-off below                                                             | evidence table                                                                                                                                                                                                                                             |
| Gate 2 (SQL on Neon)      | ✅ owner                                                                                                                                                                                     | 2026-10-09 — all migrations applied to Neon via 15's first deploy (`v0 → 20270302090001 dirty=false`), covers the 05 block `20261003090000–094000`                                                                                                         |
| 5 Integration             | 🚧 resolved 2026-10-09 (owner `make test-integration` green, 32 pkgs — IT011/012/013 + `ListGroupsForUser` SQL fixed); remaining: app fixture swap, MMKV offline queue, real R2/device flows | G-3/G-4                                                                                                                                                                                                                                                    |
| Gate 3 (integrated flows) | ⏳ pending                                                                                                                                                                                   | —                                                                                                                                                                                                                                                          |
| 6 Gaps & verification     | 🚧                                                                                                                                                                                           | `08-gaps.md`                                                                                                                                                                                                                                               |

## Owner decisions (2026-10-02) — ADR

1. **ADR-1 (owner):** pickers/data DB-backed and school onboarding via request approval — see 04
   `07-progress.md` ADR-1/2; 05 consumes `hierarchy.ResolveUserNodes`/`GetSection` (implemented).
2. **ADR-2 (owner, 2026-10-02):** "proceed with recommended" — approval flow wiring in 03, POC as
   first pre-verified School Admin, audit-only request↔school trace.
3. **ADR-3 (owner, 2026-10-02, module 06 run): "DO NOT CHANGE the existing chat screen and bottom
   menu".** The module 06 build must not modify `(tabs)/chat/*` or the floating tab bar; 06 adds
   its surfaces as separate routes. Recorded here because it binds 05's shipped UI too.
4. **ADR-4:** no commits authorised; 05 works in the tree alongside 03/04 WIP (standing rule 2).
5. **ADR-5 (owner, 2026-10-02):** standing rule — the agent never runs the app (see workspace
   `AGENTS.md` rule 1). All container/live-DB work is owner-run with exact commands.
6. **Download URL endpoint (#21):** the 20-endpoint table had no way to mint the short-lived R2
   GET URLs US-005/012 require — added `POST /media/{id}/download-url` (module-own spec fix).
7. **Club approval endpoint (#22):** COM-BE-005/US-013 require a Super-Admin/School-Admin approve
   action for `pending_approval` clubs; the endpoint table predates it — added
   `POST /chat/groups/{id}/approve`. Both additions recorded in the registry note below.
8. **notify port:** `notify.BroadcastTopic` (06) is unbuilt — 05 consumes a narrow `Broadcaster`
   port with a Noop binding (03's `internal/notify` is 03-owned, untouched); 06 binds the real
   fan-out in its build (mirrors the 04↔05 chat port precedent).
9. **ADR-8 (owner, 2026-10-09): tab shell change (final rev 3)** — bottom bar = Home · Explore ·
   Chat · Store · Profile. Shop returned as **Store** (same `/shop` stub, relabelled); Explore
   (events + tuition listings) stays; You/Profile relabelled from "Users". **Notifications moved
   off the bar**: the bell lives in every tab root's header (Spartens-style — circle action +
   unread-count bubble → `/notifications`; `ScreenHeader` actions gained an optional `badge`;
   shared `useNotificationBellAction` hook). Chat header is Spartens chrome: search field inside
   the header, bell beside the new-club action. Notice board + detail routes highlight no tab.
   Conversation-surface restyle (Spartens bubbles/composer/date separators) — done, ADR-9.
10. **ADR-9 (owner, 2026-10-09): "implement same chat or channel screen … like
    `tec/Spartens/Mobile-App`"** — the chat list and the conversation screen now follow the Spartens
    `(tabs)/chat` + `channels/[channelId]` screens, in Kushol tokens, on the Stage-2 fixtures (no new
    dependency, no native rebuild):
    - **List** (`(tabs)/chat/index.tsx`): search pill + bell header (no title) · filter chips All ·
      Unread · Official · Community · DMs · rows with presence, "Draft: …", time, unread pill, pin
      and mute marks · long-press row menu (pin chat ≤ 5, notification settings All / None) · pull to
      refresh · floating new-club button.
    - **Conversation** (`components/chat/group-chat-screen.tsx`): channel header (back · avatar +
      name + members/typing/online · info sheet) · pinned-message bar (tap jumps + cycles) · inverted
      list with day pills and the "N new unread" pill captured on open · Spartens bubbles (author
      avatar + name in groups, reply quote with author → tap jumps + highlights, 1–3 emoji large,
      "edited", pin mark) · swipe-to-reply (PanResponder) · long-press focus menu (blurred room,
      lifted bubble, quick reactions, Reply / Edit / Pin / Message info / Delete with confirm) ·
      reply + "Editing message" banners · share sheet (image · PDF · sticker) · typing pill · jump to
      latest · lock line for read-only rooms · tap a failed bubble to resend.
    - Fixture-only additions (gap G-7): `editChatMessage`, `setChatMessagePinned` + `editedAt` /
      `pinnedAt` on `ChatMessage`; pinned chats, mute and drafts in `chat-state`. Not ported: Copy
      (needs `expo-clipboard`), GIF / poll / location / mentions / tasks (G-8).
    - **State of the tree (2026-10-09, later pass):** the interaction layer above (pinned bar,
      swipe-to-reply, edit flow, focus menu, drafts) is NOT in the working tree — only its fixture
      support landed. What landed in components is the Spartens **visual** system: bubbles
      (square-outer-corner incoming `bg-card` / teal outgoing, group author avatar + primary name,
      block reply quotes, Spartens tombstone), centred card date separators, channel header
      (back · centred avatar/name/status · spacer), composer (soft-tint attach circle, card field
      pill → rounded-2xl on multiline, in-field arrow-up send, mic swap kept). Chat list: Spartens
      header chrome (search in header, bell + new-club actions). The remaining interactions ride
      the existing fixtures and stay open (G-9).
    - Fixes on the way: history now renders oldest → newest whatever the page order (the fixture
      page is newest-first); `message.ack` + `message.new` no longer double a sent bubble; the
      composer avoids the iOS keyboard; test helper stops mutation GC timers keeping Jest alive.

## Defaults relied on

- OQ-1: messages indefinite; media 90 d hot → `archive/` (rehydrate on demand).
- OQ-2 (`TODO: Confirm`): clubs need same-school School Admin approval; creator → owner.
- OQ-3: request expiry 7 days (hourly job). OQ-4: image 10 MB / PDF 20 MB / voice 5 min,
  presign TTL 15 min — code constants, not env. OQ-5: notices one-way (admin → school,
  teacher → own section). `SectionQuestionSamples` ships masked + no-author; school opt-in is
  `TODO: Confirm` (06 §2).
- Precedence: 04's `hierarchy.Chat` port (ctx-first) supersedes 05's ctx-less signature note
  (consumer-side port, additive).

## Evidence

| Repo   | Check                                                                             | Result                                                                                                                                                                                                                                                                                                                                                                     |
| ------ | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| api    | `openapi.yaml` + `make contracts`                                                 | 22 chat/notices/media paths + WS contract (#21 download-url, #22 club-approve added — ADR-6/7); `contracts: no drift`                                                                                                                                                                                                                                                      |
| api    | `go build ./...` + `go vet ./...` (+ `-tags=integration` on chat)                 | clean, 2026-10-02                                                                                                                                                                                                                                                                                                                                                          |
| api    | `make fmt-check` (gofmt + goimports -local)                                       | clean                                                                                                                                                                                                                                                                                                                                                                      |
| api    | golangci-lint `./...`                                                             | 0 issues in 05 code (1 pre-existing errcheck in 03's uncommitted `smsout.go` WIP — not 05's)                                                                                                                                                                                                                                                                               |
| api    | `go test -race ./...` (unit)                                                      | **22/22 packages ok** (chat guards + media sniffer/SigV4 + WS-app state machine)                                                                                                                                                                                                                                                                                           |
| api    | `gorilla/websocket v1.5.3` pinned                                                 | go.mod (tech-stack latest-verify: gorilla/websocket current stable 1.5.3)                                                                                                                                                                                                                                                                                                  |
| api    | COM-IT tests written                                                              | `it_chat_test.go`: seam idempotency, idempotent send, request lifecycle, notice board matrix, media sniff/authz — **pending owner run** (`make test-integration`, G-6)                                                                                                                                                                                                     |
| api    | 2026-10-09 owner `make test-integration` run 1                                    | COM-IT-002 (IT011) / COM-IT-003 (IT012) / COM-IT-005 (IT013) failed — **fixed 2026-10-09, re-run pending owner** (see fix log below)                                                                                                                                                                                                                                       |
| wiring | `cmd/api`                                                                         | real hierarchy service replaces the demo fake (04 entry-point item done: DB-backed pickers + BR-01 seam); chat ⇄ hierarchy mutual binding via `SetHierarchy`; hub on `GET /api/v1/ws` with JWT + verified gate + server-resolved rooms; jobs `chat.request_expiry`, `media.archival`, `media.pending_cleanup` registered; R2 gated by `R2_*` env (501s cleanly when unset) |
| app    | `pnpm lint && pnpm typecheck && pnpm test`                                        | clean · clean · **176/176** (incl. WS-client state machine 4/4, i18n parity 13/13)                                                                                                                                                                                                                                                                                         |
| app    | 2026-10-09 Spartens chat/channel (ADR-9): `tsc` · eslint (changed files) · `jest` | clean · clean · **313/314** — the one failure is the pre-existing `src/__tests__/index.test.tsx` holding-screen test (failed before this change too); +41 tests (list filter, message utils, chat-state prefs, fixture edit/pin, menu placement, row/bubble/composer/menu, screen smoke) · `test:rules` 10/10 · `contracts: no drift`                                      |
| app    | Maestro specs                                                                     | `.maestro/communication-{chat-send,offline-replay,notices}.yaml` written; **runs pending owner** (no CLI/device here — G-6)                                                                                                                                                                                                                                                |

## Gate 1 review hand-off (owner, on device)

```sh
cd applications/app && pnpm ios   # or pnpm android — dev build, fixture mode ON
```

1. Sign in (any phone, code `123456` — identity fixtures land the demo teacher).
2. **Chat tab**: segments অফিসিয়াল/ক্লাব/ডিএম; unread badges; request banner → inbox; open
   `দশম শ্রেণি · বিজ্ঞান (ডেমো)` — history, bn date separators, tombstone, image/PDF/voice
   bubbles; send a text (SENDING→✓→✓✓), attach image/PDF, record voice (≤5 min cap), long-press
   delete, reply; demo peer typing + reply within ~5 s.
3. **Notices tab**: pinned first, scope badges, attachment chip → detail → PDF viewer;
   compose (+ button) publishes a section notice.
4. **DM**: `ডিএম` segment → `করিম আহমেদ` opens instantly; request inbox accept/decline;
   cross-school peer shows the request hint.
5. **States**: `/dev/chat-fixtures` toggles offline (banner + queued clock bubble → replay),
   send-failed (red + retry), rate-limited, forbidden, unverified gate.
6. Screenshots: 360px, bn + en (language switch in settings).

## Stage 5 — Client integration (app live swap + web composer live glue) — 2026-10-16

Owner instruction this run: "implement the chat features in both web and app" (web was N/A at
Stage 2; 07's composer UI already existed on fixtures — brought live this run).

- **app**: src/lib/chat/live-chat.ts — live backend behind the @/fixtures/chat seam. REST via
  the generated client through liveAuth() (bearer + single-flight 401 rotate); realtime via the
  real WS gateway (ws-client, per-socket Authorization header — RN WebSocket; reconnect
  re-reads the rotated token). Errors map onto the shared fixture codes (screens keep their
  states; NOT_IN_LIVE added for spec-less seams). Media pipeline: live presign → client PUT
  (blob) → confirm → download-url.
  ealtime.ts: live socket state drives the connection slice;
  reconnect fires a REST catch-up invalidation. Screens untouched (ADR-3 — the swap lives in the
  seam + lib only).
- **web**: src/lib/chat/live-console-chat.ts — the console messenger seam
  (@/fixtures/console-chat) delegates when a session cookie is live: conversations, messages,
  send, delete, read, club create (pending_approval), members add/remove on the real api
  (credentials include). schema.gen.ts regenerated (chat paths now typed). api-less console
  affordances (reactions, polls, explore, forward, rename, message pin/edit, asset galleries)
  raise ConsoleNotAvailableError (G-9) instead of silently no-opping.
- **checks**: app sc clean · chat-file lint clean · 313/314 tests pass — the 1 failure is
  pre-existing and unrelated (src/**tests**/index.test.tsx expects the anon holding screen but
  the 03 auth-store now boots idle until restore — G-8). web sc clean · seam lint clean ·
  **220/220 tests pass (28 files)**.
- Sticker pickers degrade live: emoji-as-text (no sticker kind in the OpenAPI — G-7). Console
  reactions/polls/explore/forward/rename/message-pin/asset-galleries: demo-only until the owner
  decides additive endpoints vs trimmed UI (G-9).

**Gates 1–3 remain owner-run.** Gate 2 note: the LOCAL dev stack auto-applies migrations at
dev-start.sh (step 5 migrate up), so app↔api chat integration is testable locally now; the
shared Neon database still needs the manual migration pass before any hosted verification.

## G-9 backend + full-stack integration — 2026-10-16 (owner: "implement the all required backend")

- api: additive spec paths (edit, pin, seen-by, reactions toggle, poll vote, forward, club
  rename, explore + join, group assets) + ChatMessage gains editedAt/pinnedAt/pinnedBy/
  reactions/poll; kind `poll` added to the CHECK + spec enums. Migration
  `20261016090000_com_chat_rich_messages` (reactions + poll-votes tables, edit/pin columns).
  Service `internal/chat/rich.go` (guards: author-only edit, CanPin, membership, poll rules —
  pure `DecidePollVote`/`ValidatePoll`/`CanPin` unit-pinned), handlers `handlers_rich.go`,
  history enriches reactions/polls batch (no N+1), WS `message.updated` fans out.
- clients regenerated both sides. web: live-console-chat consumes every new surface (the
  ConsoleNotAvailableError paths are gone). app: edit/pin/seen-by now live (NOT_IN_LIVE gone);
  poll sends from the app are typed-blocked (web-only composer).
- checks: api build+vet clean, unit tests all green (new rich-guard tests); app tsc 0 · 313/314
  (only pre-existing G-8) · chat lint clean · require cycle broken via `lib/chat/stickers.ts`;
  web tsc 0 · 220/220 · seam lint clean.
- gates: 1–3 remain owner-run; Gate 2 note unchanged (Neon manual pass; local dev auto-migrates).

## WhatsApp-like chat on web `/chat` + app, auto-created groups, R2 attachments — 2026-10-17

Owner instructions this run (precedence §1.1 #1): "implement the chat features in both app and
web (`/admin/chat` → `/chat`), keep the same UI, implement the backend functionality, similar to
WhatsApp; chat groups and the Kushol Admin group are created automatically"; "for attachments
(images, pdf, doc, excel, csv, voice note) use Cloudflare R2"; "in the mobile app consider both
Android and iOS layout".

### Decisions (ADR-9 … ADR-14)

- **ADR-9 — auto-created groups.** Three server-managed families, kept in sync by the api (startup
  sweep `ProvisionAll` + lazy per-user `autoProvision` on every chat list): **Kushol Admin**
  (`system_key = kushol_admin`; every VERIFIED super_admin; the seeded group is adopted),
  **institution staff** (`institution:{schoolId}`; the school's VERIFIED school_admins as
  moderators + teachers as members — the institution admin's home chat on the web) and **section
  groups** (official, created for every ACTIVE section even before anyone verifies; students and
  teachers still join via 04's `JoinSectionGroups`). Managed rosters are added _and pruned_
  (suspended/unverified users leave); managed groups refuse leave/rename/manual add.
  Interpretation of "chat group will be created automatically" — `TODO: Confirm` with Rahul that a
  per-institution staff group is wanted (it is the only auto group an institution admin is in).
- **ADR-10 — group lifecycle.** Super admins create platform groups (no school) and institution
  admins create school groups that are live at once; teachers/students still request clubs that
  wait for approval (BR-010). Description (≤ 500) on create + edit. Exit group = self-removal for
  custom, unmanaged groups; a leaving owner hands ownership to the longest-standing moderator.
- **ADR-11 — direct messages.** Same-school instant DMs unchanged; added the platform support line
  (super_admin ↔ super_admin / school_admin) — `DirectAllowed`. Everything else still needs an
  accepted Message Request (BR-004). People picker `GET /chat/contacts` returns name + role only.
- **ADR-12 — WhatsApp semantics.** Read horizon (`ChatMessagePage.readUpTo`) drives single tick /
  blue double tick; list rows carry `lastMessageKind` + sender for "You: …" / "Name: …" previews;
  tombstones never return their body; edits/pins/reactions/polls fan out `message.updated`,
  roster/name changes `group.updated`; reactions and polls carry per-viewer `mine` / `userVoted` on
  REST reads.
- **ADR-13 — attachments on R2.** Media kinds `doc` (.docx/.doc), `sheet` (.xlsx/.xls), `csv` added
  (plus `slides` in the enum, unused by chat); legacy OLE `.doc/.xls` sniffed; CSV sniffed as UTF-8
  text without control bytes; captions allowed on image/pdf/doc/sheet/csv (not voice); original
  file names persisted. Caps: image 10 MB · pdf/doc/sheet 20 MB · csv 10 MB · voice 5 MB / 5 min.
  App: real pickers (`expo-image-picker`, `expo-document-picker`) and recorder (`expo-audio`, mono
  AAC 64 kbps `.m4a`) in **live sessions only**; the file streams from disk to the presigned URL
  (`expo-file-system/legacy` `uploadAsync`) — React Native's `Blob` cannot be built from bytes.
  Demo/fixture sessions keep the simulated picks (tests + Maestro unchanged).
- **ADR-14 — web route.** The messenger moved to **`/chat`** (same `AdminPortalLayout` shell and
  role-aware nav; `/admin/chat` → `/chat` redirect in `next.config.ts`). Same component; behaviour
  wiring only (+ "New chat / New group" on the existing "+" button, contact search in the existing
  Add-members dialog, a description editor).

### Defects found and fixed (evidence: `applications/.dev/logs/api.log`, code audit)

1. `20261016090000_com_chat_rich_messages` sat **below** the applied `20270304090001`, so
   golang-migrate skipped it and history failed (`column m.edited_at does not exist`, api log
   2026-10-17 11:32). Re-stamped to `20270305090000`, idempotent (`IF NOT EXISTS`).
2. `chat_messages_content_chk` (2026-10-03) rejected every poll insert — fixed in `20270305091000`.
3. `20270304090001` dropped the Office media kinds from the CHECK (doc/sheet uploads failed) — restored.
4. **The WS hub was never bound to the chat service** (`SetHub` missing in `cmd/api`): no realtime
   event ever reached a socket. Bound.
5. Gateway: browser upgrades failed the same-origin check behind the Next dev rewrite (Host is
   rewritten) → explicit `CheckOrigin` (Host or X-Forwarded-Host); concurrent writes to one socket
   (gorilla forbids them) → per-socket write lock + deadlines (also stops `http.Server.WriteTimeout`
   killing hijacked sockets after 30 s); the in-process bus echoed every publish → node-tagged
   envelopes; clients never subscribed to rooms (the app sends `rooms: []`) → server auto-subscribe
   - live attach/detach on membership change; presence expired after 60 s while connected →
     heartbeat refresh + a snapshot on subscribe; no server pings → real ping frames.
6. Response envelopes: 16 handlers wrapped bare-schema responses in a `data` envelope (send, create
   group, add member, reactions, edit, pin, vote, rename, join, confirm upload, …) and 5 were
   double-wrapped (`seen-by`, `forward`, `explore`, `assets`, `notices`) — both clients read
   `undefined`. Handlers now match the contract.
7. History dropped attachments, edit/pin state and unvoted polls; sends returned no sender name;
   tombstones returned their body. Fixed.
8. The web live seam called the api cross-origin (no CORS — it silently fell back to demo data) and
   sent no CSRF header; history order was reversed. Now same-origin + `X-CSRF-Token`.
9. The app treated the demo teacher as "me" in live sessions (own bubbles rendered as incoming) →
   `useChatMe()` from the auth store; reactions were local-only → server toggle + render.

### Contract (OpenAPI, synced to web + app)

New: `GET /api/v1/chat/groups/{groupId}/members` (`listChatGroupMembers`), `GET /api/v1/chat/contacts`
(`listChatContacts`). Additive changes: `PATCH /chat/groups/{groupId}` accepts `name` and/or
`description`; `DELETE …/members/{me}` = leave; `ChatGroup` + `lastMessageKind`,
`lastMessageSenderId`, `lastMessageSenderName`, `description`, `managed`; `ChatMessage` +
`replySenderName`; `ChatReactionSummary.mine`; `ChatPoll.userVoted`; `ChatMessagePage.readUpTo`;
message/send kinds + `doc|sheet|csv`; `MediaKind` + `doc|slides|sheet|csv`;
`MediaUploadUrlInput.fileName`; `MediaAsset.fileName`; `ChatGroupAssetFile` + kind/mime/size/name;
WS events `message.updated`, `group.updated`, presence snapshot and auto-subscribe documented.

### Migrations (Gate 2 — owner runs; the local `dev-start.sh` applies them automatically)

| Version          | File                     | What                                                                                                                                                                                                                                                                         |
| ---------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `20270305090000` | `com_chat_rich_messages` | re-stamp of the skipped 2026-10-16 file (reactions, poll votes, edit/pin columns, poll kind) — idempotent                                                                                                                                                                    |
| `20270305091000` | `com_chat_system_groups` | `chat_groups.system_key` (unique) + `description`; shape check allows section-less official (institution) groups; Kushol Admin group adopted; media kinds doc/slides/sheet/csv; message kinds doc/sheet/csv; content check fixed (polls, captions); `media_assets.file_name` |

Owner command (shared database): `cd applications/api && go run ./cmd/api migrate up --confirm && go run ./cmd/api migrate-status`

### Evidence (agent-side checks — no app, no containers)

| Repo    | Check                                                             | Result                                                                                                                                                                                                                   |
| ------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| api     | `sqlc generate` + `oapi-codegen`                                  | regenerated; `make contracts-check` → **contracts: no drift**                                                                                                                                                            |
| api     | `go build ./...` · `go vet ./...` (+ `-tags=integration` on chat) | clean                                                                                                                                                                                                                    |
| api     | `go test ./...` (unit)                                            | **all packages ok** — new pins: `chat/system_test.go` (17), `chat/gateway/hub_test.go` (6), media sniff + file name (2). `-race` cannot run on this Windows host (no C compiler) — `make test` on the owner's machine/CI |
| api     | golangci-lint (chat, media, cmd)                                  | no findings except gofmt-on-CRLF artefacts (content verified formatted on CR-stripped copies)                                                                                                                            |
| api     | integration tests written, **pending owner run**                  | `TestIT015ManagedGroups`, `TestIT016PollsHistoryAndGroupLifecycle` (`make test-integration`)                                                                                                                             |
| web     | typecheck · eslint (touched files) · prettier                     | clean (full `pnpm lint` reports 19 pre-existing errors in the untouched `admin/audit/audit-page-client.tsx`)                                                                                                             |
| web     | `pnpm test`                                                       | **238/238** tests (30 files), including the new chat pins (`live-console-chat.test.ts`, `console-socket.test.ts`)                                                                                                        |
| web/app | spec copy vs api                                                  | identical (`sync:api-spec` + `generate:api`)                                                                                                                                                                             |
| app     | typecheck · eslint (chat scope)                                   | clean (media-viewer lint errors exist identically at HEAD)                                                                                                                                                               |
| app     | `pnpm test`                                                       | **330/331** (50 suites) — the 1 failure is the pre-existing `src/__tests__/index.test.tsx` (G-8); new `whatsapp-chat.test.ts` green                                                                                      |
| app     | full `pnpm lint`                                                  | 15 findings, all in files this run did not change or that carry them identically at HEAD (`media-viewer.tsx`, `(tabs)/_layout.tsx`, two ui tests)                                                                        |

### Gate hand-off (owner)

1. `bash applications/dev-start.sh --android` — the app lockfile changed, so the dev client rebuilds
   with expo-image-picker / expo-document-picker / expo-audio / expo-file-system (iOS: `--rebuild`).
2. Web: sign in as `aktarul.islam@kusholconnect.com` → **http://localhost:4433/chat** → "Kushol
   Admin" is listed; send text, reply, react, pin, edit, delete, poll; a second browser as
   `atiqul.islam@kusholconnect.com` sees messages, typing, ticks and presence arrive live.
3. Web: attach a JPG, a PDF, a .docx, a .xlsx and a .csv → bubbles render; Download opens the R2 URL
   (needs the R2 bucket CORS rule — 08-gaps G-12).
4. Web as an institution admin → the "{school} · শিক্ষক ও প্রশাসন" group is listed (managed — Add and
   Exit explain that membership is automatic); New group is live at once; Add members via search.
5. App (Android + iOS) as a verified teacher → section + staff groups; send text, a photo, a
   document and a recorded voice note; the composer sits above the keyboard and the recorder above
   the home indicator / gesture bar.

## G-11 closed — upload size enforced at media confirm — 2026-10-17

Owner: "Do this task here: Enforce R2 upload size at media confirm".

- The presigned R2 PUT signs only `host`, so the declared `sizeBytes` was just the client's claim.
  `ObjectStore.HeadBytes` became `ReadHead` → `ObjectHead{Bytes, Size}`: the same ranged GET that
  feeds the sniff now reads the stored object's real size (`Content-Range: bytes 0-511/<total>`,
  `Content-Length` on a 200, `416` = empty object). Unknown totals fail closed.
- `ConfirmUpload` runs `CheckUploadSize(kind, realSize)` before the sniff: empty or over-cap
  (image 10 MB · pdf/doc/sheet 20 MB · csv 10 MB · voice 5 MB) → VALIDATION_FAILED and the
  object is deleted at once (the pending row is still swept by `media.pending_cleanup`).
  Confirmed assets now store the **real** size (`ConfirmMediaAsset` takes an optional
  `size_bytes`; server-put objects keep their inserted size). No contract or migration change.
- Also fixed: CSV object keys had no extension (`objectKey` map lacked `KindCSV`); `DeleteObject`
  gained the same justified `#nosec G704` notes as the other R2 calls.

| Check                                                       | Result                                                                                                                                                                                                            |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sqlc generate` · `make contracts-check`                    | regenerated · **contracts: no drift**                                                                                                                                                                             |
| `go build ./...` · `go vet` (+ `-tags=integration` on chat) | clean                                                                                                                                                                                                             |
| `go test ./...`                                             | all packages ok — new `internal/media/size_test.go`: `CheckUploadSize` (9 cases), `objectSize` (7), `R2Store.ReadHead` against a canned transport (signed ranged GET, 206/416/unknown/500), object-key extensions |
| golangci-lint `./internal/media/...`                        | no findings (besides gofmt-on-CRLF artefacts; content verified formatted)                                                                                                                                         |
| `TestIT014MediaConfirmAndAuthz` (extended)                  | over-cap upload rejected + object deleted; confirmed asset carries the real size — **pending owner run** (`make test-integration`)                                                                                |

## Conversation wallpaper (WhatsApp-style, education doodles) — 2026-10-17

Owner: "like whatsapp, add background images in chat active conversation" → "add high quality
background with pen pencil book etc related to educational institution".

- **Artwork (ADR-15):** original line art (not WhatsApp's): pen, pencil, pencil cup, open book,
  book stack, spiral notebook, ruler, set square, protractor, compass, scissors, eraser, crayon,
  paintbrush, paper clip, calculator, abacus, chalkboard, globe, microscope, flask, test tubes,
  atom, lightbulb, magnifier, laptop, backpack, graduation cap, diploma, trophy, school bell,
  alarm clock, apple, paper plane, music note, question bubble, plus maths signs (π, √, Σ, ÷, ×,
  =, %), letters/digits and sparkles. 420 × 420 seamless tile, 85 drawings: one per 70-px cell
  (random tilt/size/offset, kept inside its cell) + small signs on cell corners and on both
  opposite tile edges so the seam is as dense as the inside. Brand teal `#095777` at 10% opacity,
  1.35 stroke, round caps.
- **Web `/chat`:** `src/assets/chat/doodles.svg` (bundled via `globals.css` `.chat-wallpaper` →
  `/_next/static/media`, so the auth proxy never intercepts it) over the existing `wa-wall` token;
  background stays fixed while messages scroll. Precedence note: the design reference §7 says "no
  playful illustration on web" — the owner's instruction wins (§1.1 #1); the art stays subtle.
- **App (Android + iOS):** `ChatWallpaper` draws the same paths
  (`chat-wallpaper-doodles.ts`) as one `react-native-svg` `Pattern` over `teal-100` behind the
  transparent message list — vector-crisp at every density, no bitmap assets, identical on both
  platforms.
- Generator + previews: `screenshots/chat-wallpaper-generator.py` (re-run to change the art; it
  writes both files), `screenshots/chat-wallpaper-{tile,web,app}.png` (sharp-rasterised previews).
- Also fixed: the web demo gallery placeholder pointed at `/brand/logo.svg`, which never existed
  (web has no `public/`) — now the bundled lockup.

| Repo | Check                                                     | Result                                                                                                                                         |
| ---- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| web  | `pnpm typecheck` · eslint (messenger) · prettier          | clean                                                                                                                                          |
| web  | vitest (chat + console fixtures)                          | 30/30                                                                                                                                          |
| app  | `pnpm typecheck` · eslint (wallpaper + screen) · prettier | clean                                                                                                                                          |
| app  | jest `src/components/chat` + `src/lib/chat`               | 75/75 (12 suites)                                                                                                                              |
| web  | `next build`                                              | not run (would share `.next/` with the owner's running dev server); CSS `url()` bundling is standard Next behaviour — verify on the next build |

## Web hover actions + WhatsApp forward · reply · reactions · Message info · seen — 2026-10-17

Owner: "in web chat, when user hover the message, it should show the vertical3 dot for reply,
info, copy mesage, forward like whatsapp and reaction icon" → "also implement the forward,
reply, reaction, message info, seen in backend and integrate these in both web and app".

**Web hover menu.** Hovering a bubble (or keyboard focus; always on touch screens) shows a ⋮
button in the bubble's top corner — Reply · Copy · Forward · Message info (+ Pin for moderators,
Edit for my own text, Delete in red) — and a 😊 reaction button beside the bubble with the quick
emoji row. Item rules are pure (`lib/chat/message-actions.ts`); Copy copies the text, a poll's
question + options, or the file name.

**Backend (migration `20270306090000_com_chat_receipts_reactions_forward`, idempotent):**

- **Seen / delivered (ADR-16).** `chat_group_members.last_delivered_message_id` beside the read
  pointer; both pointers only move forward (a stale or replayed id answers with the current
  pointer — previously a late frame could un-read) and must point into their own group
  (previously any message id was stored). Read ⇒ delivered. Delivery is recorded when the inbox
  is listed, when a room's newest page loads, and on the new `PATCH /chat/groups/{id}/delivered`
  / WS `message.delivered` frame that clients send when another member's `message.new` arrives.
  `chat_receipt_marks` keeps one row per pointer advance (not per message per member), so
  Message info gets real times: the first mark at or after a message is when that member
  received / read it. **Bug fixed:** seen-by used to report the _send time of the reader's last
  read message_ as "read at". History pages now carry `deliveredUpTo` beside `readUpTo`.
- **Message info.** `GET /chat/messages/{id}/seen-by` → `{data: [{userId, name, status:
read|delivered, readAt?, deliveredAt?}], pending}` (read rows first in read order, then
  delivered-only; `pending` = members it has not reached). New `GET
/chat/messages/{id}/reactions` lists who reacted with what.
- **Reactions (ADR-17).** One per person (WhatsApp): a new emoji replaces mine, the same emoji
  removes it (`DecideReaction`); the migration keeps each person's newest reaction and adds a
  unique `(message_id, user_id)` index.
- **Forward (ADR-18).** `chat_messages.forward_count` (source + 1; ≥ 1 "Forwarded", ≥ 5
  "Forwarded many times"); ≤ 5 chats per forward, 1 once forwarded many times; duplicates and the
  source room collapse. **Security fix:** forwarding now requires read access to the source
  message's room (a known message id was enough before).
- **Reply.** Replying to a deleted message is refused, and the quote of a since-deleted message
  is masked (`replyKind: "deleted"`, no preview) — the deleted text used to leak through quotes.
  `replyKind` lets clients show "📷 Photo" etc. for caption-less attachments.

**Web `/chat`:** ticks ✓ sent · ✓✓ delivered · blue ✓✓ read; "Forwarded" label; deleted quotes
in italics; forward dialog hides the source chat and enforces the limit; Message info shows Read
by / Delivered to with "Today, 10:05 am" times, members not reached, and reactions; the browser
acks deliveries over the socket and coalesces receipt bursts (one refetch per room per 800 ms).
Demo reactions follow the one-per-person rule too.

**App (Android + iOS):** new Forward action + `ForwardSheet` (pick ≤ 5 chats, 1 when forwarded
many times); ticks sending → ✓ → ✓✓ → read ✓✓ (on the teal bubble read is solid white, sent and
delivered dim to 70 % — the design tokens have no blue and one-off hex values are banned, so the
approved white-on-teal "seen" stays; **Gate 1: owner to confirm the look**); the bubble's
accessibility label now says Sent / Delivered / Seen (lucide icons are aria-hidden); "Forwarded"
label; deleted quotes; Message info with real Seen / Delivered rows, "N member(s) haven't
received it yet" and a Reactions card; deliveries acked on `message.new` (socket frame, REST
fallback). Fixed both clients' tick comparison: ISO strings were compared as text, which
mis-orders the api's variable-length fractional seconds (`isoAtOrBefore`).

| Repo    | Check                                                                        | Result                                                                                                                          |
| ------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| api     | `go build` · `go vet ./...` · `go vet -tags integration ./internal/chat/...` | clean                                                                                                                           |
| api     | `go test ./...`                                                              | all packages ok — new `receipts_test.go`: `BuildReceipts`, `DecideReaction`, forward limits / targets / hop clamp, `replyQuote` |
| api     | golangci-lint `./internal/chat/...`                                          | only gofmt-on-CRLF artefacts in untouched files (touched files verified on CR-stripped copies)                                  |
| api     | `make contracts-check`                                                       | no drift                                                                                                                        |
| api     | `TestIT017ReceiptsReactionsForwardReply` (new)                               | **pending owner run** (`make test-integration`)                                                                                 |
| web     | typecheck · eslint · prettier (touched files)                                | clean                                                                                                                           |
| web     | vitest (full)                                                                | 257/257 (33 files) — new `receipts.test.ts`, hover-menu + Message info + forward UI tests                                       |
| web/app | client types regenerated from the synced spec                                | no drift (checked by hand: `contracts:check` cannot spawn `.bin` shims on Windows)                                              |
| app     | typecheck · eslint · prettier (touched files)                                | clean                                                                                                                           |
| app     | jest (full)                                                                  | 352/353 — the one failure is the pre-existing `src/__tests__/index.test.tsx` (G-8)                                              |

Owner steps: run the migration (Gate 2), `make test-integration`, and check the forward sheet,
ticks and Message info on a device (Gate 1/3).
