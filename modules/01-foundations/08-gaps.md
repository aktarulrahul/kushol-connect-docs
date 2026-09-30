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
| G-6 | App not run on a device, emulator or simulator | No Android emulator and no iOS Simulator runtime on the dev Mac (Xcode 27 installed, `simctl list runtimes` empty); there are no product screens yet | Native runtime is verified only through tests + the Android bundle export | Owner: install the iOS runtime (`xcodebuild -downloadPlatform iOS`), then `./dev-start.sh --ios`. First on-device check with 02/03 (360px, bn/en, low-end Android profile), using an EAS development build |
| ~~G-7~~ | ~~App identifiers unset~~ | **Closed 2026-09-30:** owner chose `com.kusholconnect.app` for `ios.bundleIdentifier` and `android.package` | — | — |
| G-8 | Home repo for deploy files (infra F18) | Apps are separate repos | 15 has nowhere agreed to put Compose/Nginx/ops scripts | Owner decides before module 15 |
