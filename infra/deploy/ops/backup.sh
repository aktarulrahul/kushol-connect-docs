#!/usr/bin/env bash
# deploy/ops/backup.sh — nightly backup (OPS-BE-009): pg_dump -Fc from a version-matched
# postgres client container → .sha256 → R2 (versioned bucket) → off-site rclone → prune.
# Skips + alarms on deploy-lock or low disk; never blocks a migration window (02 §5).
# Root-run on the VPS via cron 02:30 Asia/Dhaka; container-free tests cover the pure helpers.
set -uo pipefail

# shellcheck source=deploy/ops/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KC_BACKUP_ENV="${KC_BACKUP_ENV:-$KC_ENV_DIR/backup.env}"
KC_BACKUP_DIR="${KC_BACKUP_DIR:-$KC_STATE/backups}"
KC_BACKUP_LOG="${KC_BACKUP_LOG:-$KC_STATE/backups.log}"
KC_KEEP_DAYS=${KC_KEEP_DAYS:-30}
KC_MIN_DISK_MB=${KC_MIN_DISK_MB:-2048}
KC_LOCK="${KC_STATE}/deploy.lock"

[[ -f $KC_BACKUP_ENV ]] || die "$EXIT_USAGE" "missing $KC_BACKUP_ENV (copy env/backup.env.example)"
# shellcheck disable=SC1090
. "$KC_BACKUP_ENV"
: "${BACKUP_DATABASE_URL:?BACKUP_DATABASE_URL required}" "${BACKUP_R2_REMOTE:?BACKUP_R2_REMOTE required}" \
  "${BACKUP_OFFSITE_REMOTE:?BACKUP_OFFSITE_REMOTE required}" "${PG_MAJOR:?PG_MAJOR required}"

note() { printf '%s %s\n' "$(now)" "$*" >>"$KC_BACKUP_LOG"; }
alarm() { note "ALARM $*"; printf '%s %s\n' "$(now)" "backup: $*" >>"$KC_INCIDENTS_LOG"; }

# skip_if_locked — a deploy in flight owns the DB dump window; retry tomorrow (02 §5). The lock
# file itself always exists after the first deploy: only a held flock means "deploy running".
skip_if_locked() {
  exec 8>"$KC_LOCK"
  if ! flock -n 8; then
    alarm "a deploy holds deploy.lock — backup skipped (retry tomorrow)"
    exit "$EXIT_OK"
  fi
  # Keep holding it: a deploy started now waits for the dump instead of racing it.
}

# disk_free_mb DIR — headroom guard before writing dumps.
disk_free_mb() { df -Pm "$1" | awk 'NR == 2 { print $4 }'; }

# prune_list DIR NOW_EPOCH KEEP_DAYS — files older than the window (pure; unit-tested).
prune_list() {
  local dir=$1 now_epoch=$2 keep=$3 f epoch
  local cutoff=$((now_epoch - keep * 86400))
  for f in "$dir"/*.dump.gz "$dir"/*.dump.gz.sha256; do
    [[ -f $f ]] || continue
    # GNU (server) first: GNU `stat -f` means --file-system and would print junk here.
    epoch=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || continue
    ((epoch < cutoff)) && printf '%s\n' "$f"
  done
  return 0
}

main() {
  skip_if_locked
  mkdir -p "$KC_BACKUP_DIR"
  local free
  free=$(disk_free_mb "$KC_BACKUP_DIR")
  if ((free < KC_MIN_DISK_MB)); then
    alarm "low disk ${free}MB < ${KC_MIN_DISK_MB}MB — backup skipped"
    exit "$EXIT_FAILED"
  fi
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  local out="$KC_BACKUP_DIR/kushol-$stamp.dump"
  log "pg_dump (postgres:$PG_MAJOR client) → $out"
  docker run --rm -v "$KC_BACKUP_DIR:/out" "postgres:$PG_MAJOR" \
    pg_dump -Fc --no-owner --dbname="$BACKUP_DATABASE_URL" -f "/out/$(basename "$out")" \
    || { alarm "pg_dump failed"; exit "$EXIT_FAILED"; }
  gzip -f "$out"
  out="$out.gz"
  # Bare file name inside, so the sidecar verifies wherever the pair is downloaded to.
  (cd "$KC_BACKUP_DIR" && shasum -a 256 "$(basename "$out")" >"$(basename "$out").sha256") \
    || die "$EXIT_FAILED" "checksum"
  if command -v rclone >/dev/null; then
    rclone copy "$out" "$BACKUP_R2_REMOTE:kushol-backups" || { alarm "R2 upload failed"; exit "$EXIT_FAILED"; }
    rclone copy "$out.sha256" "$BACKUP_R2_REMOTE:kushol-backups" || true
    rclone copy "$out" "$BACKUP_OFFSITE_REMOTE:kushol-backups" \
      || alarm "off-site copy failed (R2 copy is authoritative)"
  else
    alarm "rclone not found — dumps remain local only"
  fi
  local old total=0
  for old in $(prune_list "$KC_BACKUP_DIR" "$(date +%s)" "$KC_KEEP_DAYS"); do
    rm -f "$old" && total=$((total + 1))
  done
  note "ok $out (pruned $total)"
  log "backup ok → $out"
}

main "$@"
