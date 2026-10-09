#!/usr/bin/env bash
# ops/smoke.sh [local|public] — post-deploy smoke (OPS-E2E-001, curl edition). ops/deploy.sh runs
# it after the /readyz gate; operators can run it any time. Mode defaults to SMOKE_MODE.
#
#   local  — the loopback ports only (before DNS and certificates exist)
#   public — the real front door: DNS → HestiaCP Nginx → TLS → containers
#
# The login round-trip joins this list when 03-identity-access is deployed (15 08-gaps.md G-4).
set -euo pipefail
# shellcheck source=deploy/ops/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_stack
mode=${1:-${SMOKE_MODE:-public}}
failed=0

# check NAME WANT_CODE URL [curl args…]
check() {
  local name=$1 want=$2 url=$3 got
  shift 3
  got=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null) || got=000
  if [[ $got == "$want" ]]; then
    log "smoke ok   $name ($got)"
  else
    log "smoke FAIL $name: $url → $got (want $want)"
    failed=1
  fi
}

# check_api_origin NAME URL — the response must come from the api (it stamps X-Request-Id on every
# response; the web app does not), proving Nginx routes /api/ same-origin to the api.
check_api_origin() {
  if curl -sS -o /dev/null -D - --max-time 10 "$2" 2>/dev/null | grep -qi '^x-request-id:'; then
    log "smoke ok   $1"
  else
    log "smoke FAIL $1: $2 did not reach the api"
    failed=1
  fi
}

case $mode in
  local)
    check "api liveness" 200 "http://127.0.0.1:$API_PORT/healthz"
    check "api readiness" 200 "http://127.0.0.1:$API_PORT/readyz"
    check "web landing" 200 "http://127.0.0.1:$WEB_PORT/" -L
    ;;
  public)
    check "api liveness" 200 "https://$API_DOMAIN/healthz"
    check "api readiness" 200 "https://$API_DOMAIN/readyz"
    check "web landing" 200 "https://$SITE_DOMAIN/" -L
    check "http → https" 301 "http://$SITE_DOMAIN/"
    check "www → apex" 301 "https://www.$SITE_DOMAIN/"
    check_api_origin "same-origin /api/ → api" "https://$SITE_DOMAIN/api/v1/"
    ;;
  *)
    die "$EXIT_USAGE" "usage: ops/smoke.sh [local|public]"
    ;;
esac

if [[ $failed -ne 0 ]]; then
  echo "SMOKE_FAILED $mode"
  exit "$EXIT_FAILED"
fi
echo "SMOKE_OK $mode"
