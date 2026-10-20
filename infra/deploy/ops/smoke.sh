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

# check_nginx_templates — warn (never fail: the fix needs root, and a rollback would not help) when
# an installed Kushol template lacks a route the bundle's copy has. Synced template edits only take
# effect once hestia/setup-web.sh re-installs and re-applies them; until then Nginx keeps the old
# routes (2026-10-20: the site domain had no /api/v1/ws location, so browsers got no realtime).
check_nginx_templates() {
  local dir name ext want have
  for dir in /usr/local/hestia/data/templates/web/nginx /usr/local/hestia/data/templates/web/nginx/php-fpm; do
    [[ -r $dir/kushol-web.stpl ]] && break
  done
  [[ -r $dir/kushol-web.stpl ]] || return 0 # not a HestiaCP host (or templates not installed yet)
  for name in kushol-web kushol-api; do
    for ext in tpl stpl; do
      want=$(grep -E '^[[:space:]]*location ' "$KC_ROOT/hestia/templates/$name.$ext" | sort) || true
      have=$(grep -E '^[[:space:]]*location ' "$dir/$name.$ext" 2>/dev/null | sort) || true
      if [[ $want != "$have" ]]; then
        log "smoke WARN nginx template $name.$ext is older than the bundle — as root: bash $KC_ROOT/hestia/setup-web.sh"
      fi
    done
  done
}
check_nginx_templates

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
