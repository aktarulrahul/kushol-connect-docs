# 05-communication-engine — Build Progress

Module: communication-engine · Surfaces: api + app (web N/A — 07 builds the composer on these
endpoints) · Repos: `applications/api`, `applications/app` (branch `module/03-identity-access`
working tree — ADR-4) · **Last updated:** 2026-10-17

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

## G-20 closed — receipts reach senders, not the whole room — 2026-10-17

Every member's delivered/read ack used to publish `message.delivered` / `message.read` to the
whole group room, so one message cost 2·(n−1)·n frames in an n-member group (n = 300 → about
179,400), and every client refetched history on each burst.

- **Decision (ADR-19).** Two options were evaluated:
  - (a) Publish one room-wide `receipts.updated` only when the room's horizon moves, storing the
    last published horizon on `chat_groups` (conditional `UPDATE … RETURNING`). **Rejected.** A
    horizon is per viewer (the minimum over every OTHER member), so one room value cannot serve
    everyone: the payload would need the floor plus the lone laggard's own value. It still costs
    O(n) frames per change, needs a migration and a version guard against cross-node reordering,
    and the stored value goes stale on membership changes (a join lowers the floor with no
    pointer advance).
  - (b) **Chosen.** Ticks only show on your own messages, so only the senders of messages that
    an advance newly covered need an event. They get it in their own user room.
- **How (api).**
  - The advance queries now return where the actor's pointers stood before (`read_from`,
    `delivered_from`).
  - After the advance commits, `GroupReceiptLows` reads the room's two lowest pointers per kind.
    That is enough for every viewer's horizon (`BuildHorizons`, `Horizon.For`: everyone sees the
    floor, except a member holding it alone, who sees the second lowest).
  - `ListReceiptSenders` returns each other sender's earliest message between the old and new
    pointer. `ReceiptUpdates` keeps the senders whose message is now inside their horizon, and
    each gets `receipts.updated {groupId, readUpTo?, deliveredUpTo?}` with their own horizons.
  - Result: all members' acks for one message produce **one delivered and one read event, to its
    sender only** (pinned by `TestReceiptFanOutPerMessage`, 40 members).
  - History pages use the same rule, with one query in place of `GroupReadHorizon` +
    `GroupDeliveredHorizon`, which are removed.
  - No migration. The gateway hub is unchanged: `PublishUser` already routes to `user:{id}`.
- **Across nodes.** Horizons are read after the advance commits, so of two concurrent "last" acks
  at least one sees both. The worst case is a duplicate event, which is harmless.
- **Clients.** Both clients drop the per-room 800 ms receipt refetch timers; a receipt event now
  causes no refetch at all.
  - web `/chat`: `receipts.updated` patches my ticks in place (`raiseTicks`).
  - app: it raises the cached history page's `readUpTo` / `deliveredUpTo` (`raiseHorizons`,
    `mapEvent`).
  - Events only move ticks forward, and the next history fetch stays the truth.
  - The client→server `message.read` / `message.delivered` frames are unchanged.
- **Cost.** Each pointer advance adds one horizon query, plus a senders query only when the
  advance can cover something (inbox listing: per group whose delivered pointer moved).
- **Rollout note.** App builds older than this change ignore `receipts.updated` (unknown events
  are dropped). Their ticks update on the next history load, not live.

| Repo    | Check                                                                                       | Result                                                                                                                                                                                       |
| ------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| api     | `go build ./...` · `go vet ./...` · `go vet -tags integration ./internal/chat/...`           | clean                                                                                                                                                                                        |
| api     | `go test ./...`                                                                             | all packages ok. New `horizons_test.go`: `TestHorizonFor`, `TestHorizonMatchesBruteForce` (500 random rooms vs. min over others), `TestReceiptUpdates`, fan-out per message + catch-up |
| api     | golangci-lint `./internal/chat/...` (also `--build-tags integration`)                       | only gofmt-on-CRLF in untouched `dm.go`, `exports.go`, `handler_helpers.go`; touched files have no CR and pass gofmt                                                                          |
| api     | `make contracts` · `make contracts-check`                                                   | no drift (`api.gen.go`: embedded spec text only)                                                                                                                                             |
| api     | `TestIT018ReceiptFanOutTargetsSenders` (new, beside `TestIT017`)                            | **pending owner run** (`make test-integration`)                                                                                                                                             |
| api     | `go test -race`                                                                             | not run (no cgo on this host, G-19)                                                                                                                                                          |
| web     | `tsc --noEmit` (src) · eslint · prettier (touched files)                                    | clean (tsc errors only in the dev server's `.next/dev/types` output)                                                                                                                         |
| web     | vitest (full)                                                                               | 259/259 (33 files), with new `raiseTicks` cases                                                                                                                                              |
| web/app | `pnpm sync:api-spec && pnpm generate:api`                                                   | `schema.gen.ts`: WS protocol doc comments only                                                                                                                                               |
| app     | `tsc --noEmit` · eslint · prettier (touched files)                                          | clean                                                                                                                                                                                        |
| app     | jest (full)                                                                                 | 354/355; the one failure is the pre-existing `src/__tests__/index.test.tsx` (G-8)                                                                                                            |

Owner steps: `make test-integration` (new `TestIT018`, and `TestIT017` again). No migration, so
Gate 2 does not apply. Gate 3: in a group of 3 or more, check that the sender's ✓✓ appear once
everyone has received the message and turn blue once everyone has read it, without a reload, on
web and app.

## Uploads go through the api (no browser → R2) — 2026-10-17

Owner, after a browser upload failed on the R2 preflight: "why this is expose in the browser? it
should call the backend api and api will connect the r2 storage for upload. also use pre-signed
url".

- **Decision (ADR-20).** Clients upload attachments to the api, and the api uploads them to R2
  itself. Before, the client PUT straight to a presigned R2 URL, so the bucket host and access-key
  ID showed up in the browser's network tab and bucket CORS was mandatory (the failing 403
  preflight: "CORS not configured for this bucket"). The presigned URL is still used, but only
  server-side, for the api → R2 leg.
- **api:** new `POST /api/v1/media/upload?kind=…&fileName=…[&width&height&durationMs]`. The body
  is the raw file (`application/octet-stream`) with an exact `Content-Length`.
  - The kind and size cap are checked on that length, and the magic bytes are sniffed from the
    first 512 bytes before anything is stored, so a renamed `.exe` never reaches the bucket.
  - The bytes then stream (64 KB buffer, never the whole file in memory) to a presigned PUT
    minted server-side (`R2Store.PutPresigned`, `UNSIGNED-PAYLOAD`). The response is the
    confirmed `MediaAsset`: presign, PUT and confirm in one call.
  - Transport errors are stripped of the signed URL before they can reach a log line.
  - The handler lifts the server's 30 s read/write deadlines to a 10-minute upload window for
    this request only (a 20 MB file on a slow mobile link).
  - The OpenAPI validator skips body validation for this route (kin-openapi would read the
    whole file into memory); its query parameters are still validated.
  - The old `upload-url` and `confirm` endpoints stay for compatibility, but no client uses them
    any more.
- **Web `/chat`:** `sendAttachment` sends the File to `/api/v1/media/upload` same-origin (cookie
  + CSRF via the generated client), then sends the message. The browser never contacts storage.
  `proxy.ts` skips `/api`, so Next does not buffer the body; the dev rewrite streams it.
- **App:**
  - Device files stream from disk with `uploadAsync` to the api (bearer + `X-Kushol-Client:
    mobile`). A token about to expire is rotated first, and a 401 rotates once and retries.
  - Test bytes go through `liveAuth()`.
- **Downloads are unchanged:** the viewer still gets a 15-minute presigned GET link, so an R2 URL
  is visible when a file is opened (G-24).

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build` · `go vet ./...` (+ `-tags integration` on chat/media) · `go test ./...` | clean / all ok — new `internal/media/upload_test.go` (PUT shape + exact bytes, URL redaction, 7 rejections before storage, Content-Length required) |
| api | golangci-lint media/httpx · `make contracts-check` | gofmt-on-CRLF artefacts only (untouched files) · no drift |
| api | `TestIT019ProxiedUpload` (new) | **pending owner run** (`make test-integration`) |
| web | typecheck · eslint · prettier (touched) · vitest full | clean · 254/254 — new `lib/chat/upload.test.ts` (same-origin upload, octet-stream body, no storage call) |
| app | typecheck · eslint · prettier (touched) · jest full | clean · 365/366 — new `lib/chat/upload.test.ts`; the one failure is the pre-existing `src/__tests__/index.test.tsx` (G-8) |

Owner steps: restart the stack (`applications/dev-stop.sh && applications/dev-start.sh`, so the
api picks up the R2 values from `api/.env`), then retry the upload. No bucket CORS is needed for
uploads any more.

## Mobile web, captions, polls, KLIPY GIFs + stickers, group settings — 2026-10-18

Owner request:
1. Make the web responsive, with the sidebar as a drawer on phones.
2. On mobile `/chat`, open the conversation, not group info.
3. WhatsApp-style captions on images and documents (web and app).
4. Fix create poll.
5. Add stickers. Mid-run: "use klipy for stickers, gif".
6. The group-info Settings button should open a popup for the photo, the name (Kushol admin only) and the description.

### Decisions (ADR-21 … ADR-24)

- **ADR-21 — KLIPY from the client.** KLIPY's integration requirements forbid routing KLIPY requests through partner servers and re-hosting media, and they require a "Search KLIPY" placeholder. So:
  - The api hands each signed-in user the app key, an opaque customer id (`sha256("kushol-klipy:"+userId)`, 32 hex) and the request params (`locale=bd`, `content_filter=high` for a school audience) via `GET /api/v1/chat/klipy`.
  - Web and app call `api.klipy.com` themselves and load media straight from KLIPY.
  - A sent GIF/sticker is stored as a reference only: `chat_messages.klipy {slug, title, url, width, height}`, kinds `gif` and `sticker`.
  - The api accepts only https URLs on `static.klipy.com`, `static1.klipy.com` and `static2.klipy.com`, so no client can make others load an arbitrary URL (tracking pixels).
  - The share trigger is posted from the client after a send.
  - The key is a client key by design (it travels in KLIPY request paths), not a server secret: `KLIPY_APP_KEY` in `api.env`. Unset means the GIF/Sticker tabs stay hidden.
- **ADR-22 — GIF renditions.** Clients send KLIPY's GIF rendition (GIFs `md`, stickers `sm`). It animates in every browser and in React Native on both platforms. The Android build keeps animated WebP off (`android/gradle.properties` `expo.webp.animated=false`), so WebP would show one frame. The web picker grid still loads the lighter WebP previews.
- **ADR-23 — group settings rights (owner).**
  - Name: Kushol admins (`super_admin`) only, on custom groups including the managed ones. Official class groups keep the section's name.
  - Photo and description: group owner/moderator, the School Admin or a Kushol admin.
  - Every check runs before the first write (one transaction), so a refused rename leaves the description unchanged.
  - The photo is a confirmed image the caller uploaded (`POST /media/upload?kind=image`), stored in `chat_groups.photo_asset_id`. Members fetch it like attachments (download URL); `AuthorizeAsset` admits members of the group using it.
  - School admins and group owners can no longer rename (the earlier rule).
- **ADR-24 — mobile `/chat` layout.** Group info sits beside the chat only from 1280 px (`xl`), where it starts open. Below that it is an overlay that starts closed, so phones land on the conversation. Picking another chat on a narrow screen closes it again.

### Defect fixed — "create poll is not working"

The REST `POST /chat/messages` handler (and the WS `message.send` frame decoder) never read the `poll` object. Every poll reached `Send` with `Poll == nil` and failed "poll needs a question and 2–6 distinct options". Both now decode it (and `klipy`).

The web poll dialog was also rebuilt:
- 2–6 options with add/remove and "Allow multiple answers".
- The api's rules are checked before sending (question 3–200 chars, options 1–80 chars, distinct).
- Bubbles show "Select one / Select one or more · N votes".

The app had no poll support at all. It now renders polls (tallies, my vote, tap to vote via `POST …/poll/vote`) and composes them from the attach sheet.

### What changed

- **api:**
  - Migration `20270308090000_com_chat_klipy_group_photo`: `chat_messages.klipy` + kinds `gif`/`sticker` + content/klipy checks; `chat_groups.photo_asset_id` + index.
  - `internal/chat/klipy.go` (reference type, host allowlist, customer id, config).
  - `UpdateGroup(GroupEdit{Name, Description, PhotoAssetID})` replaces `RenameGroup`. It audits `chat_group.renamed`.
  - `CanEditGroupInfo` / `CanRenameGroup`.
  - Forward copies the KLIPY reference.
  - Tombstones drop it.
  - `KLIPY_APP_KEY` config + `GetChatKlipyConfig`.
  - OpenAPI:
    - `GET /chat/klipy`.
    - `ChatKlipyMedia` / `ChatKlipyConfig`.
    - `klipy` on messages and sends.
    - `photoAssetId` on `ChatGroup` and the PATCH.
    - Kinds `gif`/`sticker`.
- **web:**
  - **Shell:** below `md`, a top-bar menu button opens the nav as a left drawer that closes on navigation. The title and actions shrink, and the persona switcher moves into the drawer below `lg`.
  - **Chat layout:**
    - Group info is an overlay below `xl` (ADR-24).
    - Paddings are tighter on phones.
    - A back button returns to the list.
  - **Attachments:** picking or pasting a file opens a WhatsApp send preview (photo or document card) with "Add a caption…". Composer text starts as the caption.
  - **Composer panel:** an Emoji · GIFs · Stickers panel (KLIPY, "Search KLIPY", "Powered by KLIPY", infinite scroll); GIF and Sticker tiles in the attach menu. GIFs render in the bubble with a badge; stickers render without a bubble.
  - **Group settings dialog:** photo change/remove, name (read-only with the reason for non-Kushol admins), description. The pencil on the description opens it too.
  - Group photos in the list, header, info panel and forward dialog.
  - Test setup: `matchMedia` stub guard fixed (this jsdom declares it undefined).
- **app:**
  - Caption sheet before every photo/document upload.
  - KLIPY picker sheet (GIFs/Stickers tabs, search, load more). The emoji sticker set remains when KLIPY is off or in demo.
  - Poll sheet and poll bubble.
  - GIF/sticker bubbles.
  - Group photos in avatars (list, header, info, forward).
  - Group description in chat info.
  - bn/en keys.

### Migrations (Gate 2 — owner runs)

`20270308090000_com_chat_klipy_group_photo` (local `dev-start.sh` applies it). Production: `ops/migrate.sh <api tag> up --confirm` after the next api image is built.

### Evidence (agent-side checks — no app, no containers)

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` · `go vet` (chat, config, cmd; `-tags integration` on chat) · `golangci-lint` · `make contracts` | clean · 0 issues · regenerated |
| api | `go test ./internal/chat/... ./internal/config/... ./internal/media/...` | ok — new `klipy_test.go`: host allowlist incl. look-alike hosts, userinfo, ports; customer id; WS frame decoding of poll/klipy; settings rules |
| api | `TestIT020PollsKlipyGroupSettings` (new): REST poll body, GIF history/list/forward, foreign host refused, rename rights, photo set/clear, a refused field writes nothing, photo visible to members only | **pending owner run** (`make test-integration`) |
| web | `tsc` (sources) · eslint (touched) · prettier (touched) · vitest full | clean · clean · clean · 276/276. New: `klipy.test.ts`, `poll.test.ts`, mapping tests, `admin-messenger-features.test.tsx` (narrow layout, poll, caption preview, settings), `admin-shell.test.tsx` (drawer) |
| web | `pnpm typecheck` / `pnpm lint` (whole repo) | blocked by files outside this change: stale `.next/dev/types/*.d.ts` written by a running dev server (syntax errors), and pre-existing lint errors in `app/admin/audit/audit-page-client.tsx` + `hooks/use-auth-mutations.ts` |
| app | `tsc` · eslint (touched) · jest full | clean · clean · 383/384. New: `chat-rich-messages.test.tsx` (poll bubble + vote, KLIPY GIF/sticker, poll sheet, caption sheet), `klipy.test.ts`, `poll.test.ts`. The one failure is the pre-existing `src/__tests__/index.test.tsx` (G-8); whole-repo eslint still flags untouched `media-viewer.tsx`, `(tabs)/_layout.tsx`, `floating-tab-bar.test.tsx`, `glass-surface.test.tsx` |
| docs | `host/set-api-env.sh` KLIPY group: `bash -n`, `--from-stdin` with a fake key, the 16 earlier stdin checks | ok — key written in place, masked in output |

### Gate hand-off (owner)

1. **KLIPY key:** create an app key at partner.klipy.com → API Keys. Set `KLIPY_APP_KEY` in `applications/api/.env` and, for production, `env/api.env` (the `set-api-env.sh` KLIPY group). Restart the api. Request production access in the KLIPY Partner Panel before launch, and set content filtering there too (G-27).
2. Run migration `20270308090000` (local: `dev-start.sh`; production: Gate 2).
3. `cd applications/api && make test-integration` (IT017–IT020).
4. **Gate 1 UI review:**
   - Phone-width web: drawer, `/chat` lands on the conversation.
   - Caption preview.
   - Poll dialog.
   - GIF/sticker panel.
   - Group settings (as a Kushol admin and as a school admin).
   - App: caption sheet, poll sheet/bubble, KLIPY sheet; needs a rebuilt dev client only if native modules changed. None were added.

## G-28 closed — "Edit group" on the app — 2026-10-18

Follow-up to the web group settings dialog above: the app's chat info now edits a group too, with the same rights (ADR-23) and the same `PATCH /api/v1/chat/groups/{groupId}`. No api, OpenAPI or migration change (the app's `schema.gen.ts` already had `photoAssetId`).

### What changed (app only)

- **Chat info** (`channel-header.tsx` `ChatInfoSheet`): groups show an **Edit group** button when the account may change something. Rights come from the cached group row (`myRole`) and the account role (`me.role`). DMs, archived groups and plain members get no button.
- **Group settings sheet** (new `group-settings-sheet.tsx`, the web dialog's layout):
  - The photo with a camera badge (change) and **Remove photo**. Live sessions open the system photo picker (`pickImage()`, ≤ 10 MB); demo sessions use the bundled demo picture.
  - The name. Editable for Kushol admins on custom groups. Otherwise it is read-only with the reason: "Only Kushol admins can change the group name", or "Class group names follow their section" for a Kushol admin on an official group.
  - The description (≤ 500, counter), with Cancel and Save.
  - Save is off until something changed. It sends only the changed fields, trimmed. A name outside 3–60 code points is refused before sending.
- **Save** (new `lib/chat/group-settings.ts`):
  - A new photo is uploaded first with `uploadMedia()` (kind `image`); its confirmed asset id goes in `photoAssetId`. Removing sends `photoAssetId: ""`, and an empty description sends `""`.
  - On success, `chatKeys.groups` and the `["chat_group_photo"]` queries are invalidated, so the title, the description in chat info and every group avatar refresh. A toast confirms. Failures toast: CONFLICT → "Another club already uses this name", FORBIDDEN → "Not allowed", anything else → "Couldn't save the group settings". On a failure the sheet stays open.
  - The rules live in `groupSettingsRights`, which mirrors `CanRenameGroup` / `CanEditGroupInfo`. The api re-checks every field.
- **Seam:**
  - `liveChat.updateChatGroup`: the PATCH through the generated client.
  - `fixtures/chat.ts` `updateChatGroup`: the demo checks the api's shape rules (no dm settings, archived → CONFLICT, name on custom only, 3–60 / ≤ 500, name clash → CONFLICT, image asset) and emits `group.updated`. `resetChatFixtures` restores the seeded names.
- **i18n:** 17 `chat.settings.*` keys in bn and en.
- **Scope note:** `group-chat-screen.tsx` is unchanged. `ChatInfoSheet` reads the group row from the chat list itself; for groups, its `avatarId` is the group id. This kept the change out of the screen while another session works there.

### Evidence (agent-side checks — no app, no containers)

| Check | Result |
| --- | --- |
| `npx tsc --noEmit` | clean |
| eslint `--max-warnings=0` + prettier `--check` on the touched files | clean |
| jest: `lib/chat/group-settings.test.ts` (new) | rights for Kushol admin / official group / owner / moderator / School Admin / member / dm / archived; the draft keeps only the changed fields; name length in code points; demo save: photo upload → the PATCH carries the confirmed image asset id; `""` removes the photo and clears the description; rename on custom only; reset; save-error copy |
| jest: `components/chat/group-settings-sheet.test.tsx` (new) | the sheet: rename + description payload; read-only name with the reason (group admin, official group); pick a photo → `photo` in the payload; remove → `photo: null`; short name refused; a failed save stays open. From chat info via the real `/groups/[id]` route: the moderator edits the description and chat info shows it; a Kushol admin renames a club and the header title follows; no Edit group for a plain member or in a DM |
| jest full suite | 405/406 — the one failure is the pre-existing `src/__tests__/index.test.tsx` (G-8) |

### Gate hand-off (owner)

Gate 1 on a phone (dev client, live api). No native module was added (`expo-image-picker` was already in the build):
1. **As a teacher who moderates a class group:** Chat info → Edit group. Change the photo (system picker) and the description, then Save. Check that the list, the header and the info avatar show the new photo. The name stays read-only with the reason.
2. **As a School Admin on a club where they are a plain member:** photo and description are editable; the name is not.
3. **As a Kushol admin (`super_admin`):** rename a custom group. On an official group the name stays read-only ("Class group names follow their section").
4. Remove a photo and clear a description. Both disappear for the other members after their list refreshes (`group.updated`).

### 2026-10-18 run — @mentions + starred messages (owner instruction, Stage 1 pre-approved)

Additive extension (G-9 closure pattern). **api**: migration `20270309090000_com_chat_mentions_stars`
(`chat_messages.mentions uuid[]` + private `chat_message_stars`); OpenAPI `PUT/DELETE
/chat/messages/{messageId}/star` + `GET /chat/starred` (#23–#25) and `mentions` on
`ChatMessageSendInput`/`ChatMessage`; sqlc `chat_stars.sql` + oapi regen; `chat.NormalizeMentions`
(dedupe, drop sender/non-members, cap 20 — unit-pinned in `mentions_test.go`); star services
(`stars.go`) re-check live membership on every list; mention pushes via a `MentionPusher` port
bound to 06's frozen `SendToUser` in `cmd/api` (`chat_mention` / class `chat` / mute respected).
**web** (`/chat`): composer "@" roster picker, mention highlight in bubbles, Star/Unstar in the ⋮
menu (`message-actions` unit-pinned), star badge on bubbles, "Starred messages" card in the group
info panel with jump-to-message; spec synced + client regenerated.
**app**: composer "@" picker (`listChatGroupMembers` seam), Star/Unstar in the focus menu,
"Starred messages" in the chat info sheet, bn/en keys; spec synced + client regenerated.
**ADR-21**: stars are private per-user bookmarks — no WS event, no push, invisible to others;
unfollow = membership loss filters the list (not a delete cascade).
**Evidence**: api `go build`/`go vet`/`gofmt` clean, chat+notify unit tests green (unit pins for
NormalizeMentions/carriesBody); web typecheck clean, 277/277 vitest, lint clean on touched files;
app targeted chat unit suites 50/50 green (typecheck has pre-existing failures from the parallel
session's in-flight edits — none in files this run touched); contracts: web+app `sync:api-spec`
+ `generate:api` against the updated spec.
**Deferred to 08-gaps G-31**: app bubble star badge + @-highlight rendering (parallel-session
collision), mentions-cap confirmation, IT suite run.
**Gates**: Gate 1 (UI) + Gate 2 (SQL) + Gate 3 (flows) pending owner.

**Completion pass, same day (owner: "complete all todos")**: the deferred app bubble polish
landed — star badge in the bubble meta row + @-mention highlight rendering
(`mentionSegments`/`escapeRegExp`, unit-pinned in `message-bubble.test.tsx`; screen passes
`starred` + `mentionNames` from the roster) — and the integration tests were written
(`it_mentions_stars_test.go`, `COM-IT-010/011`, integration-tagged, `go vet -tags=integration`
clean). Evidence: app chat suites 22/22 green (bubble + screen + list), api build/vet/gofmt +
unit tests green, zero new typecheck errors in touched app files (the app tree still carries the
parallel session's pre-existing catalog-key failures). Remaining owner-only: confirm the
20-mention cap (G-31a) and run the container IT suite + the three gates.

**Realtime on the VPS, 2026-10-20 (owner: "real time user online, message typing, message update
not happening")**: presence, typing and live message updates all ride the one gateway socket.
Most likely cause for the web: the site domain's Nginx template got its `location = /api/v1/ws`
only on 2026-10-20 (docs `33d5f0c`). Until `hestia/setup-web.sh` re-renders the vhost, the browser's
same-origin upgrade goes through the plain `/api/` route, which drops `Upgrade`/`Connection`, so
the handshake fails. Hardening landed in the clients and api:

- **App:** the socket rotates an expired access token before every (re)dial. The gateway checks
  the bearer only at the handshake, so after 15 minutes every reconnect failed until some REST
  call rotated. A start guard stops concurrent subscribers from opening two sockets.
- **App and web:** a stale-link watchdog drops and re-dials a socket that has sent nothing for
  60 s (no `pong` to two pings) instead of sitting "online" while every event is lost.
- **Web:** the open conversation polls every 5 s while the socket is not online.
- **Api:** the "gateway: upgrade failed" log now carries host, origin and a proxy hint when the
  upgrade headers never arrived.
- **Ops:** `ops/smoke.sh` warns, never fails, when an installed Kushol template is missing a route
  the bundle's copy has.

Evidence:
- Api: build, vet, gateway tests and golangci-lint all clean (0 issues). Also removed the unused
  `presenceRoomKey`.
- Web: chat vitest 72/72.
- App: `ws-client` jest 6/6; tsc and eslint clean.
- `bash -n` on smoke.sh passes; its template check was exercised against an old and a current
  template.

Server verification and the template re-apply are owner steps (G-32).

**Member photos in chat, 2026-10-20**:
- The api now gives every chat payload the same stable photo path (`userdto.AvatarPath`):
  `senderAvatarUrl` on messages and WS frames, `peer.avatarUrl` (DM list rows and the
  conversation header), member `avatarUrl` (group info) and contact `avatarUrl` (pickers). All are
  now in the contract; web and app types are regenerated, and the app spec copy is re-synced.
- The committed sqlc output had been hand-edited (`…AvatarURL` vs the generator's `…AvatarUrl`).
  It is regenerated and `make contracts-check` passes.
- The app's group info sheet now lists members with their photos.
- Root cause of the missing photos: they never reached the server. See 03 07-progress, same date.
