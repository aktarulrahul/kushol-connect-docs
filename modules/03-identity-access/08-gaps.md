# 03-identity-access — Gaps

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Teacher self-registration still collects a password | Scope: the owner's 2026-10-02 decision covered **login** ("after input email, 6 digit OTP will be sent"); registration is unchanged spec | A password hash is created that no login flow reads (until 07's vendor pattern) — harmless but possibly not what the owner wants | Ask the owner: make teacher registration email-OTP-verified and passwordless too? |
| G-2 | `/auth/password/forgot` + `/reset` remain in the contract | Kept for 07's vendor first-password set and account recovery | Dead surface for staff (no password login); two endpoints to maintain | Decide at 07 build: drop them or keep for vendors |
| G-3 | Integration stage not started — web+app still run on fixtures | Stage 5 follows Gate 1 UI approval | Screens don't talk to the real api yet | Owner approves UI (incl. new Email OTP tabs) → swap fixtures for the generated client, run e2e against the local stack |
| G-4 | E2E (web Playwright, app Maestro) not run this session | Local stack not started (owner runs it) | Golden paths verified by unit + integration tests only, not browser/device | Owner runs `applications/dev-start.sh`, then the e2e commands handed over at Stage 5 |
| G-5 | Neon (shared DB) has no migrations applied yet | Same as 01-foundations G-1 — owner-run Gate 2 | Api not deployable; super admin exists only on local `kc` | Owner: from `applications/api`, `go run ./cmd/api migrate up --confirm` with `DATABASE_URL_UNPOOLED`, then re-run `bootstrap-super-admin` |
