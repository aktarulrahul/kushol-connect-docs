#!/usr/bin/env bash
# ops/migrate.sh <api-tag> status | up --confirm — OWNER-RUN ONLY (Gate 2).
#
# Runs that api image's own migrate subcommands against DATABASE_URL in env/api.env (the Neon
# production branch). `status` is read-only; `up` changes the production schema and needs
# --confirm, exactly like `api migrate up --confirm`. ops/deploy.sh never calls this: it only
# checks the version and stops when the database is behind.
set -euo pipefail
# shellcheck source=deploy/ops/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: ops/migrate.sh <api-tag> status | up --confirm" >&2
  exit "$EXIT_USAGE"
}
[[ $# -ge 2 ]] || usage
tag=$1
action=$2
valid_tag "$tag" || die "$EXIT_USAGE" "invalid tag '$tag'"

load_stack
check_env_file api
mkdir -p "$KC_STATE"
release=$(mktemp "$KC_STATE/release.migrate.XXXXXX")
trap 'rm -f "$release"' EXIT
# Only the api service runs; WEB_TAG just satisfies the compose file's interpolation.
write_release "$release" "$tag" "$tag"
export KC_RELEASE_FILE=$release

kc_compose pull --quiet api
case $action in
  status)
    kc_compose run --rm --no-deps -T api migrate-status
    ;;
  up)
    [[ ${3:-} == --confirm ]] || die "$EXIT_USAGE" "add --confirm: this applies migrations to the production database"
    log "applying migrations from api=$tag to the database in env/api.env"
    kc_compose run --rm --no-deps -T api migrate up --confirm
    ;;
  *) usage ;;
esac
