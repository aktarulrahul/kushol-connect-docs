#!/usr/bin/env bash
# host/first-deploy.sh api=<tag> web=<tag> — the whole first deployment of web + api, run as root on
# the VPS after syncing the bundle to /opt/kushol (DEPLOYMENT.md §2, "fast path"):
#
#   ssh -t root@72.61.114.20 bash /opt/kushol/host/first-deploy.sh api=main-<sha7> web=main-<sha7>
#
# Needs a terminal (-t): it reads the Neon URL and the registry token interactively.
# It chains the existing scripts and stops only for what the owner must type or decide:
#   1 host/prepare-host.sh          Docker, swap, kushol user, env files
#   2 env/api.env                   asks for the Neon production URL (hidden); generates the secrets
#   3 registry login                as kushol, only if the api image cannot be pulled yet
#   4 hestia/setup-web.sh           domains + Kushol Nginx templates (+ certificates if DNS is ready)
#   5 migrations (Gate 2)           shows the status; applies only after you type "apply"
#   6 ops/deploy.sh                 gated deploy, smoke on the loopback ports
#   7 public check                  when DNS points here: certificates, HTTPS, www → apex, public smoke
# Safe to rerun: every step skips what is already done.
set -euo pipefail

KC_ROOT=/opt/kushol
API_ENV=$KC_ROOT/env/api.env
STACK_ENV=$KC_ROOT/env/stack.env

say() { printf '\n==== %s\n' "$*"; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
as_kushol() { sudo -iu kushol "$@"; }

api_tag="" web_tag=""
for arg in "$@"; do
  case $arg in
    api=*) api_tag=${arg#api=} ;;
    web=*) web_tag=${arg#web=} ;;
    *) die "usage: first-deploy.sh api=main-<sha7> web=main-<sha7>" ;;
  esac
done
for tag in "$api_tag" "$web_tag"; do
  [[ $tag =~ ^(main|release)-[0-9a-f]{7,40}$ ]] || die "usage: first-deploy.sh api=main-<sha7> web=main-<sha7> (got '$tag')"
done
[[ $(id -u) -eq 0 ]] || die "run as root: sudo bash $0 $*"
[[ -t 0 ]] || die "needs a terminal for the prompts — use ssh -t"
[[ -r $KC_ROOT/compose.yaml ]] || die "sync the bundle to $KC_ROOT first (DEPLOYMENT.md §3.2)"

# ── 1 ────────────────────────────────────────────────────────────────────────────────────────────
say "1/7 Host preparation"
bash "$KC_ROOT/host/prepare-host.sh"
set -a
# shellcheck source=/dev/null
. "$STACK_ENV"
set +a

# ── 2 ────────────────────────────────────────────────────────────────────────────────────────────
say "2/7 Secrets in env/api.env"
value_of() { awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$API_ENV"; }
needs_value() {
  local v
  v=$(value_of "$1")
  [[ -z $v || $v == *REPLACE* ]]
}
# set_key KEY VALUE — the value travels through the environment, so no character needs escaping.
set_key() {
  local tmp
  tmp=$(mktemp "$API_ENV.XXXXXX") # mode 600: secrets are never world-readable, even briefly
  KC_KEY=$1 KC_VAL=$2 awk 'BEGIN { k = ENVIRON["KC_KEY"]; v = ENVIRON["KC_VAL"] }
    index($0, k "=") == 1 { print k "=" v; next } { print }' "$API_ENV" >"$tmp"
  cat "$tmp" >"$API_ENV" # keeps the file's owner and mode (kushol, 600)
  rm -f "$tmp"
}
if needs_value DATABASE_URL; then
  echo "Neon console → kushol-connect-db → branch production → Connect → copy the connection string."
  read -rsp "Neon DATABASE_URL (input hidden; pooled or direct): " url
  echo
  [[ $url =~ ^postgres(ql)?:// ]] || die "that is not a postgres:// URL — rerun"
  # Migrations need the direct endpoint (golang-migrate's advisory lock fails through the pooler).
  # Neon names the pooled host ep-<id>-pooler.<region>…; the direct host is the same without -pooler.
  if [[ $url == *-pooler.* ]]; then
    url=${url/-pooler./.}
    echo "pooled URL given — using the direct endpoint (removed -pooler from the host)"
  fi
  set_key DATABASE_URL "$url"
  echo "DATABASE_URL set"
else
  echo "DATABASE_URL already set"
fi
generated=""
for key in JWT_SECRET OTP_PEPPER PAYMENTS_WEBHOOK_SECRET ERP_SECRET_KEY; do
  if needs_value "$key"; then
    bytes=48
    [[ $key == ERP_SECRET_KEY ]] && bytes=32 # AES-256 key: base64 of exactly 32 bytes
    set_key "$key" "$(openssl rand -base64 "$bytes" | tr -d '\n')"
    generated="$generated $key"
  fi
done
if [[ -n $generated ]]; then
  echo "generated on this server:$generated"
  echo "Copy $API_ENV into your password manager now — ERP_SECRET_KEY encrypts stored ERP secrets;"
  echo "if the server is lost without it, those secrets cannot be decrypted."
else
  echo "all secrets already set"
fi

# ── 3 ────────────────────────────────────────────────────────────────────────────────────────────
say "3/7 Registry access for the kushol user"
api_ref="$API_IMAGE:${API_TAG_PREFIX-}$api_tag"
web_ref="$WEB_IMAGE:${WEB_TAG_PREFIX-}$web_tag"
registry=${API_IMAGE%%/*}
[[ $registry == *.* ]] || registry=docker.io
if as_kushol docker pull --quiet "$api_ref" >/dev/null 2>&1; then
  echo "kushol can pull $api_ref"
else
  echo "Log in to $registry with a READ-ONLY access token (Docker Hub → Account settings → Personal access tokens → Read-only), not your password."
  as_kushol docker login "$registry"
  as_kushol docker pull --quiet "$api_ref" >/dev/null || die "cannot pull $api_ref — was it pushed? (deploy/docs/images.md §2)"
fi
as_kushol docker pull --quiet "$web_ref" >/dev/null || die "cannot pull $web_ref — was it pushed?"
echo "both images available"

# ── 4 ────────────────────────────────────────────────────────────────────────────────────────────
say "4/7 HestiaCP web domains and Nginx templates"
bash "$KC_ROOT/hestia/setup-web.sh"

# ── 5 ────────────────────────────────────────────────────────────────────────────────────────────
say "5/7 Database migrations (Gate 2 — owner decision)"
rc=0
as_kushol "$KC_ROOT/ops/migrate.sh" "$api_tag" status || rc=$?
case $rc in
  0) echo "database is up to date with api=$api_tag" ;;
  3)
    echo
    echo "The production database (env/api.env DATABASE_URL) is BEHIND api=$api_tag."
    echo "Applying runs every pending migration in that image against PRODUCTION. Expand/contract"
    echo "migrations are additive, but this cannot be undone from here (Neon branch restore can)."
    read -rp 'Type "apply" to apply them now (anything else stops): ' answer
    [[ $answer == apply ]] || die "stopped before migrations — rerun when ready"
    as_kushol "$KC_ROOT/ops/migrate.sh" "$api_tag" up --confirm
    ;;
  4) die "the schema is DIRTY (a migration failed midway) — fix forward first (DEPLOYMENT.md §7)" ;;
  *) die "migrate-status failed (exit $rc) — check DATABASE_URL and that Neon is reachable" ;;
esac

# ── 6 ────────────────────────────────────────────────────────────────────────────────────────────
say "6/7 Deploy"
as_kushol "$KC_ROOT/ops/deploy.sh" "$KUSHOL_ENV" "api=$api_tag" "web=$web_tag"

# ── 7 ────────────────────────────────────────────────────────────────────────────────────────────
say "7/7 Public front door"
resolves_here() { getent ahostsv4 "$1" | awk -v ip="$PUBLIC_IP" '{ seen = 1; if ($1 != ip) bad = 1 } END { exit !(seen && !bad) }'; }
if resolves_here "$SITE_DOMAIN" && resolves_here "www.$SITE_DOMAIN" && resolves_here "$API_DOMAIN"; then
  bash "$KC_ROOT/hestia/setup-web.sh" # certificates, HTTPS, HSTS, www → apex (skips what exists)
  sed -i 's/^SMOKE_MODE=.*/SMOKE_MODE=public/' "$STACK_ENV"
  as_kushol "$KC_ROOT/ops/smoke.sh" public
  say "Live: https://$SITE_DOMAIN and https://$API_DOMAIN"
else
  say "Deployed and healthy on the server; not public yet"
  cat <<EOF
DNS does not point here yet. In hPanel → Domains → $SITE_DOMAIN → DNS set:
  A  @    $PUBLIC_IP   (replaces the parking address)
  A  api  $PUBLIC_IP
(www is a CNAME to the apex already.) When 'dig +short $SITE_DOMAIN' shows $PUBLIC_IP, rerun:
  sudo bash $KC_ROOT/host/first-deploy.sh api=$api_tag web=$web_tag
Finished steps are skipped; it then issues the certificates and runs the public smoke check.
EOF
fi
