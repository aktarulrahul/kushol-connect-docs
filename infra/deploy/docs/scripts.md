# Scripts and tests — reference

**Module:** `15-deployment-operations` (OPS-BE-006…008, -012, -016) · **Last updated:** 2026-10-02 ·
Runbook: [`../DEPLOYMENT.md`](../DEPLOYMENT.md)

Conventions for every script: Bash with `set -euo pipefail`; non-interactive (cron-safe); progress
and errors on **stderr**; where a script has a result, it is **one line on stdout**; safe to rerun.
Script CLIs change additively only — new flags optional, existing behaviour and exit codes stable
(15 `06-integration-tasks.md` §7).

| Script | Run as | Purpose |
| --- | --- | --- |
| [`ops/deploy.sh`](../ops/deploy.sh) | `kushol` | gated deploy with automatic rollback |
| [`ops/rollback.sh`](../ops/rollback.sh) | `kushol` | redeploy the previous release from the log |
| [`ops/smoke.sh`](../ops/smoke.sh) | `kushol` | post-deploy checks (local or through the public front door) |
| [`ops/migrate.sh`](../ops/migrate.sh) | `kushol` — **owner only** | migration status / apply (Gate 2) with a given api image |
| [`ops/compose.sh`](../ops/compose.sh) | `kushol` | `docker compose` with the stack's files and the deployed tags |
| [`ops/lib.sh`](../ops/lib.sh) | (sourced) | shared helpers |
| [`host/prepare-host.sh`](../host/prepare-host.sh) | `root` | one-time host preparation |
| [`host/first-deploy.sh`](../host/first-deploy.sh) | `root`, interactive (`ssh -t`) | the whole first deployment in one run: prepare-host → api.env secrets → registry login → setup-web → migrations (asks) → deploy → public check |
| [`hestia/setup-web.sh`](../hestia/setup-web.sh) | `root` | HestiaCP web domains, Nginx templates, TLS |
| [`hestia/setup-mail.sh`](../hestia/setup-mail.sh) | `root` | HestiaCP mail domain, mailboxes, aliases, DNS values |
| [`hestia/lib.sh`](../hestia/lib.sh) | (sourced) | shared HestiaCP helpers |
| [`tests/run.sh`](../tests/run.sh), [`tests/flow.sh`](../tests/flow.sh) | anyone (CI, Mac) | bundle checks and deploy/rollback flow tests |

## `ops/deploy.sh <env> [api=<tag>] [web=<tag>] [--no-rollback]`

`<env>` must equal `KUSHOL_ENV` in `env/stack.env` (`pilot`). A tag left out keeps the deployed one;
with no tags at all it **redeploys the current release** (useful after a manual stop or an env
change). The first deploy needs both tags. `--no-rollback` disables the automatic rollback (used by
`rollback.sh`); `--note=<word>` adds a note to the log line (internal).

Steps:

1. **Lock** — `flock` on `state/deploy.lock`; a second deploy/rollback exits 2 (edge case 1).
2. **Env check** — `stack.env`, `api.env`, `web.env` exist, are chmod 600 and fill every required key
   (uncommented in the `.example`) with a non-placeholder value (no `REPLACE`). The error names the keys.
3. **Tags** — each must match `^(main|release)-[0-9a-f]{7,40}$`; `latest` is refused.
4. **Pull** — `docker compose pull` of api, worker, web, redis with the *candidate* tags, 3 attempts
   (5 s, 10 s pauses). Failure → exit 5; nothing changed.
5. **Schema check** — a one-off container of the *new* api image runs `migrate-status` (read-only)
   against `DATABASE_URL`. Exit 1 (cannot reach Neon — e.g. a cold start) is retried up to 3 times,
   5 s apart. Behind → exit 3 with the `ops/migrate.sh <tag> up --confirm` command to run (Gate 2);
   dirty → exit 4. Nothing changed in either case. **The script never applies migrations.**
6. **Swap** — writes `state/release.env`, `docker compose up -d --remove-orphans`. Compose recreates
   only the services whose image changed (a brief restart; WebSocket clients reconnect).
7. **Gate** — `http://127.0.0.1:$API_PORT/readyz` must return 200 within 120 s (polled with a 2→10 s
   back-off, so Neon warm-up is tolerated), then `http://127.0.0.1:$WEB_PORT/` within 120 s, then
   `ops/smoke.sh` (mode from `SMOKE_MODE`). A green `/readyz` alone is not enough (edge case 2).
8. **Green** → `SERVING` line in `releases.log`; stdout `SERVING <env> api=<tag> web=<tag>`; exit 0.
9. **Red** → container status and the last 40 log lines of api/worker/web on stderr; `FAILED` in
   `releases.log`; a line in `incidents.log`; then, if a release was serving before, it is put back
   (same `up -d` + gate) → `SERVING auto-rollback` and stdout `ROLLED_BACK …`, or
   `ROLLBACK_FAILED` if that also fails. Exit 1 either way.

Migrations must follow expand/contract so the previous image still works on the newer schema — that
is what makes step 9 safe.

## `ops/rollback.sh <env>`

Finds the rollback target in `state/releases.log`: the newest release whose latest line is
`SERVING` and that is not the running one ([`stack.md`](stack.md) §2.1). Marks the running release
`ROLLED_BACK operator`, writes an incident line, then hands over (with the lock) to
`deploy.sh <env> api=<target> web=<target> --no-rollback --note=rollback`. Exits 2 when nothing is
deployed or there is no earlier `SERVING` release. Only releases in the log can be targets, and
nothing is rebuilt (OPS-BR-005). Target: under 5 minutes, drill-timed on the server (07-progress
"Owner run" step 7); the images are normally still on disk, so the pull is quick.

## `ops/smoke.sh [local|public]`

Default mode: `SMOKE_MODE` from `stack.env`. stdout `SMOKE_OK <mode>` (exit 0) or
`SMOKE_FAILED <mode>` (exit 1); each check is logged on stderr.

| Mode | Check | Expect |
| --- | --- | --- |
| local | `http://127.0.0.1:$API_PORT/healthz`, `/readyz` | 200, 200 |
| local | `http://127.0.0.1:$WEB_PORT/` (redirects followed) | 200 |
| public | `https://$API_DOMAIN/healthz`, `/readyz` | 200, 200 (valid TLS) |
| public | `https://$SITE_DOMAIN/` (redirects followed) | 200 |
| public | `http://$SITE_DOMAIN/` | 301 (force HTTPS) |
| public | `https://www.$SITE_DOMAIN/` | 301 (to the apex) |
| public | `https://$SITE_DOMAIN/api/v1/` | response carries `X-Request-Id` — proves `/api/` reaches the api, not the web |

A Playwright login round-trip joins `public` when 03 is on `main` (08-gaps G-4).

## `ops/migrate.sh <api-tag> status | up --confirm` — owner only (Gate 2)

Pulls that api image and runs its own subcommand in a one-off container with `env/api.env`:
`status` → `migrate-status` (read-only: prints `database_version=… expected_version=… dirty=…`;
exit 3 behind, 4 dirty); `up --confirm` → `migrate up --confirm`, applying every embedded migration
newer than the database. Without `--confirm` it refuses. Uses a temporary release file, so the
running stack is not touched. Record each run in the module's `07-progress.md`.

## `ops/compose.sh <compose args…>`

`docker compose --project-name kushol --project-directory /opt/kushol -f compose.yaml
--env-file env/stack.env --env-file state/release.env <args>`. Refuses before the first deploy.
Examples: `ps`, `logs -f --tail 100 api`, `restart web`, `top`, `exec redis redis-cli info memory`.
Deploys never go through it.

## `host/prepare-host.sh [--ssh-key-file FILE]` — root, once

Requires the bundle in `/opt/kushol`. In order:

1. **Host report** to `state/host-check-<UTC>.txt` and the screen: OS, CPU, memory, swap, disk,
   listening ports (`ss -tlnp`), HestiaCP settings (`VERSION`, `WEB_SYSTEM`, `PROXY_SYSTEM`,
   `MAIL_SYSTEM`, anti-virus/anti-spam, webmail, firewall), Docker version, running containers and
   network subnets.
2. **Conflicts** — stops if `API_PORT`/`WEB_PORT` are already listening (unless the kushol stack
   itself holds them) or `KUSHOL_SUBNET` overlaps an existing Docker network.
3. **Docker** — installs Docker Engine + Compose plugin from Docker's apt repository only when
   `docker` is missing; an existing Docker and its `daemon.json` are left alone (no restart).
4. **Swap** — 2 GB `/swapfile` + `vm.swappiness=10`, only when the host has no swap.
5. **Deploy user** `kushol` — created with a locked password, added to `docker`; with
   `--ssh-key-file` the keys are appended to its `authorized_keys`.
6. **Layout** — creates `env/{stack,api,web}.env` from the examples if missing; `chown -R kushol`;
   `env/` 0700, env files 0600, scripts executable.
7. **Outbound checks** — port 25 to Gmail's MX (mail delivery) and Docker Hub registry reachability.

## `hestia/setup-web.sh` — root, twice

See [`hestia.md`](hestia.md) §1 for the routing it sets up. In order:

1. Detects the HestiaCP web stack from `hestia.conf`: `PROXY_SYSTEM=nginx` (nginx in front of
   apache2 — proxy templates, `v-change-web-domain-proxy-tpl`) or `WEB_SYSTEM=nginx` (nginx only — web
   templates, `v-change-web-domain-tpl`); anything else stops.
2. Renders `templates/kushol-{web,api}.{tpl,stpl}` (ports from `stack.env`) into HestiaCP's template
   directory.
3. Creates the HestiaCP user `HESTIA_USER` if missing (`v-add-user`, generated password → credentials
   file).
4. Creates the web domains if missing (`v-add-web-domain`: apex with alias `www.<apex>`, `api.` with no
   alias) and (re)applies the Kushol templates — every run, so template edits take effect.
5. TLS, per domain, only when every name resolves to `PUBLIC_IP`: `v-add-letsencrypt-domain` (apex +
   `www`; `api.`), then `v-add-web-domain-ssl-force` and `-ssl-hsts`. Otherwise a warning: rerun after
   DNS.
6. After the apex certificate: `v-add-web-domain-redirect <apex> <apex> 301` (any other host name,
   i.e. `www`, → apex).
7. `nginx -t`, `systemctl reload nginx`, then HTTP checks through the local Nginx.

## `hestia/setup-mail.sh` — root, once + once after DNS

Overridable through the environment: `MAILBOXES` (default
`"aktarul.islam:2048 jafrin.myoria:2048 atiqul.islam:2048 noreply:256"`, account:quota-MB),
`MAIL_ALIASES` (default `"hello dmarc postmaster abuse"`), `ALIAS_OWNER` (default `aktarul.islam`).

1. Checks a mail system is installed and that HestiaCP reads passwords from `/tmp` files.
2. Creates the HestiaCP user if missing.
3. Mail domain if missing — `v-add-mail-domain <user> <domain> <antispam> <antivirus> yes 2048`
   (anti-spam / anti-virus `yes` only when HestiaCP has them installed; DKIM 2048-bit; webmail added by
   HestiaCP when a webmail client is installed).
4. Each mailbox in `MAILBOXES` that does not exist yet — `v-add-mail-account` with a generated
   24-character password passed as a `/tmp` file, recorded only in the credentials file. Existing
   mailboxes are skipped: rerunning never changes a password.
5. Each alias — `v-add-mail-account-alias <user> <domain> <ALIAS_OWNER> <alias>` ("exists" is fine).
6. Mail TLS when `mail.` (and the webmail name) resolve here — `v-add-letsencrypt-domain <user>
   <domain> '' yes`.
7. Port-25 check; prints the DNS records (A `mail`/`webmail`, MX, SPF, DMARC and the DKIM value from
   `v-list-mail-domain-dkim-dns`) and the client settings.

To add one person later: `MAILBOXES="new.person:2048" bash /opt/kushol/hestia/setup-mail.sh`.

## Exit codes (`deploy.sh`, `rollback.sh`; `migrate.sh` passes the api's through)

| Code | Meaning | Containers changed? |
| --- | --- | --- |
| 0 | serving the requested release | yes |
| 1 | failed the gate/smoke (rolled back when possible), or `migrate-status` failed | gate: yes, then restored · status: no |
| 2 | usage or precondition: bad/`latest` tag, env file incomplete or not 600, `<env>` mismatch, lock held, nothing to roll back to, first deploy without both tags | no |
| 3 | database behind the new image — run the migrations first | no |
| 4 | database schema dirty — a migration failed midway | no |
| 5 | image pull failed (login, token, network, unknown tag) | no |

Machine-readable stdout lines: `SERVING|ROLLED_BACK|ROLLBACK_FAILED|FAILED <env> api=<tag> web=<tag>`
(deploy/rollback), `SMOKE_OK|SMOKE_FAILED <mode>` (smoke).

## Tunables (testing only)

`KC_GATE_TIMEOUT` (default 120 s per gate check) and `KC_RETRY_DELAY` (default 5 s) are read from
the environment; `tests/flow.sh` shortens them. Leave them unset on the server.

## Tests

Run from the docs repo: `bash infra/deploy/tests/run.sh` and `bash infra/deploy/tests/flow.sh`
(no containers). No CI runs them since the move to `docs/infra` (the docs repo has no workflow —
15 08-gaps G-14); before changing a script, also run `shellcheck -x infra/deploy/*/*.sh` if
shellcheck is installed. The env-parity checks read the api and web sources from
`../applications` (or `KC_APPS`) and print `SKIP` when those repos are not there.

| Script | Checks |
| --- | --- |
| `tests/run.sh` (87 checks with the app repos present) | tag scheme accepts/refuses (OPS-UT-003) · env completeness detects empty, absent and `REPLACE` values · release-log rollback targets (skips `FAILED`, walks back after `ROLLED_BACK`) · **env parity**: every key in `internal/config` is in `api.env.example` or set by Compose, and nothing extra (OPS-UT-002); `web.env.example` matches the web repo's `src/env.ts` when it sits next to this repo · Compose rules: exactly api/redis/web/worker, each with `mem_limit`, `restart: unless-stopped`, `healthcheck`, `logging`; every port `127.0.0.1:`; no `build:`; no Postgres/MinIO; third-party images pinned by digest · no image builds in host scripts (OPS-BR-001) · templates use only known placeholders, balanced braces, never append `X-Forwarded-For` · `bash -n` on every script |
| `tests/flow.sh` (33 checks; 34 where `flock` exists, e.g. Linux) | runs the real `deploy.sh`/`rollback.sh` against fake `docker` and `curl` (no containers, no network): first deploy · api-only deploy keeps web · red gate → automatic rollback (release, running tags, log lines, incidents) · database behind (exit 3, no `up`, owner command named) · dirty (4) · pull failure (5) · `latest` / env mismatch / unknown argument / placeholder secret / world-readable env refused (2) · operator rollback walks back, then has nothing left (2) · nothing to roll back before the first deploy · lock refusal (with a real `flock`, i.e. in CI) |

The container-backed dry-run (OPS-IT-001) is the owner's first deploy on the server.
