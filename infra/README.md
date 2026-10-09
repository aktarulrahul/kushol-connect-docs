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
| [`deploy/build-push-images.sh`](deploy/build-push-images.sh) | **Mac:** build + push the api/web images from committed `main` (checks, gates, immutable tags) |
| [`deploy/deploy-web-api-vps.sh`](deploy/deploy-web-api-vps.sh) | **Mac:** sync the bundle (`--sync`) and/or deploy the tags on the VPS over SSH |
| [`deploy/tests/`](deploy/tests/) | Bundle checks, deploy/rollback flow tests, Mac-script tests — `bash infra/deploy/tests/run.sh` / `flow.sh` / `workstation.sh` from the docs repo |

## Things to know

- **This repo is public** (`aktarulrahul/kushol-connect-docs`). Only templates go in: real env
  files (`deploy/env/*.env`) and server state (`deploy/state/`) are git-ignored and must never be
  committed. The server's IP, ports and layout are visible to anyone.
- **No CI checks this folder yet.** The api repo's old `deploy-bundle` and both repos' `image` jobs
  were removed with the move. Run the bundle tests before committing changes here.
- **Images are built from the workspace** (`deploy/docs/images.md` §2) — never on the VPS — and
  pushed to the **private** Docker Hub repository `airahul/ai` as `api-main-<sha7>` / `web-main-<sha7>`.
  Release = `bash docs/infra/deploy/build-push-images.sh` then `bash docs/infra/deploy/deploy-web-api-vps.sh`
  from the workspace root.
- The agent never runs the stack or the server steps (AGENTS.md rule 1); every server step is a
  script the owner runs.
