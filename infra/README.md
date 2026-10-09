# Infrastructure — everything deploy-related

Owner decision 2026-10-08: **all deploy-related files and docs live here**, in the docs repo, and
nowhere in the app repos (`applications/api`, `applications/web`, `applications/app`). The app repos
contain application code and their own CI gates only.

| Path | What |
| --- | --- |
| [`architecture-and-deployment.md`](architecture-and-deployment.md) | Architecture plan and reasoning: topology, findings F1–F19, DNS and email plan |
| [`deploy/DEPLOYMENT.md`](deploy/DEPLOYMENT.md) | **Runbook** — first deployment plan, host prep, HestiaCP domains and mail, DNS, deploy, rollback, troubleshooting |
| [`deploy/docs/`](deploy/docs/) | Reference: `images.md` (build + registry), `stack.md` (Compose, layout, config, security), `scripts.md`, `hestia.md` (Nginx, TLS, mail), `backups.md`, `prod-wiring.md`, `secret-rotation.md` |
| [`docker/`](docker/) | `api.Dockerfile`, `web.Dockerfile` and their `*.dockerignore` — built with `-f` against the app repo as context (`deploy/docs/images.md` §2) |
| [`deploy/`](deploy/) | The server bundle synced to `/opt/kushol` on the VPS: `compose.yaml`, `env/*.example`, `ops/`, `host/`, `hestia/` |
| [`deploy/tests/`](deploy/tests/) | Bundle checks and deploy/rollback flow tests — `bash infra/deploy/tests/run.sh` / `flow.sh` from the docs repo |

## Things to know

- **This repo is public** (`aktarulrahul/kushol-connect-docs`). Only templates go in: real env
  files (`deploy/env/*.env`) and server state (`deploy/state/`) are git-ignored and must never be
  committed. The server's IP, ports and layout are visible to anyone.
- **No CI checks this folder yet.** The api repo's old `deploy-bundle` and both repos' `image` jobs
  were removed with the move. Run the bundle tests before committing changes here.
- **Images are built by the owner** from the workspace (`deploy/docs/images.md` §2) — never on the
  VPS. The registry is whatever `API_IMAGE`/`WEB_IMAGE` say in `deploy/env/stack.env`.
- The agent never runs the stack or the server steps (AGENTS.md rule 1); every server step is a
  script the owner runs.
