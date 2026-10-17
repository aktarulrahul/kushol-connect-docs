#!/usr/bin/env bash
# deploy/ops/maintenance.sh — planned-downtime flag (OPS-BE-015): writes the flag file the
# Hestia templates check (503 + static bn/en page) and prints the runbook steps. Web keeps a
# build-time banner via NEXT_PUBLIC_MAINTENANCE_MODE (deploy/env/web.env.example).
set -uo pipefail

# shellcheck source=deploy/ops/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KC_MAINTENANCE_FLAG="${KC_MAINTENANCE_FLAG:-$KC_STATE/maintenance.flag}"
usage=$([[ ${1:-} == on || ${1:-} == off ]] && echo ok)
[[ $usage == ok ]] || die "$EXIT_USAGE" "usage: maintenance.sh on|off"
if [[ $1 == on ]]; then
  printf '%s\n' "$(now)" >"$KC_MAINTENANCE_FLAG"
  log "maintenance ON — Nginx now serves the static page; runbook: DEPLOYMENT.md §9 + docs/backups.md"
else
  rm -f "$KC_MAINTENANCE_FLAG"
  log "maintenance OFF — stack serves traffic again"
fi
