# Foundations — Gaps

**Module:** `01-foundations` · **Last updated:** 2026-09-30

Genuine remaining gaps only (reason · impact · next action).

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Migrations not applied to Neon (Gate 2) | Owner runs SQL manually by rule | Production database has no schema; `migrate-status` deploy gate would fail | Neon project exists (`kushol-connect-db`, Singapore, linked in `applications/api`). Owner: from `applications/api`, run `migrate up --confirm` then `migrate-status` with `DATABASE_URL_UNPOOLED` from `.env.local` (see api README); record the date here and in `07-progress.md` |
| G-2 | CI workflows never run on GitHub | No commits or remotes yet in any repo | Required checks unproven on hosted runners (e.g. Playwright `--with-deps`, pnpm cache) | After the owner asks for commits and creates remotes: push each `module/01-foundations` branch and confirm all three workflows pass |
| ~~G-3~~ | ~~Postgres major in tests not confirmed against Neon~~ | **Closed 2026-09-30:** Neon runs Postgres 18; `testkit` moved to `postgres:18-alpine`, integration suite green | — | — |
| G-4 | Go module path / api repo remote unconfirmed | Owner hasn't named the remote | Renaming later touches every import | Owner confirms `github.com/aktarulrahul/kushol-connect/applications/api` or the final path before the first commit |
| G-5 | Default rate limit 120 req/min/IP is a placeholder (C5) | No traffic data yet | May throttle a school NAT sharing one IP, or be too loose | Owner confirms; revisit with 03's auth classes |
| G-6 | App not yet run on Android or on a physical device | Development build verified in the iOS Simulator only (2026-09-30); no Android SDK tools (`adb`) on the dev Mac; a device build needs the owner's accounts | Android runtime and real-device behaviour unproven | Owner: `eas login` + `eas init`, then `eas build --profile development` (register test iPhones with `eas device:create`) or install Android Studio for an emulator. First on-device check with 02/03 (360px, bn/en, low-end Android profile) |
| ~~G-7~~ | ~~App identifiers unset~~ | **Closed 2026-09-30:** owner chose `com.kusholconnect.app` for `ios.bundleIdentifier` and `android.package` | — | — |
| G-8 | Home repo for deploy files (infra F18) | Apps are separate repos | 15 has nowhere agreed to put Compose/Nginx/ops scripts | Owner decides before module 15 |
| G-9 | Local config plugin for the iOS scene life cycle (ADR-17) | Expo SDK 57's prebuild template doesn't adopt UIScene, which iOS 27 requires | If Expo changes the template, prebuild fails with the plugin's message | On each Expo upgrade: if the template's `AppDelegate` uses `ExpoAppSceneDelegate`, delete `app/plugins/with-ios-scene-lifecycle.js` and its `app.json` entry |
