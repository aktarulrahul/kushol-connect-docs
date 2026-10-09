# shellcheck shell=bash
# Shared helpers for the HestiaCP setup scripts (module 15). Sourced; the scripts run as root on
# the server. Hestia CLI reference: https://hestiacp.com/docs/reference/cli.html

HESTIA=${HESTIA:-/usr/local/hestia}
VBIN=$HESTIA/bin
KC_ROOT=${KC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck disable=SC2034 # used by the scripts that source this file
E_EXISTS=4 # Hestia's exit code for "already exists"
CRED_FILE=""

say() { printf '\n== %s\n' "$*"; }
ok() { printf '   %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# preflight — root, HestiaCP present, stack settings loaded.
preflight() {
  [[ $(id -u) -eq 0 ]] || die "run as root: sudo bash $0"
  [[ -x $VBIN/v-list-user ]] || die "HestiaCP not found at $HESTIA"
  local stack=$KC_ROOT/env/stack.env
  [[ -r $stack ]] || stack=$KC_ROOT/env/stack.env.example
  # shellcheck source=/dev/null
  . "$stack"
  : "${SITE_DOMAIN:?} ${API_DOMAIN:?} ${PUBLIC_IP:?} ${HESTIA_USER:?} ${API_PORT:?} ${WEB_PORT:?}"
}

# hestia_conf KEY — a value from hestia.conf (KEY='value').
hestia_conf() { sed -n "s/^$1='\(.*\)'$/\1/p" "$HESTIA/conf/hestia.conf" | tail -n 1; }

# web_field / mail_field USER DOMAIN FIELD — one field (SSL, PROXY, REDIRECT…) of the domain's
# `v-list-… json` object.
web_field() { "$VBIN/v-list-web-domain" "$1" "$2" json | json_get "$3"; }
mail_field() { "$VBIN/v-list-mail-domain" "$1" "$2" json | json_get "$3"; }
json_get() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(iter(d.values())).get(sys.argv[1], ""))' "$1"; }

# resolves_here NAME — every IPv4 address NAME resolves to is this server's PUBLIC_IP.
resolves_here() {
  getent ahostsv4 "$1" | awk -v ip="$PUBLIC_IP" '{ seen = 1; if ($1 != ip) bad = 1 } END { exit !(seen && !bad) }'
}

# Hestia's CLI reads a password from a file when the argument is a path under /tmp, which keeps
# passwords off the process list and out of the panel's action log. Refuse to run without it.
supports_password_file() { grep -A4 '^is_password_valid()' "$HESTIA/func/main.sh" 2>/dev/null | grep -q '/tmp/'; }

new_password() { openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-24; }

# password_file PASSWORD — writes it to a private /tmp file and prints the path (caller deletes).
password_file() {
  local file
  file=$(mktemp /tmp/kc-pw.XXXXXXXX)
  chmod 600 "$file"
  printf '%s\n' "$1" >"$file"
  echo "$file"
}

# record_secret LABEL VALUE — new credentials go to one root-only file under /root, never to the
# terminal or a log. The owner moves them into the password manager and shreds the file.
record_secret() {
  if [[ -z $CRED_FILE ]]; then
    CRED_FILE=/root/kushol-credentials-$(date -u +%Y%m%dT%H%M%SZ).txt
    (
      umask 077
      {
        echo "# Kushol Connect credentials created $(date -u +%Y-%m-%dT%H:%M:%SZ) by $(basename "$0")"
        echo "# Move each into the password manager, share personal ones privately, then: shred -u $CRED_FILE"
      } >"$CRED_FILE"
    )
  fi
  printf '%-48s %s\n' "$1" "$2" >>"$CRED_FILE"
}

# ensure_hestia_user — the panel user that owns the Kushol web and mail domains.
ensure_hestia_user() {
  if "$VBIN/v-list-user" "$HESTIA_USER" >/dev/null 2>&1; then
    ok "HestiaCP user $HESTIA_USER exists"
    return
  fi
  supports_password_file || die "this HestiaCP cannot read passwords from a file — update HestiaCP, or create user $HESTIA_USER in the panel and rerun"
  local password file
  password=$(new_password)
  file=$(password_file "$password")
  "$VBIN/v-add-user" "$HESTIA_USER" "$file" "${HESTIA_USER_EMAIL:-hello@$SITE_DOMAIN}" || {
    rm -f "$file"
    die "v-add-user failed"
  }
  rm -f "$file"
  record_secret "HestiaCP panel login: $HESTIA_USER" "$password"
  ok "created HestiaCP user $HESTIA_USER"
}

# finish — reminds the owner where new credentials are.
finish() {
  if [[ -n $CRED_FILE ]]; then
    say "New credentials are in $CRED_FILE (root only)"
    ok "Move them into the password manager, then: shred -u $CRED_FILE"
  fi
}
