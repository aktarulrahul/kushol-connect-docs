# Foundations — Gaps

**Module:** `01-foundations` · **Last updated:** 2026-09-30

Genuine remaining gaps only (reason · impact · next action).

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Migrations not applied to Neon (Gate 2) | Owner runs SQL manually by rule | api cannot run against the shared database; `migrate-status` deploy gate would fail | Owner: pick the Neon region (infra F1), then `bin/api migrate up --confirm` and `bin/api migrate-status` with the **direct** endpoint; record the date here and in `07-progress.md` |
| G-2 | CI workflows never run on GitHub | No commits or remotes yet in any repo | Required checks unproven on hosted runners (e.g. Playwright `--with-deps`, pnpm cache) | After the owner asks for commits and creates remotes: push each `module/01-foundations` branch and confirm all three workflows pass |
| G-3 | Postgres major in tests (17) not confirmed against Neon | Neon project not created yet | A version-specific SQL difference could pass tests and fail on Neon | Confirm at Gate 2; change `testkit` image if different |
| G-4 | Go module path / api repo remote unconfirmed | Owner hasn't named the remote | Renaming later touches every import | Owner confirms `github.com/aktarulrahul/kushol-connect/applications/api` or the final path before the first commit |
| G-5 | Default rate limit 120 req/min/IP is a placeholder (C5) | No traffic data yet | May throttle a school NAT sharing one IP, or be too loose | Owner confirms; revisit with 03's auth classes |
| G-6 | App not run on a device or emulator | No Android emulator on the dev Mac; there are no product screens yet | Native runtime is verified only through tests + the Android bundle export | First on-device check with 02/03 (360px, bn/en, low-end Android profile), using an EAS development build |
| G-7 | App identifiers (`android.package`, `ios.bundleIdentifier`) unset | Store identity not decided | EAS build (15) can't run without them | Owner decides (e.g. reverse-domain of `kusholconnect.com`) — `TODO: Confirm` |
| G-8 | Home repo for deploy files (infra F18) | Apps are separate repos | 15 has nowhere agreed to put Compose/Nginx/ops scripts | Owner decides before module 15 |
