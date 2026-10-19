# Release Runbook — pilot (api + web)

Release commands, run from the workspace root (`/d/ai-workspace/me/kushol-connect`) in Git Bash.
**Status: none of these have been run yet.**

## Before you start

Commit the api and web changes on main and push both to `origin/main`:

- The build script refuses a dirty or unpushed repo, and it tags each image with the pushed commit.
- Hold the app commit until the other session finishes — it is still editing `applications/app`.
  (The app isn't built into an image anyway.)

## Step 1 — Build and push images

Docker Desktop must be running and you must be logged in to Docker Hub as `airahul`.

```bash
bash docs/infra/deploy/build-push-images.sh --skip-gate
```

> **Why `--skip-gate`:** the gates fail on this Windows machine for reasons unrelated to this change.
>
> - **Web:** lint errors in two files this change doesn't touch, plus Prettier's line-ending false positives.
> - **Api:** the gate runs the integration tests, which need Docker. Run them yourself first if you want that proof (they include the new `TestIT020`):
>
>   ```bash
>   cd applications/api && make test-integration
>   ```

## Step 2 — Update the server env with the KLIPY key

Copy the new script first, then send the key:

```bash
scp docs/infra/deploy/host/set-api-env.sh root@72.61.114.20:/opt/kushol/host/set-api-env.sh
grep -E '^(R2*[A-Z*]+|SMS*GATEWAY*[A-Z_]+|SMTP*[A-Z*]+|KLIPY_APP_KEY)=' applications/api/.env | ssh root@72.61.114.20 'bash /opt/kushol/host/set-api-env.sh --from-stdin'
```

## Step 3 — Deploy

`deploy-web-api-vps.sh` fails in Git Bash, so this goes straight over SSH.
The tags are read from your current commits:

```bash
ssh -t root@72.61.114.20 "sudo -iu kushol /opt/kushol/ops/deploy.sh pilot api=main-$(git -C applications/api rev-parse --short=7 HEAD) web=main-$(git -C applications/web rev-parse --short=7 HEAD)"
```

> **Expect exit 3 ("database behind")** because the new migration `20270308090000` hasn't run yet.
> Nothing changes on the server at this point.

## Step 4 — Run migrations

Check the status first, then apply:

```bash
ssh -t root@72.61.114.20 "sudo -iu kushol /opt/kushol/ops/migrate.sh main-$(git -C applications/api rev-parse --short=7 HEAD) status"
ssh -t root@72.61.114.20 "sudo -iu kushol /opt/kushol/ops/migrate.sh main-$(git -C applications/api rev-parse --short=7 HEAD) up --confirm"
```

> If the earlier release was never migrated, its 7 migrations will be listed too —
> including the demo-tenant seed.

## Step 5 — Deploy again

Run the same command as [Step 3](#step-3--deploy).

- Success prints `SERVING pilot api=main-… web=main-…`.
- If the health check fails, the script rolls back on its own.

## Important

Run steps 3–5 **without committing anything else** to api or web after the build.
The commands read the tags from your current commits, so a new commit would point
them at images that don't exist.
