# Images — how they are built and where they go

**Module:** `15-deployment-operations` (OPS-BE-001, -002, -005) · **Last updated:** 2026-10-08 ·
Runbook: [`../DEPLOYMENT.md`](../DEPLOYMENT.md)

Two images make up the platform. Since 2026-10-08 everything deploy-related lives in the docs repo
under `infra/` (owner decision), including both Dockerfiles; the app repos contain only application
code, and their CI no longer builds images. The owner builds and pushes from the workspace; the
server never builds anything (OPS-BR-001) — it only pulls exact tags.

```text
workspace (owner's Mac, Docker running)
  applications/api @ main ─┐   docs/infra/docker/api.Dockerfile
  applications/web @ main ─┼─► docker buildx build -f <Dockerfile> --platform linux/amd64 <app repo> --push
                           └─► <API_IMAGE>:main-<sha7> · <WEB_IMAGE>:main-<sha7>   (names from env/stack.env)
server: ops/deploy.sh pilot api=main-<sha7> web=main-<sha7> → docker compose pull → schema check → up → gate
```

## 1. What gets published

| Image (`env/stack.env`) | Source | Dockerfile | Runs |
| --- | --- | --- | --- |
| `API_IMAGE` (now `ghcr.io/aktarulrahul/kushol-api`) | `applications/api` | [`docker/api.Dockerfile`](../../docker/api.Dockerfile) | containers `api` (`serve`) and `worker` (`worker`); also `migrate-status` / `migrate` (one-off runs) |
| `WEB_IMAGE` (now `ghcr.io/aktarulrahul/kushol-web`) | `applications/web` | [`docker/web.Dockerfile`](../../docker/web.Dockerfile) | container `web` (Next.js standalone server) |
| `redis:7.4.11-alpine3.21@sha256:858f…` | Docker Hub (not ours) | — | container `redis`, pulled by digest |

The registry is whatever `API_IMAGE`/`WEB_IMAGE` name; changing registry means changing those two
values and logging the server in to the new registry (§4). Nothing else depends on it.

**Tags.**

| Tag | Meaning | Deployable? |
| --- | --- | --- |
| `main-<sha7>` | the first 7 hex characters of the `main` commit that was built, e.g. `main-1a2b3c4` | **yes** — the unit of deployment; `ops/deploy.sh` accepts only `main-<hex 7–40>` or `release-<hex 7–40>` |
| `latest` | optional convenience tag | **no** — `deploy.sh` refuses it so the release log always names an exact commit |

Tags are treated as immutable (OPS-BR-005): never re-point a `main-<sha7>` tag at different code.

## 2. Building and pushing (owner)

The CI image jobs were removed with the move, so the checks they used to enforce are now the
builder's job. For each app you build:

1. **Be on a committed `main`.** `git -C applications/<app> status --porcelain` empty, branch `main`,
   pushed. The tag names that commit; uncommitted changes would make it lie.
2. **Run the app's gate** (what CI's `gate` job runs): api `make gate` (integration tests need
   Docker), web `pnpm gate`. Don't publish a red build.
3. **Log in** to the registry with a token that can push (GHCR: classic PAT with `write:packages`).
4. **Build and push** from the workspace root, `kushol-connect/`:

```bash
SHA=$(git -C applications/api rev-parse --short=7 HEAD) && docker buildx build --platform linux/amd64 -f docs/infra/docker/api.Dockerfile --label org.opencontainers.image.revision=$(git -C applications/api rev-parse HEAD) -t ghcr.io/aktarulrahul/kushol-api:main-$SHA --push applications/api
```

```bash
SHA=$(git -C applications/web rev-parse --short=7 HEAD) && docker buildx build --platform linux/amd64 -f docs/infra/docker/web.Dockerfile --build-arg NEXT_PUBLIC_API_URL=https://kusholconnect.com --build-arg NEXT_PUBLIC_SITE_URL=https://kusholconnect.com --label org.opencontainers.image.revision=$(git -C applications/web rev-parse HEAD) -t ghcr.io/aktarulrahul/kushol-web:main-$SHA --push applications/web
```

5. **Deploy** the two tags: `ops/deploy.sh pilot api=main-<sha7> web=main-<sha7>` on the server.

Notes:

- The build context is the app repo (`applications/api`, `applications/web`); the Dockerfile comes
  from `docs/infra/docker`. BuildKit uses the ignore file named after the Dockerfile
  (`api.Dockerfile.dockerignore`, `web.Dockerfile.dockerignore`) — the app repos need none.
- On an Apple-silicon Mac the api cross-compiles natively (fast); the web build runs under amd64
  emulation and takes several minutes.
- Building never needs to run a container. The old CI web "boot check" is now covered by
  `deploy.sh`'s gate on the server (a web image that cannot start fails the gate and is rolled back).

## 3. How each image is built

Both Dockerfiles are multi-stage: build tools stay in the build stage, the runtime stage holds only
what runs. Base images are pinned by **tag + digest**, so a rebuild of the same commit uses the same
bases.

### 3.1 api — [`docker/api.Dockerfile`](../../docker/api.Dockerfile)

| Stage | Base | What happens |
| --- | --- | --- |
| `build` | `golang:1.26.8-alpine3.24@sha256:8ac98ca5…49a0c`, on the **build** platform (`--platform=$BUILDPLATFORM`) | `go mod download` (cached), copy sources, `CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api` — a static, stripped binary, cross-compiled |
| runtime | `gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec…555e3` | copies `/out/api` to `/usr/local/bin/api`; contains CA certificates (Neon TLS) and tzdata, **no shell, no package manager** |

Runtime contract: `USER 65532:65532` (non-root) · `ENV HTTP_PORT=8080` · `EXPOSE 8080` ·
`ENTRYPOINT ["/usr/local/bin/api"]` · `CMD ["serve"]`. Compose chooses the role with `command:`
(`serve` / `worker`); `deploy.sh` and `migrate.sh` run `migrate-status` / `migrate up --confirm` as
one-off containers; the container healthcheck runs `api healthcheck` (distroless has no curl).
Migrations (`db/migrations/*.sql`), the bn/en catalogs and the docs page are embedded with
`go:embed`, so the binary needs no files beside it.

[`api.Dockerfile.dockerignore`](../../docker/api.Dockerfile.dockerignore) keeps out `.git`, `.github`,
`.claude`, `.neon`, every `.env*` except `.env.example`, `node_modules` and the Neon CLI files,
`bin/` and logs — no local secret can reach the image.

### 3.2 web — [`docker/web.Dockerfile`](../../docker/web.Dockerfile)

| Stage | Base | What happens |
| --- | --- | --- |
| `base` | `node:22.23.3-alpine3.24@sha256:0a7108bf…2e402` | `corepack enable` → pnpm **11.8.0** from `package.json` `packageManager`; telemetry off |
| `deps` | `base` | copy `package.json`, `pnpm-lock.yaml`, `.npmrc`; `pnpm install --frozen-lockfile` (pnpm store cached) — a lockfile mismatch fails the build |
| `build` | `base` | copy `node_modules` + sources; `NODE_ENV=production` and the two `NEXT_PUBLIC_*` build args become env; `pnpm build` → `.next/standalone` (`output: "standalone"` in `next.config.ts`); `src/env.ts` validates both URLs during the build, so a missing build arg fails it |
| `run` | same pinned node image | copies `.next/standalone`, `.next/static` and `public/` (owned by `node`); `USER node`; `PORT=3000`, `HOSTNAME=0.0.0.0`; `CMD ["node", "server.js"]` |

**Build-time values.** Next.js inlines `NEXT_PUBLIC_*` into the browser *and* server bundles at build
time, so each web image belongs to one site origin:

| Build arg | Value |
| --- | --- |
| `NEXT_PUBLIC_API_URL` | `https://kusholconnect.com` (browser calls `/api/v1/…` same-origin; Nginx routes `/api/` to the api) |
| `NEXT_PUBLIC_SITE_URL` | `https://kusholconnect.com` |

These values are public (they ship to every browser) — never put a secret in a `NEXT_PUBLIC_*`
variable. The server's `env/web.env` holds the same values and must match. The web schema also reads
`NEXT_PUBLIC_MAINTENANCE_MODE` and `NEXT_PUBLIC_DOWNLOAD_URLS_READY`; the Dockerfile does not pass
them yet, so images always have both `false` (15 08-gaps G-13).

[`web.Dockerfile.dockerignore`](../../docker/web.Dockerfile.dockerignore) keeps out `.git`, every
`.env*` except `.env.example` (Next.js would otherwise load `.env.local` during the build),
`node_modules`, `.next`, test output, `e2e/`.

### 3.3 Size targets (spec, unmeasured until the first build)

| Image | Target (15 `03-backend-tasks.md`) | Check |
| --- | --- | --- |
| api | < 40 MB | `docker image ls <API_IMAGE>` after the build or a pull on the server |
| web | < 250 MB | same for `<WEB_IMAGE>` |

## 4. The registry

Current configuration: GitHub Container Registry, `ghcr.io/aktarulrahul/kushol-{api,web}`.

| Topic | How it works here |
| --- | --- |
| Visibility | Keep the repositories **private**: the images are the product's compiled code. GHCR packages are private by default; registries that create repositories on first push (e.g. Docker Hub) may default to public — create the repository as private before the first push |
| Who can push | The owner, with a push-scoped token (GHCR: `write:packages`) |
| Who can pull | The server, as the `kushol` user, with a **read-only** token (GHCR: classic PAT with `read:packages`) — `sudo -iu kushol docker login <registry> -u <user>`, token pasted at the prompt (DEPLOYMENT.md §3.5). Stored in `/home/kushol/.docker/config.json`, base64 and not encrypted, which is why it must be read-only |
| Token expiry | Deploys fail with exit **5** (pull failed) and the running stack is untouched. New token, `docker login` again |
| Storage | Keep every tag still in `state/releases.log` (rollback targets); delete older versions in the registry's UI when storage matters |
| On the server | Pulled images stay on disk until pruned; keep recent ones so a rollback needs no download. `docker image prune -f` removes dangling layers only |

## 5. Updating base images

Pins change only on purpose, in a commit of their own (docs repo):

1. Pick the new tag (e.g. the latest `golang:1.26.x-alpine3.y`, `node:22.x-alpine3.y`,
   `distroless/static-debian13:nonroot`, `redis:7.4.x-alpine3.y`).
2. Get its digest: `docker buildx imagetools inspect <image>:<tag>` (the `Digest:` line).
3. Replace `tag@sha256:…` in the Dockerfile (or `deploy/compose.yaml` for redis); keep the Go and Node
   majors in line with the api's `go.mod` and the web's `.nvmrc`.
4. Build, push and deploy like any release.

`deploy/tests/run.sh` fails if a third-party image in `compose.yaml` is not pinned by digest.

## 6. From image to server

`ops/deploy.sh pilot api=main-<sha7> web=main-<sha7>` (either tag can be omitted to keep the one
running) pulls the tags, checks the database schema with the new api image, swaps containers and
gates on `/readyz` + smoke — see [`scripts.md`](scripts.md) and DEPLOYMENT.md §6.
