#!/usr/bin/env bash
# ops/deploy.sh <env> [api=<tag>] [web=<tag>] — the only sanctioned deploy path (OPS-BE-007).
#
#   lock → validate tags and env files → pull (on failure nothing has changed) → schema check with
#   the new api image (read-only `migrate-status`; this script never migrates — Gate 2 is the
#   owner's) → `up -d` → /readyz gate ≤ 120 s → smoke → release log.
#   Gate or smoke red → automatic rollback to the release that was serving, incident entry, exit 1.
#
# api and web come from separate repos, so each has its own tag; a tag left out keeps the one
# deployed now. Run as the deploy user (docker group). Non-interactive and cron-safe: progress on
# stderr, one result line on stdout.
#
# Exit codes: 0 serving · 1 failed (rolled back when possible) · 2 usage or precondition ·
#             3 database behind the new image · 4 database dirty · 5 image pull failed
set -euo pipefail
# shellcheck source=deploy/ops/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: ops/deploy.sh <env> [api=<tag>] [web=<tag>] [--no-rollback]" >&2
  exit "$EXIT_USAGE"
}

[[ $# -ge 1 ]] || usage
env_name=$1
shift
api_tag="" web_tag="" auto_rollback=yes note=""
for arg in "$@"; do
  case $arg in
    api=*) api_tag=${arg#api=} ;;
    web=*) web_tag=${arg#web=} ;;
    --no-rollback) auto_rollback=no ;;
    --note=*) note=${arg#--note=} ;;
    *) usage ;;
  esac
done

load_stack
[[ $env_name == "$KUSHOL_ENV" ]] || die "$EXIT_USAGE" "env '$env_name' does not match KUSHOL_ENV=$KUSHOL_ENV (env/stack.env)"
mkdir -p "$KC_STATE"
take_lock
for name in stack api web; do check_env_file "$name"; done

read -r cur_api cur_web <<<"$(read_release "$KC_STATE/release.env")"
api_tag=${api_tag:-$cur_api}
web_tag=${web_tag:-$cur_web}
[[ -n $api_tag && -n $web_tag ]] || die "$EXIT_USAGE" "the first deploy needs both api=<tag> and web=<tag>"
for tag in "$api_tag" "$web_tag"; do
  valid_tag "$tag" || die "$EXIT_USAGE" "invalid tag '$tag' — want main-<sha7> or release-<sha> (never latest)"
done

candidate="$KC_STATE/release.candidate.env"
trap 'rm -f "$candidate"' EXIT
write_release "$candidate" "$api_tag" "$web_tag"
log "deploy $env_name api=$api_tag web=$web_tag (serving: api=${cur_api:-none} web=${cur_web:-none})"

# 1. Pull first: a registry failure leaves the running stack untouched (edge case 3).
# shellcheck disable=SC2317 # invoked through retry
pull() { KC_RELEASE_FILE=$candidate kc_compose pull --quiet api worker web redis >&2; }
retry 3 pull || die "$EXIT_PULL" "image pull failed — nothing changed (is the kushol user logged in to the registry? sudo -iu kushol docker login docker.io)"

# 2. Schema check with the NEW api image, read-only. The database must already be at (or past) the
#    migration version this image embeds; the owner applies migrations by hand (Gate 2).
schema_status() { KC_RELEASE_FILE=$candidate kc_compose run --rm --no-deps -T api migrate-status 2>&1; }
status_rc=0
for attempt in 1 2 3; do
  if status_out=$(schema_status); then status_rc=0; else status_rc=$?; fi
  [[ $status_rc -eq 1 && $attempt -lt 3 ]] || break # 1 = could not reach Neon (cold start): retry
  log "migrate-status could not reach the database — retrying"
  sleep "$KC_RETRY_DELAY"
done
status_line=$(grep -o 'database_version=[^ ]* expected_version=[^ ]* dirty=[a-z]*' <<<"$status_out" | tail -1 || true)
case $status_rc in
  0) log "schema ok: $status_line" ;;
  3) die "$EXIT_SCHEMA_BEHIND" "database is BEHIND api=$api_tag ($status_line). Owner (Gate 2): ops/migrate.sh $api_tag up --confirm, then rerun this deploy. Nothing changed." ;;
  4) die "$EXIT_SCHEMA_DIRTY" "database schema is DIRTY ($status_line) — a migration failed midway; fix per DEPLOYMENT.md before deploying. Nothing changed." ;;
  *) die "$EXIT_FAILED" "migrate-status failed (exit $status_rc). Nothing changed. Output: $status_out" ;;
esac

gate() {
  wait_http "http://127.0.0.1:$API_PORT/readyz" "$KC_GATE_TIMEOUT" || {
    log "gate: /readyz not 200 within $KC_GATE_TIMEOUT s (ops.deploy.readyzTimeout)"
    return 1
  }
  wait_http "http://127.0.0.1:$WEB_PORT/" "$KC_GATE_TIMEOUT" || {
    log "gate: web not answering within $KC_GATE_TIMEOUT s"
    return 1
  }
  "$KC_ROOT/ops/smoke.sh" >&2 || {
    log "gate: smoke failed — a green /readyz is not enough (edge case 2)"
    return 1
  }
}

diagnostics() {
  kc_compose ps >&2 || true
  kc_compose logs --no-color --tail 40 api worker web >&2 || true
}

# 3. Swap. `up -d` replaces only the services whose image changed — a brief restart; WebSocket
#    clients reconnect.
cp "$candidate" "$KC_STATE/release.env"
if kc_compose up -d --remove-orphans >&2 && gate; then
  log_release "$env_name" "$api_tag" "$web_tag" SERVING "$note"
  log "serving api=$api_tag web=$web_tag"
  echo "SERVING $env_name api=$api_tag web=$web_tag"
  exit "$EXIT_OK"
fi

diagnostics
log_release "$env_name" "$api_tag" "$web_tag" FAILED "$note"
incident "deploy api=$api_tag web=$web_tag failed the gate/smoke"

if [[ $auto_rollback == yes && -n $cur_api && -n $cur_web ]]; then
  log "rolling back to api=$cur_api web=$cur_web"
  write_release "$KC_STATE/release.env" "$cur_api" "$cur_web"
  if kc_compose up -d --remove-orphans >&2 && gate; then
    log_release "$env_name" "$cur_api" "$cur_web" SERVING auto-rollback
    incident "auto-rollback to api=$cur_api web=$cur_web: serving"
    echo "ROLLED_BACK $env_name api=$cur_api web=$cur_web"
  else
    diagnostics
    log_release "$env_name" "$cur_api" "$cur_web" ROLLBACK_FAILED auto-rollback
    incident "auto-rollback to api=$cur_api web=$cur_web FAILED: stack degraded (DEPLOYMENT.md §7)"
    echo "ROLLBACK_FAILED $env_name api=$cur_api web=$cur_web"
  fi
else
  echo "FAILED $env_name api=$api_tag web=$web_tag"
fi
exit "$EXIT_FAILED"
