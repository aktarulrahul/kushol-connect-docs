# Backups & restore drill (OPS-BE-009/010)

**Cadence:** nightly 02:30 Asia/Dhaka via root cron. **Retention:** 30 days local + R2
(versioned bucket) + one off-site rclone remote. **Rule (BR-007):** the pilot is not signed off
until one restore drill has succeeded and its evidence is filed in `07-progress.md`; repeat
quarterly.

## 1. One-time setup (owner)

1. `rclone config` as root: remote `r2` (Cloudflare R2 S3 backend, bucket `kushol-backups` with
   **versioning enabled** in the R2 console) and one off-site remote (`offsite` — B2/another
   account). R2 credentials live in rclone's config, not in the repo.
2. `install -m 600 -o root /opt/kushol/env/backup.env.example /opt/kushol/env/backup.env`, fill the
   values (a `backup_ro` Neon role with SELECT-only is enough).
3. Cron: `30 2 * * * /opt/kushol/ops/backup.sh >> /opt/kushol/state/backups.log 2>&1`
4. Cron (Monday 03:10): `/opt/kushol/ops/redaction-probe.sh` (OPS-BE-014).
5. Cron (every minute): `/opt/kushol/ops/uptime-check.sh` with `HEALTHCHECKS_IO_URL` set to the
   platform monitor's ping URL — external paging survives a dark VPS.

## 2. What a backup is

`pg_dump -Fc` (custom format, compressed) from a `postgres:$PG_MAJOR` **client container**,
written under `/opt/kushol/state/backups/` with a `.sha256` sidecar, then rclone → R2 →
off-site; files older than 30 days are pruned locally. A `deploy.lock` file or < 2 GB disk
headroom skips the run and files an alarm instead of blocking a migration window.

## 3. Restore drill (quarterly + pre-pilot)

```bash
/opt/kushol/ops/restore.sh /opt/kushol/state/backups/kushol-YYYYMMDDTHHMMSSZ.dump.gz
```

1. Create a scratch Neon branch/DB (`kushol_drill`); put its URL in `RESTORE_DATABASE_URL`.
2. Run the command above — it checksums, restores with `--clean --if-exists`, then runs
   row-count sanity over `schools`/`users`/`sections`.
3. Point a scratch compose stack at the restored DB, hit `/readyz` + login once.
4. File evidence (date, backup name, counts, smoke result) in the module `07-progress.md`.
   Any failure is an incident entry and **blocks pilot sign-off** (BR-007).
