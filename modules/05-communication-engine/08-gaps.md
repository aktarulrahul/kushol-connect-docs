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
