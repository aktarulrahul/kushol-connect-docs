#!/usr/bin/env bash
# deploy/ops/uptime-check.sh — minute-cron self-check (Part B, 01 §9 Q1): healthz + readyz +
# landing through the real front door. Failure → incidents.log (+ optional HEALTHCHECKS_IO_URL
# ping/fail so the external monitor pagers the owner even when the VPS is dark).
set -uo pipefail

# shellcheck source=deploy/ops/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KC_BASE_URL=${KC_BASE_URL:-https://kusholconnect.com}
KC_API_URL=${KC_API_URL:-https://api.kusholconnect.com}
HEALTHCHECKS_IO_URL=${HEALTHCHECKS_IO_URL:-}
fail() {
  printf '%s uptime: %s\n' "$(now)" "$1" >>"$KC_INCIDENTS_LOG"
  [[ -z $HEALTHCHECKS_IO_URL ]] || curl -fsS --max-time 5 "$HEALTHCHECKS_IO_URL/fail" >/dev/null 2>&1 || true
  exit "$EXIT_FAILED"
}
curl -fsS --max-time 10 "$KC_API_URL/healthz" >/dev/null || fail "api /healthz unreachable"
curl -fsS --max-time 10 "$KC_API_URL/readyz" >/dev/null || fail "api /readyz degraded"
curl -fsS --max-time 10 "$KC_BASE_URL/" >/dev/null || fail "web landing unreachable"
[[ -z $HEALTHCHECKS_IO_URL ]] || curl -fsS --max-time 5 "$HEALTHCHECKS_IO_URL" >/dev/null 2>&1 || true
