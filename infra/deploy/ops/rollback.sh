#!/usr/bin/env bash
# ops/rollback.sh <env> — redeploy the previous release from state/releases.log (OPS-BE-008).
#
# The target is mechanical, never memory: the newest release whose latest log line is SERVING and
# that is not the one serving now. The abandoned release is marked ROLLED_BACK so a second
# rollback walks further back. Only logged releases are targets and nothing is rebuilt (OPS-BR-005);
# images are usually still on the host, so this takes well under the 5-minute target.
# Exit codes: as ops/deploy.sh.
set -euo pipefail
# shellcheck source=deploy/ops/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || {
  echo "usage: ops/rollback.sh <env>" >&2
  exit "$EXIT_USAGE"
}
env_name=$1

load_stack
[[ $env_name == "$KUSHOL_ENV" ]] || die "$EXIT_USAGE" "env '$env_name' does not match KUSHOL_ENV=$KUSHOL_ENV (env/stack.env)"
mkdir -p "$KC_STATE"
take_lock

read -r cur_api cur_web <<<"$(read_release "$KC_STATE/release.env")"
[[ -n $cur_api && -n $cur_web ]] || die "$EXIT_USAGE" "nothing is deployed yet"
target=$(previous_release "$KC_RELEASES_LOG" "$cur_api" "$cur_web")
[[ -n $target ]] || die "$EXIT_USAGE" "no earlier SERVING release in $KC_RELEASES_LOG — nothing to roll back to"
read -r target_api target_web <<<"$target"

log "rollback $env_name: api=$cur_api web=$cur_web → api=$target_api web=$target_web"
log_release "$env_name" "$cur_api" "$cur_web" ROLLED_BACK operator
incident "operator rollback from api=$cur_api web=$cur_web to api=$target_api web=$target_web"
exec "$KC_ROOT/ops/deploy.sh" "$env_name" "api=$target_api" "web=$target_web" --no-rollback --note=rollback
