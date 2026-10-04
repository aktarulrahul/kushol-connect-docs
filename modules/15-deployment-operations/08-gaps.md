# Deployment & Operations — Gaps

**Module:** `15-deployment-operations` (Part A) · **Last updated:** 2026-10-04

Genuine remaining gaps only (reason · impact · next action).

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Nothing has run on the server yet — host prep, HestiaCP web/mail, migrations, first deploy, DNS, TLS, rollback drill | Owner rule: the agent has no SSH and never runs the stack; server steps are owner-run | OPS-US-001/003/004 unproven end to end; pending owner run | Owner follows `applications/api/deploy/DEPLOYMENT.md` §2 and pastes each output into `07-progress.md` "Owner run" |
| G-2 | Worker container has no healthcheck (`disable: true`) | Worker serves no HTTP; distroless has no shell | A hung (not crashed) worker is not detected; crashes still restart (OPS-BR-006 partly met) | 01 adds a worker heartbeat (e.g. file in `/tmp` touched each loop + `api healthcheck --worker`); then enable it in `compose.yaml` |
| G-3 | `shellcheck`, both image builds and `docker compose config` have not run yet | Not installed / Docker off on the dev Mac (owner rule) | Script lint or image build errors surface only on the first CI run | First push of these changes: CI jobs `deploy-bundle` and `image` (image only on `main`); fix anything red |
| G-4 | Smoke has no login round-trip (OPS-E2E-001 asks for it, Playwright) | No login on `main` yet | Gate proves health, routing and TLS, not auth | When 03 is on `main`: Playwright smoke against `https://kusholconnect.com` in `ops/smoke.sh public` or CI |
| G-5 | No Content-Security-Policy on the web | A wrong CSP breaks Next.js; 07 owns the pages | Weaker XSS defence-in-depth | 07 sets CSP (nonce-based) in Next or the template |
| G-6 | ~~Maintenance mode~~ **built 2026-10-04** (Part B): `ops/maintenance.sh` + Nginx flag → 503 bn/en page + `/maintenance` page + `NEXT_PUBLIC_MAINTENANCE_MODE`; enable/disable drill pending owner | — | — | run drill once after first deploy |
| G-7 | Part B **code-complete 2026-10-04** (backup/restore scripts + drill doc, uptime checker, rotation runbook, redaction probe, prod-wiring checklist, EAS workflow) — executions are owner-run | Agent never runs the stack | Nothing has executed yet: no backup artifact, no drill evidence, no monitor paging | Owner: wire cron + monitor (`docs/backups.md` §1), run the drill, execute `docs/prod-wiring.md` |
| G-8 | Spec text still describes one tag per release and `deploy/Dockerfile.*` paths | Repos were split per app after the spec was drafted (ADR-1/ADR-2) | Spec vs build drift | Owner approves; then update 15 `03-backend-tasks.md` §2/§3 and `technical-document.md` |
| G-9 | "The 4 emails" read as 4 mailboxes (3 people + `noreply`) with `hello@` as an alias | Request named no addresses; architecture §7.1 lists 5 | Different set needed? | `TODO: Confirm` with Rahul — change `MAILBOXES`/`MAIL_ALIASES` and rerun `setup-mail.sh` (existing mailboxes untouched) |
| G-10 | `noreply@` send rate limit left at the HestiaCP default | OTP volume unknown before 03/06 go live | OTP email could be throttled under load | Measure after 03 email OTP ships; `v-change-mail-account-rate-limit` or move to a transactional provider (architecture §7.3) |
| G-11 | The HestiaCP version and web stack on this VPS are unknown | No SSH for the agent | Scripts detect nginx proxy vs standalone and refuse unsupported setups or a HestiaCP without password-file support | Confirm from the host report (G-1 step 1) |
| G-12 | ~~Boot check after push~~ **fixed 2026-10-04**: web `image` job now builds (load) → boot-checks → pushes | — | — | first CI run confirms |
