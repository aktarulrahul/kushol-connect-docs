# 06-notifications — Remaining Gaps

Genuine gaps only — reason · impact · next action. Created 2026-10-02.

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Maestro runs pending owner | Maestro CLI/device unavailable (standing rule ADR-1) | E2E unproven on device | `maestro test .maestro/notifications-pilot.yaml` (+ deeplink spec) |
| G-2 | Real FCM sends unproven until Gate 3 | Provider client fully faked in tests (`fakeFCM`); the real HTTP v1 client is wired but needs `FCM_SERVICE_ACCOUNT_JSON` + a device | Push delivery proof outstanding | Owner: set the env, run the stack, send `POST /admin/notifications/test` to a device after Gate 2 |
| G-3 | Pre-existing app test/lint debt (not 06's) | `src/__tests__/index.test.tsx` red + 3 committed files with lint debt, from the parallel 05 continuation; frozen surfaces per ADR-2 | App-gate reporting is scoped, not repo-wide | Owning work-stream fixes; 06 did not touch those files |
| G-4 | Delivery retention job (180-day aggregate-and-delete) | OQ-5 default noted; job deferred to keep the module scoped | `notification_deliveries` grows | Add `deliveries.retention` job with 13's analytics needs |
| G-5 | Email channel (`NTF-BE-023`) | Deferred: OTP email lives in 03; the notification email copy path has no consumer until 07 settings ship | `notify.SendEmail` not built | Land with 07's staff settings (spec NTF-BE-023) |
| G-6 | Native FCM token inactive until owner adds Firebase config | `getDevicePushTokenAsync()` needs `google-services.json` (android) / `GoogleService-Info.plist` (ios) + `FCM_SERVICE_ACCOUNT_JSON` on the api — owner-provided credentials, not invented (ADR-7) | Live-session push registration silently skipped; in-app + WS unaffected (NTF §7 edge 4) | Owner: create the Firebase project, drop the config files in `applications/app/`, set the api env, rebuild the dev client, then run the G-2 test push |
| G-7 | ~~`go build ./...` in `applications/api` broken by parallel 04 stream WIP~~ RESOLVED 2026-10-03 | `cmd/api/main.go:510` called `a.hierarchy.GetCity` before `internal/hierarchy` exported it (shared working tree, module 04's surface); the 04 stream has since landed the method | Was: repo-wide api build red | Verified: `go build ./...` + `go vet ./...` exit 0, `gofmt -l internal/` empty (2026-10-03) |
