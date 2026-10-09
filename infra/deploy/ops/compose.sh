#!/usr/bin/env bash
# ops/compose.sh ARGS — `docker compose` for the kushol stack with the right files and the deployed
# tags. For looking and nudging: ps, logs -f api, restart web, top. Deploys go through deploy.sh.
set -euo pipefail
# shellcheck source=deploy/ops/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ -r $KC_RELEASE_FILE ]] || die "$EXIT_USAGE" "nothing deployed yet ($KC_RELEASE_FILE missing) — run ops/deploy.sh"
kc_compose "$@"
