#!/usr/bin/env bash
# deploy/ops/redaction-probe.sh — weekly log discipline probe (OPS-BE-014, FND-BR-006 live):
# samples recent api/web container logs and fails on secret-shaped patterns. A failure is an
# incident entry + rotation-runbook check (06 §9), never silent.
set -uo pipefail

# shellcheck source=deploy/ops/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PATTERNS='Authorization: Bearer|X-Kushol-Signature:|password=|passwd=|secret=|ERP_SECRET|PAYMENTS_WEBHOOK_SECRET|jwt_secret|ksh_[A-Za-z0-9]{20,}|sk_live_|BEGIN (RSA )?PRIVATE KEY'

hits=""
for svc in api worker web; do
  # kc_compose supplies the stack's env files; plain `docker compose` fails interpolation. A probe
  # that cannot read the logs must fail, never report "clean".
  if ! logs=$(kc_compose logs --no-color --since 24h "$svc" 2>&1); then
    die "$EXIT_FAILED" "cannot read $svc logs: $logs"
  fi
  sample=$(grep -E "$PATTERNS" <<<"$logs" | head -5) || true
  [[ -z $sample ]] || hits="$hits
[$svc] $sample"
done

if [[ -n ${hits//[[:space:]]/} ]]; then
  {
    printf '%s redaction-probe: SECRET-SHAPED STRINGS IN LOGS\n%s\n' "$(now)" "$hits"
  } >>"$KC_INCIDENTS_LOG"
  log "PROBE FAILED — see incidents.log; run docs/secret-rotation.md §7"
  exit "$EXIT_FAILED"
fi
log "redaction probe clean"
