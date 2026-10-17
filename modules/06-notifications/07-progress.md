# 06-notifications — Build Progress

Module: notifications · Surfaces: api + app (web N/A by design — all `04` sections declare N/A) ·
Repos: `applications/api`, `applications/app` · **Last updated:** 2026-10-15

> The build prompt's `TODAY=2026-10-01` lags the actual date; recorded truthfully as 2026-10-03.

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ approved 2026-10-02 | owner: "go ahead" (Conflict-2 default: header badge, tab bar untouched; Conflict-3: FCM SDK pinned after docs check) |
| 2 UI (app, mock-driven) | ✅ 2026-10-02 | NTF-AP-001…011 on fixtures; my files lint-clean · tsc green · notifications unit tests 14/14 |
| Gate 1 (UI approval) | ✅ owner 2026-10-15 | owner approved in session ("complete all from Gate 1"); 360px bn/en device pass still recommended (rides the app device run, G-1) |
| 3 Docs sync | ✅ 2026-10-02, refreshed 2026-10-03 · checklist sync 2026-10-15 | this file, `08-gaps.md`, README → 🚧, checklist ticks (`03` §7, `05` §7, `06` §10), change log; `NTF-BE-023` recorded as deferred (G-5) |
| 4 Backend | ✅ code-complete 2026-10-02/03 | evidence table + Gate 2 hand-off below |
| Gate 2 (SQL on Neon) | ✅ owner | 2026-10-09 — all migrations applied to Neon via 15's first deploy (`v0 → 20270302090001 dirty=false`), covers block `20261006090001–090002` |
| 5 Integration | ✅ code-complete 2026-10-03 | app live client + selector, FCM token via `getDevicePushTokenAsync`, runtime attached; contracts re-synced `no drift`; IT/E2E runs pending owner |
| Gate 3 | ⏳ pending | — |

## Owner decisions (2026-10-02) — ADR

1. **ADR-1 (standing):** the agent never runs the app — container/live work is owner-run (workspace `AGENTS.md`).
2. **ADR-2 (owner, module-06 run): "DO NOT CHANGE the existing chat screen and bottom menu."** NTF-AP-009's tab badge → the unread state stays on the notices surfaces outside the tab bar; deep links/primer/settings/banner all live outside the frozen surfaces. The chat screen and floating tab bar files are untouched by this module's diff.
3. **ADR-3:** token model = native FCM per `03 §1.1` (Expo tokens rejected) with channels/permissions via expo-notifications (`NTF-AP-001`'s own pairing). Both sides of the spec respected.
4. **ADR-4:** 06's real `notify` service binds 05's `chat.Broadcaster` port in `cmd/api` (closing 05 `08-gaps` G-2) — the planned one-line cross-module binding.
5. **Pre-existing app test debt (NOT 06's):** `src/__tests__/index.test.tsx` fails on the committed tree (verified by stash) — owned by the parallel 05 continuation; three committed files carry lint debt (`src/app/(modals)/media-viewer.tsx`, `src/app/(tabs)/chat/index.tsx:151`, `src/components/chat/chrome.tsx:54`) — frozen surfaces, left untouched per ADR-2.

## Cross-module binding (2026-10-03)

06's real `notify.Service` binds 05's `chat.Broadcaster` port in `cmd/api`
(`chatSvc.SetNotify(notifySvc)`; mutual refs resolved by late-binding setters) — **05's G-2 is
closed**: notice publishes now fan out through the real topic path (bindings-guarded) instead of
the Noop. Notify's FCM client is env-gated (`FCM_SERVICE_ACCOUNT_JSON` + `FCM_PROJECT_ID`);
unset → degraded to in-app/WS (NTF §7 edge 4), jobs drain when configured.

## Stage 5 app integration (2026-10-03) — ADR

6. **ADR-6 (fixture/live selector):** `src/lib/notifications/backend.ts` is the one import
   surface; a live session (non-`access_demo_*` JWT, per `isFixtureAccessToken`) routes to the
   generated `openapi-fetch` client (`live.ts`), fixture sessions keep the Stage-2 seam. Fixtures
   stay behind the demo-session flag (allowed by the DoD "test-only flags" clause) so demo
   reviews and Maestro fixture mode keep working — mirrors the auth module's live/fixture split.
   Problem codes map to the seam vocabulary (`NotificationsApiError`: OFFLINE/NOT_FOUND/CONFLICT/…);
   404-on-delete and CONFLICT-on-opened resolve silently per `06` §6.
7. **ADR-7 (FCM token without new native deps):** the native FCM/APNs token comes from the
   already-installed expo-notifications `getDevicePushTokenAsync()` (SDK 57 returns the native
   FCM token on Android once the owner adds `google-services.json` / `GoogleService-Info.plist`)
   — this IS ADR-3's pairing, and it avoids `@react-native-firebase/*` autolinking breaking
   prebuild before the owner supplies the Firebase config (gap G-6). Absent config → token null →
   registration silently skipped (degraded, in-app still works, NTF §7 edge 4).
8. **Stage 5 app facts:** `NotificationsRuntime` mounted in `_layout.tsx` (foreground handler
   `shouldShowBanner/shouldShowList=false` — no tray duplicate; live foreground listener maps
   payload schema v1 to the banner; AppState heartbeat refreshes `last_seen_at`); primer gained
   the §2.1 class rows + permanent-denial OS-settings hint + row a11y grouping; settings gained
   whole-row ≥44 pt switch targets, bn/en status keys, localized history badges.

## Defaults relied on

OQ-1 none · OQ-2 3 channels · OQ-3 topics fire-and-forget / directed tracked · OQ-4 90-day prune
(config `NTF_PRUNE_DAYS`, default 90) · OQ-5 180-day retention (aggregate job deferred, gap G-4).

## Evidence

| Repo | Check | Result |
| --- | --- | --- |
| api | `openapi.yaml` + `make contracts` | 7 notification endpoints + payload schema v1; `contracts: no drift` |
| api | `go build ./...` + `go vet ./...` (+ `-tags=integration` on notify) | clean, 2026-10-03 |
| api | `make fmt-check` + `make contracts-check` | clean · `contracts: no drift` |
| api | golangci-lint `./...` | 0 issues in 06 code (only 03's pre-existing `smsout.go` errcheck WIP item remains repo-wide) |
| api | unit `go test -race ./internal/notify/` | NTF-UT-001–005 green (payload builder + privacy invariant, prefs/validation, opened guards, topic prefix guard, FCM redaction + SA-JWT shape); **repo-wide 23/23 packages ok** |
| api | NTF-IT-001–004, 006–008 written | `it_notify_test.go` (testcontainers + fake FCM) — **pending owner run** (`make test-integration`, G-1/G-2) |
| api | wiring `cmd/api` | notify service + handler; jobs `fanout.send` / `tokens.prune` / `topics.backfill` registered; `chat.Broadcaster` bound; AuthRequired covers `/notifications`, `/school|admin/notifications`; 10/h rule on the test-push route |
| api | lint/vet/fmt on 06 code | clean (repo-wide scan carries only the pre-existing 03 `smsout.go` errcheck item) |
| app | scoped lint + `pnpm typecheck` | clean · green (pre-existing debt listed in ADR-5, untouched) |
| app | `pnpm test --run src/lib/notifications` | **14/14** (channels, registration idempotency + verified gating, prefs flip, opened write-once, test-push validation, deep-link map + fallback) |
| app | `pnpm test --run src/lib/notifications` | **25/25** (was 14; +11 live-client/selector tests: problem mapping, 404-as-success delete, CONFLICT-silent opened, OFFLINE transport, fixture/live routing) — 2026-10-03 |
| app | Maestro specs | `.maestro/notifications-{pilot,deeplink}.yaml` — **runs pending owner** |
| app | scoped eslint (`--max-warnings=0`) on 06 files | clean · 2026-10-03 |
| app | `pnpm typecheck` | green · 2026-10-03 |
| app | `pnpm test` (full) | 235/236 — the 1 red is `src/__tests__/index.test.tsx`, pre-existing (G-3, 05 stream) |
| app | `sync:api-spec && generate:api` | app spec copy + `schema.gen.ts` regenerated; **matches api spec** (drift vs committed tree is the parallel 03/05 streams' new endpoints, not 06's) |
| api | `make contracts-check` | `contracts: no drift` · 2026-10-03 |
| api | `go build/vet ./internal/notify/...` + `gofmt` | clean · 2026-10-03 (repo-wide `go build` broken by the 04 stream's WIP `hierarchy.GetCity` — G-7, not 06's) |
| app | a11y §7 | static contrast: ink 17.1 · muted-600 7.3 · teal-800 7.7 · white-on-teal 8.0 · warning 4.85 (all ≥ AA); on-device bn/en verification rides Gate 1 |

## Gate 1 review hand-off (unchanged surfaces + this session's additions)

Fixtures: dev switcher (`ntfFixtureFlags`) still toggles success/offline/rate_limited/not_found for
the screens; live paths need the owner's stack. Screens: `/(modals)/notifications-primer` (3 class
rows, allow/denied/permanent-denied → OS settings), `/settings/notifications` (3 switches, device
row, admin test push, history). Review at 360 px in bn + en.

## Fix log — 2026-10-09 (owner `make test-integration` run 1 failure)

**NTF-IT-002 (TestIT002MuteAndPrune)** panicked in `subscribeBoundTopics`: `s.hierarchy` is nil
when the harness wires no 04 port, and the method called the nil interface. Fix: nil-guard returns
an error so `RegisterDevice` takes its existing degraded path (warn + `topics.backfill` enqueue)
instead of panicking. Agent-side checks green (build · vet · lint 0 · unit ok · `-tags=integration`
compiles); suite re-run **pending owner**.

**2026-10-09 (evening, owner-authorised run):** `make test-integration` fully green — 32 packages
ok. IT002 passes with the nil-hierarchy degrade; IT006's fake hierarchy now keys nodes by the
seeded caller id (it previously keyed a random uuid, so bound-topic resolution missed; the panic
in IT002 had been aborting the package before IT006 could assert).
