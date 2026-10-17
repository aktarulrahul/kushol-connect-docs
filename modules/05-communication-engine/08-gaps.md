# 05-communication-engine — Remaining Gaps

Genuine gaps only — reason · impact · next action. Created 2026-10-02.

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Maestro runs pending owner | Maestro CLI/device unavailable in the build env (standing rule: agent never runs the app) | E2E unproven on device | Owner: `maestro test .maestro/communication-chat-send.yaml` (+ the other two specs) |
| ~~G-2~~ | **CLOSED 2026-10-03** — 06 built and bound `chat.Broadcaster` in `cmd/api` | — | notice publishes now fan out through the real FCM topic path (bindings-guarded) | — |
| G-3 | Offline queue is memory-only (MMKV persistence + cold-start replay deferred) | Stage-2 precedent (module 03/04): persistence lands with integration | A killed app loses queued sends | Wire MMKV-backed queue in Stage 5 (COM-AP-017 completion) |
| G-4 | Real media device flows (expo-image-manipulator, expo-av recording, expo-document-picker) | Stage-2 fixtures simulate bytes/caps; the pipeline shape + error paths are the real contract | Device flows unproven until integration | Swap the pipeline internals in Stage 5; screens unchanged |
| G-5 | Club approval UI (School Admin queue) | Endpoint + service shipped; the queue screen is module 07's admin console | Clubs stay `pending_approval` until 07 lands | 07 consumes `POST /chat/groups/{id}/approve` |
| G-6 | Integration tests are written but **pending owner run** (container suite) | Standing rule: agent never runs the app/containers | IT proof outstanding | Owner: `cd applications/api && make test-integration` after Gate 2 |
| G-8 | src/__tests__/index.test.tsx fails (pre-existing, observed during the 05 run) | 03's auth-store now boots idle until restore runs; the test renders <Index/> directly and expects the anon holding screen | DSN-IT-002 red in pnpm test | 03 owner-flow: seed the store as non in the test (or gate on restore) — unrelated to chat |
| G-9 | Console messenger affordances without api endpoints (reactions, polls, explore discovery/join, forward, rename, message pin/edit, per-message seen-by, asset galleries) + app message edit/pin/seen-by/sticker-kind | Spec grew chat CRUD/realtime but not these; ADR-3 forbids restructuring the shipped screens to hide them | In live sessions those actions surface a typed NOT_IN_LIVE/ConsoleNotAvailableError (toast) instead of silent no-ops; stickers degrade to emoji-as-text | Owner decision: additive endpoints (spec change → re-run codegen) vs trimmed console UI; then remove the typed errors |
| G-10 | App attach sheet still uploads demo magic-bytes in live sessions | ADR-3: the shipped chat screen hardcodes DEMO_MAGIC picks; real pickers (document/image/audio) were never wired | Live media sends are blocked with VALIDATION_FAILED real_file_required (no corrupt uploads) | Wire expo-document-picker/image-picker/audio recording into the attach handlers passing full ytes + mime (the live pipeline already accepts them) |

**G-9 CLOSED 2026-10-16** — the api grew the missing surface additively (owner instruction:
"implement the all required backend"): reactions (toggle), poll kind + votes, message edit
(author-only), pin (CanPin), per-message seen-by, forward, club rename, explore + join, group
asset gallery — OpenAPI 05-rich-paths + migration `20261016090000_com_chat_rich_messages` +
sqlc/oapi regen; web console + app seams consume them (ConsoleNotAvailableError/NOT_IN_LIVE
removed from those paths). **Still open inside G-9/G-10**: app attach sheet real file pickers
(ADR-3 screens — live pipeline rejects demo magic-bytes by design) and web gallery file names
(placeholders until media file_name is persisted).

### 2026-10-17 run (WhatsApp-like `/chat` + app, auto groups, R2 attachments)

**G-10 CLOSED in code 2026-10-17** — live sessions use the real pickers (`expo-image-picker`,
`expo-document-picker`) and recorder (`expo-audio`), streaming the file to R2; device
verification is part of the gate hand-off in `07-progress.md` (needs the rebuilt dev client).

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-6 | (updated) Two more integration tests are written and pending owner run | Standing rule: the agent never runs containers | Managed-group provisioning, poll insert, read horizon and leave are proven only by unit pins + code | Owner: `cd applications/api && make test-integration` (`TestIT015ManagedGroups`, `TestIT016PollsHistoryAndGroupLifecycle`, `TestIT017ReceiptsReactionsForwardReply`) |
| ~~G-11~~ | **CLOSED 2026-10-17** — confirm reads the real stored size and rejects empty/over-cap uploads (see 07-progress). Was: R2 presigned PUT signs only `host`; confirm sniffed the first 512 bytes but never checked the stored object's size | Pre-existing media design (05 Stage 4) | A modified client could upload more than the declared size/cap | Confirm should read the object size (Range response `Content-Range` total or a HEAD) and reject over-cap uploads; consider signing `content-length` |
| G-12 | R2 bucket CORS for browser uploads/downloads | Bucket configuration is owner-side (Cloudflare dashboard) | Web `/chat` attachments fail with "Upload failed" until set | Owner: R2 bucket → Settings → CORS: allow origins `http://localhost:4433`, `https://kusholconnect.com` (+ `https://www.kusholconnect.com` if used), methods `PUT, GET`, headers `Content-Type`, max-age 3600 |
| G-13 | Production Nginx must proxy WebSocket upgrades on the **site host's** `/api/v1/ws` (and the api host's path is `/api/v1/ws`, not `/ws` as 15's spec says) | Module 15 owns the Nginx config (not edited here) | Web `/chat` realtime (typing, live messages, ticks) would fall back to the 10 s list poll in production | Module 15: add `Upgrade`/`Connection` headers + `proxy_read_timeout 300s` on `location /api/v1/ws` for both hosts |
| G-14 | Android in-app PDF viewing sends the short-lived R2 URL to the Google Docs viewer | Pre-existing media-viewer approach (Android WebView cannot render PDFs) | A third party receives a working (15-min) link to a school document | Open PDFs with the system viewer (`Linking.openURL`, as Word/Excel/CSV now do) or bundle a local renderer — owner decision |
| G-15 | Web history shows the newest 100 messages (no scroll-back paging yet) | Scope of this run; the api already pages with `before` | Very old messages in busy groups are not reachable on the web | Add "load earlier" using `nextBefore` in the console seam |
| G-16 | No push notification for new chat messages (only notices push today) | 06 owns FCM fan-out; chat → push wiring was never specified | Offline members learn of messages only when they open the app | Owner decision for 06: per-group mute + push for DMs/mentions (WhatsApp default) |
| G-17 | Web cannot record voice notes (browsers record webm/ogg; the sniff accepts AAC/m4a only) | R2 voice kind is AAC-only by design (INV-6) | Web users can play voice notes and upload .m4a/.aac files, not record | Accept `audio/webm;codecs=opus` as a voice kind (sniff `1A 45 DF A3`) or transcode server-side — owner decision |
| G-18 | `TODO: Confirm` — the per-institution staff group (ADR-9) is an interpretation of "chat group will be created automatically" | The instruction named the Kushol Admin group explicitly; section groups already existed | If unwanted, institution admins have no auto group on the web | Rahul to confirm; removing it is one `ProvisionAll`/`autoProvision` branch |
| G-19 | `go test -race` not run for this change | This Windows host has no C compiler (cgo) | Data-race detection outstanding (the gateway's write lock is the main concurrency change; a concurrent-publish unit pin passes) | Owner/CI: `cd applications/api && make test` |
| G-20 | Receipt fan-out grows with group size² (every member's `message.delivered`/`message.read` goes to the whole room) | Same pattern as the existing `message.read`; clients coalesce refetches (800 ms) | Large online groups (300+) generate many small frames per message | Publish only when the room's delivered/read horizon moves (store it on `chat_groups`, conditional update), or send receipts to the sender's user room |
| G-21 | No push/notification when someone reacts to my message | 06 owns notifications; not specified | Authors see reactions only when they open the chat | Owner decision with G-16 |
| G-22 | App has no Copy action in the message menu | Needs the `expo-clipboard` native module (dev-client rebuild); not in this request | Copy works on web only | Add `expo-clipboard` and a Copy row when the owner wants it |
| G-23 | App read ticks stay white on the teal bubble (sent/delivered dimmed) instead of WhatsApp blue | The design tokens have no blue; one-off hex values are banned (DSN-INT-002) | Read vs delivered differs by brightness, not hue | Owner/design: add a receipt token (e.g. `#53BDEB`, ≥ 3:1 on teal-800) if blue is wanted |
