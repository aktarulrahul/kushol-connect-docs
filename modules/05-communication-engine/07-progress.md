# 05-communication-engine — Build Progress

Module: communication-engine · Surfaces: api + app (web N/A — 07 builds the composer on these
endpoints) · Repos: `applications/api`, `applications/app` (branch `module/03-identity-access`
working tree — ADR-4) · **Last updated:** 2026-10-09

> Note: the build prompt parameter `TODAY=2026-10-01` lags the actual build date; dates are
> recorded truthfully as 2026-10-02 (same convention as module 04).

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ approved 2026-10-02 | owner: "proceed" with recommended options |
| 2 UI (app, mock-driven) | ✅ 2026-10-02 | COM-AP-001…019 on fixtures; app gate green (lint · typecheck · unit 176/176) |
| Gate 1 (UI approval) | ⏳ pending owner — UI reviewable per the hand-off below (owner later instructed to continue building: "complete the pending tasks", 2026-10-02 — recorded, gate still owner-run) |
| 3 Docs sync | ✅ 2026-10-02 | this file, `08-gaps.md`, README row → 🚧, checklist ticks, change log |
| 4 Backend | ✅ code-complete 2026-10-02 (migrations · services · gateway · exports · handlers · wiring · unit tests) — Gate 2 hand-off below | evidence table |
| Gate 2 (SQL on Neon) | ⏳ pending owner — runs **01 → 03 → 04 → 05** blocks in order | — |
| 5 Integration | ⏳ after Gate 2 | WS gateway live wiring, real R2, push binding with 06, fixture swap |
| Gate 3 (integrated flows) | ⏳ pending | — |
| 6 Gaps & verification | 🚧 | `08-gaps.md` |

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

| Repo | Check | Result |
| --- | --- | --- |
| api | `openapi.yaml` + `make contracts` | 22 chat/notices/media paths + WS contract (#21 download-url, #22 club-approve added — ADR-6/7); `contracts: no drift` |
| api | `go build ./...` + `go vet ./...` (+ `-tags=integration` on chat) | clean, 2026-10-02 |
| api | `make fmt-check` (gofmt + goimports -local) | clean |
| api | golangci-lint `./...` | 0 issues in 05 code (1 pre-existing errcheck in 03's uncommitted `smsout.go` WIP — not 05's) |
| api | `go test -race ./...` (unit) | **22/22 packages ok** (chat guards + media sniffer/SigV4 + WS-app state machine) |
| api | `gorilla/websocket v1.5.3` pinned | go.mod (tech-stack latest-verify: gorilla/websocket current stable 1.5.3) |
| api | COM-IT tests written | `it_chat_test.go`: seam idempotency, idempotent send, request lifecycle, notice board matrix, media sniff/authz — **pending owner run** (`make test-integration`, G-6) |
| api | 2026-10-09 owner `make test-integration` run 1 | COM-IT-002 (IT011) / COM-IT-003 (IT012) / COM-IT-005 (IT013) failed — **fixed 2026-10-09, re-run pending owner** (see fix log below) |
| wiring | `cmd/api` | real hierarchy service replaces the demo fake (04 entry-point item done: DB-backed pickers + BR-01 seam); chat ⇄ hierarchy mutual binding via `SetHierarchy`; hub on `GET /api/v1/ws` with JWT + verified gate + server-resolved rooms; jobs `chat.request_expiry`, `media.archival`, `media.pending_cleanup` registered; R2 gated by `R2_*` env (501s cleanly when unset) |
| app | `pnpm lint && pnpm typecheck && pnpm test` | clean · clean · **176/176** (incl. WS-client state machine 4/4, i18n parity 13/13) |
| app | 2026-10-09 Spartens chat/channel (ADR-9): `tsc` · eslint (changed files) · `jest` | clean · clean · **313/314** — the one failure is the pre-existing `src/__tests__/index.test.tsx` holding-screen test (failed before this change too); +41 tests (list filter, message utils, chat-state prefs, fixture edit/pin, menu placement, row/bubble/composer/menu, screen smoke) · `test:rules` 10/10 · `contracts: no drift` |
| app | Maestro specs | `.maestro/communication-{chat-send,offline-replay,notices}.yaml` written; **runs pending owner** (no CLI/device here — G-6) |

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

## Spartens chat/channel review hand-off (owner, on device — 2026-10-09, ADR-9)

```sh
cd applications/app && pnpm ios   # or pnpm android — dev build (no new native modules)
```

1. **Chat tab**: search pill filters as you type; chips All · Unread · Official · Community · DMs;
   long-press a row → Pin this chat (pinned rows rise, max 5) / Notification settings → None shows
   the bell-off mark; type in a room, go back → the row shows "Draft: …"; pull to refresh; "+" FAB
   opens New club.
2. **Room** `দশম শ্রেণি · বিজ্ঞান (ডেমো)`: pinned bar (syllabus PDF) → tap jumps + highlights; "N new
   unread messages" pill; swipe an incoming bubble right / own bubble left → reply quote; tap a
   quote → jumps to the original; long-press → blurred room, lifted bubble, reactions, Reply / Edit
   (own text) / Pin / Message info (own) / Delete (confirm); scroll up → jump-to-latest button;
   send 👍 → large emoji; demo peer typing pill; header → Chat info sheet.
3. **States**: `/dev/chat-fixtures` offline / send-failed (tap the red bubble to resend).
4. Check 360px, bn + en, iOS keyboard (composer stays above it), Android back closes menus.

## Fix log — 2026-10-09 (owner `make test-integration` run 1 failures)

Root causes + fixes (agent-side checks green: `go build` · `go vet` · golangci-lint 0 issues ·
`go test -race` unit ok · `-tags=integration` compiles; suite re-run **pending owner** — G-6):

1. **COM-IT-003 (IT012)** — accept-creates-DM-room hit `chat_groups_status_chk`: the sqlc
   `InsertChatGroup` inserts `status` explicitly, so the DM inserts passed the Go zero value.
   Fix: `Status: GroupActive` on both DM inserts (`dm.go` OpenDM, `requests.go` AcceptMessageRequest).
2. **COM-IT-005 (IT013)** — `PublishNotice` panicked on the nil `HierarchyPort` (harness wires no
   port). Fix: shared nil-safe `loadSection` helper (port when wired, direct DB read otherwise —
   the pattern `JoinSectionGroups` already had); `JoinSectionGroups` refactored onto it.
3. **COM-IT-002 (IT011)** — the test addressed the send by section id; messages are addressed by
   group id everywhere else (REST contract, history, WS frames). Fix: test resolves the official
   group (`GetOfficialGroupBySection`) and sends `group.ID`.
