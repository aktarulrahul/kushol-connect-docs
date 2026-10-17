#!/usr/bin/env bash
# deploy/ops/restore.sh — restore drill / incident restore (OPS-BE-010): checksum → pg_restore
# into a SCRATCH target → row-count sanity → optional api smoke. Never targets prod implicitly:
# RESTORE_DATABASE_URL must be a scratch/point-in-time Neon branch, never the live URL.
set -uo pipefail

# shellcheck source=deploy/ops/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KC_BACKUP_ENV="${KC_BACKUP_ENV:-$KC_ENV_DIR/backup.env}"
[[ -f $KC_BACKUP_ENV ]] || die "$EXIT_USAGE" "missing $KC_BACKUP_ENV"
# shellcheck disable=SC1090
. "$KC_BACKUP_ENV"
: "${RESTORE_DATABASE_URL:?RESTORE_DATABASE_URL (scratch!) required}" "${PG_MAJOR:?PG_MAJOR required}"

[[ $# == 1 ]] || die "$EXIT_USAGE" "usage: restore.sh BACKUP.dump.gz"
[[ -f $1 ]] || die "$EXIT_USAGE" "no such backup: $1"
local_file=$1

(cd "$(dirname "$local_file")" && shasum -a 256 -c "$(basename "$local_file").sha256") >/dev/null 2>&1 \
  || { printf '%s restore: CHECKSUM FAILED %s\n' "$(now)" "$local_file" >>"$KC_INCIDENTS_LOG"; die "$EXIT_FAILED" "checksum mismatch — aborting"; }

log "pg_restore → scratch target (postgres:$PG_MAJOR client)"
docker run --rm -i "postgres:$PG_MAJOR" \
  pg_restore --no-owner --dbname="$RESTORE_DATABASE_URL" --clean --if-exists \
  < <(gunzip -c "$local_file") \
  || { printf '%s restore: FAILED %s\n' "$(now)" "$local_file" >>"$KC_INCIDENTS_LOG"; die "$EXIT_FAILED" "pg_restore failed"; }

# Row-count sanity on the tenant-critical tables (drill evidence for 07-progress).
docker run --rm "postgres:$PG_MAJOR" psql --dbname="$RESTORE_DATABASE_URL" -tAc \
  "SELECT 'schools=' || (SELECT count(*) FROM schools) || ' users=' || (SELECT count(*) FROM users) || ' sections=' || (SELECT count(*) FROM sections);" \
  || { printf '%s restore: SANITY FAILED\n' "$(now)" >>"$KC_INCIDENTS_LOG"; die "$EXIT_FAILED" "sanity queries failed"; }

log "restore ok — run the api smoke against a scratch stack, then file the drill evidence"
