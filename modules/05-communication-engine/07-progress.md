# 05-communication-engine — Build Progress

Module: communication-engine · Surfaces: api + app (web N/A — 07 builds the composer on these
endpoints) · Repos: `applications/api`, `applications/app` (branch `module/03-identity-access`
working tree — ADR-4) · **Last updated:** 2026-10-02

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
| wiring | `cmd/api` | real hierarchy service replaces the demo fake (04 entry-point item done: DB-backed pickers + BR-01 seam); chat ⇄ hierarchy mutual binding via `SetHierarchy`; hub on `GET /api/v1/ws` with JWT + verified gate + server-resolved rooms; jobs `chat.request_expiry`, `media.archival`, `media.pending_cleanup` registered; R2 gated by `R2_*` env (501s cleanly when unset) |
| app | `pnpm lint && pnpm typecheck && pnpm test` | clean · clean · **176/176** (incl. WS-client state machine 4/4, i18n parity 13/13) |
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
