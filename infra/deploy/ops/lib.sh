# shellcheck shell=bash
# Shared helpers for the ops scripts (module 15, OPS-BE-007/008). Sourced, never executed.
# Layout on the server (deploy/docs/stack.md §2): /opt/kushol/{compose.yaml,ops/,env/,state/}.
# The pure helpers (tags, env files, release log) are unit-tested by deploy/tests/run.sh and stay
# portable to the macOS bash 3.2 that runs those tests.

KC_ROOT="${KC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
KC_ENV_DIR="$KC_ROOT/env"
KC_STATE="$KC_ROOT/state"
KC_RELEASE_FILE="${KC_RELEASE_FILE:-$KC_STATE/release.env}"
KC_RELEASES_LOG="$KC_STATE/releases.log"
KC_INCIDENTS_LOG="$KC_STATE/incidents.log"
# Tunables (deploy/tests/flow.sh shortens them): gate deadline per check, pause between retries.
KC_GATE_TIMEOUT=${KC_GATE_TIMEOUT:-120}
KC_RETRY_DELAY=${KC_RETRY_DELAY:-5}

# Exit codes — documented in DEPLOYMENT.md §6 and deploy/docs/scripts.md; additive only (06 §7).
# One assignment command, so the directive covers all of them (they are used by the callers).
# shellcheck disable=SC2034
EXIT_OK=0 EXIT_FAILED=1 EXIT_USAGE=2 EXIT_SCHEMA_BEHIND=3 EXIT_SCHEMA_DIRTY=4 EXIT_PULL=5

# Progress goes to stderr; stdout carries the one machine-readable result line.
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
die() {
  local code=$1
  shift
  log "ERROR: $*"
  exit "$code"
}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# valid_tag TAG — only immutable git-SHA tags deploy (OPS-UT-003, OPS-BR-005); never `latest`.
valid_tag() { [[ $1 =~ ^(main|release)-[0-9a-f]{7,40}$ ]]; }

# env_value FILE KEY — the value of KEY in a KEY=VALUE file (last assignment wins; empty if absent).
env_value() { awk -v k="$2" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$1"; }

# required_keys EXAMPLE — the keys an .env.example leaves uncommented; those are required.
required_keys() { grep -E '^[A-Z][A-Z0-9_]*=' "$1" | cut -d= -f1 || true; }

# missing_keys EXAMPLE ACTUAL — required keys absent, empty or still holding a REPLACE placeholder.
missing_keys() {
  local key value
  for key in $(required_keys "$1"); do
    value=$(env_value "$2" "$key")
    if [[ -z $value || $value == *REPLACE* ]]; then echo "$key"; fi
  done
}

# check_env_file NAME — env/NAME.env exists, is chmod 600 and holds every required key (OPS-US-005).
check_env_file() {
  local file="$KC_ENV_DIR/$1.env" example="$KC_ENV_DIR/$1.env.example" mode missing
  [[ -r $example ]] || die "$EXIT_USAGE" "missing $example — re-sync the deploy bundle"
  [[ -r $file ]] || die "$EXIT_USAGE" "missing $file — copy $example and fill it"
  mode=$(stat -c %a "$file")
  [[ $mode == 600 ]] || die "$EXIT_USAGE" "$file must be chmod 600 (it is $mode)"
  missing=$(missing_keys "$example" "$file")
  [[ -z $missing ]] || die "$EXIT_USAGE" "$file is incomplete (ops.config.envIncomplete): $(echo "$missing" | tr '\n' ' ')"
}

# load_stack — exports env/stack.env (ports, images, domains) for the scripts.
load_stack() {
  local file="$KC_ENV_DIR/stack.env"
  [[ -r $file ]] || die "$EXIT_USAGE" "missing $file — copy env/stack.env.example"
  set -a
  # shellcheck source=/dev/null
  . "$file"
  set +a
}

# kc_compose ARGS — docker compose for the kushol project with its env files.
kc_compose() {
  docker compose --project-name kushol --project-directory "$KC_ROOT" \
    -f "$KC_ROOT/compose.yaml" \
    --env-file "$KC_ENV_DIR/stack.env" --env-file "$KC_RELEASE_FILE" "$@"
}

# take_lock — one deploy/rollback at a time (edge case 1). rollback.sh takes it and hands it to
# deploy.sh through KC_LOCK_HELD (fd 9 survives exec).
take_lock() {
  [[ ${KC_LOCK_HELD:-} == 1 ]] && return 0
  exec 9>"$KC_STATE/deploy.lock"
  flock -n 9 || die "$EXIT_USAGE" "another deploy or rollback holds $KC_STATE/deploy.lock"
  export KC_LOCK_HELD=1
}

# read_release FILE — prints "API_TAG WEB_TAG" (both empty before the first deploy).
read_release() {
  if [[ -r $1 ]]; then
    printf '%s %s\n' "$(env_value "$1" API_TAG)" "$(env_value "$1" WEB_TAG)"
  else
    echo ""
  fi
}

# write_release FILE API_TAG WEB_TAG — atomically.
write_release() {
  printf 'API_TAG=%s\nWEB_TAG=%s\n' "$2" "$3" >"$1.tmp"
  mv "$1.tmp" "$1"
}

# log_release ENV API_TAG WEB_TAG RESULT [NOTE] — appends to state/releases.log:
#   <UTC timestamp> <env> api=<tag> web=<tag> <SERVING|FAILED|ROLLED_BACK|ROLLBACK_FAILED> [note]
log_release() {
  printf '%s %s api=%s web=%s %s%s\n' "$(now)" "$1" "$2" "$3" "$4" "${5:+ $5}" >>"$KC_RELEASES_LOG"
}

# previous_release LOG API_TAG WEB_TAG — the rollback target: the newest release whose latest log
# line is SERVING and which is not the given one. Releases later marked FAILED or ROLLED_BACK are
# never targets, so repeated rollbacks walk backwards instead of bouncing (OPS-US-004).
previous_release() {
  [[ -r $1 ]] || return 0
  awk -v cur="api=$2 web=$3" '
    NF >= 5 { pair = $3 " " $4; status[pair] = $5; seq[pair] = NR }
    END {
      best = 0
      for (p in status) if (status[p] == "SERVING" && p != cur && seq[p] > best) { best = seq[p]; out = p }
      if (out != "") { gsub(/api=|web=/, "", out); print out }
    }' "$1"
}

# incident TEXT — one line in state/incidents.log; DEPLOYMENT.md §8 has the full incident template.
incident() { printf '%s %s %s\n' "$(now)" "${KUSHOL_ENV:-?}" "$*" >>"$KC_INCIDENTS_LOG"; }

# retry N CMD… — N attempts with a growing pause (registry pulls, Neon waking up).
retry() {
  local attempts=$1 n=1
  shift
  until "$@"; do
    ((n >= attempts)) && return 1
    log "attempt $n failed — retrying in $((n * KC_RETRY_DELAY)) s"
    sleep $((n * KC_RETRY_DELAY))
    n=$((n + 1))
  done
}

# wait_http URL SECONDS — polls until HTTP 200 (redirects followed) or the deadline passes. Backs off
# from 2 s to 10 s, so a Neon cold start is tolerated rather than read as red (edge case 4).
wait_http() {
  local url=$1 deadline=$((SECONDS + $2)) delay=2
  while ((SECONDS < deadline)); do
    if curl -fsSL -o /dev/null --max-time 5 "$url" 2>/dev/null; then return 0; fi
    sleep "$delay"
    ((delay < 10)) && delay=$((delay + 2))
  done
  return 1
}
