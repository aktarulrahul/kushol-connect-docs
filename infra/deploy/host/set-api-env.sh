#!/usr/bin/env bash
# host/set-api-env.sh [--from-stdin] — sets the optional integrations in env/api.env on the VPS:
# Cloudflare R2 (chat/notice attachments), SAS Bulk SMS (phone OTP in the mobile app), SMTP
# (email OTP from noreply@ — host, port, username, password, from) and KLIPY (chat GIFs and
# stickers — the app key). Run as root.
#
#   ssh -t root@72.61.114.20 bash /opt/kushol/host/set-api-env.sh          # asks, secrets hidden
#
#   # Same values as the workstation's applications/api/.env, piped over SSH (never on a command
#   # line, in shell history or in a chat):
#   grep -E '^(R2_[A-Z_]+|SMS_GATEWAY_[A-Z_]+|SMTP_[A-Z_]+|KLIPY_APP_KEY)=' applications/api/.env \
#     | ssh root@72.61.114.20 'bash /opt/kushol/host/set-api-env.sh --from-stdin'
#
# Interactive, per group: Enter keeps it as it is, "y" sets it, "-" turns it off. --from-stdin reads
# KEY=VALUE lines (CRLF and surrounding quotes are stripped) for these keys only. Each group is
# all-or-nothing (the api refuses to start with a partial SMS set; media stays off with a partial
# R2 set; email OTP fails "delivery channel not configured" while SMTP_HOST is empty), so a group
# is only written with all of its values. Nothing is written when any check
# fails; otherwise a chmod-600 backup comes first. Values Compose would rewrite in an env_file
# ($, #, spaces, quotes) are single-quoted, which Compose reads literally. The api reads
# env/api.env when its containers are created: the next ops/deploy.sh applies the change, or now:
# `sudo -iu kushol /opt/kushol/ops/compose.sh up -d api worker`.
set -euo pipefail

KC_ROOT=${KC_ROOT:-/opt/kushol} # overridable for the bundle tests only
API_ENV=$KC_ROOT/env/api.env

R2_KEYS=(R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_KEY R2_BUCKET)
SMS_KEYS=(SMS_GATEWAY_URL SMS_GATEWAY_API_KEY SMS_GATEWAY_SECRET_KEY SMS_GATEWAY_SENDER)
SMTP_KEYS=(SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM)
KLIPY_KEYS=(KLIPY_APP_KEY)
# Non-secret defaults offered at the prompts when a key has no value yet.
DEFAULT_R2_ACCOUNT_ID=07cfe10ccb261c03b4402eed78d09833
DEFAULT_R2_BUCKET=kusholconnect
DEFAULT_SMS_GATEWAY_URL=http://sms.sasbulksms.com:3040/sendtext
DEFAULT_SMS_GATEWAY_SENDER=8809640911605
DEFAULT_SMTP_HOST=mail.kusholconnect.com
DEFAULT_SMTP_PORT=587
DEFAULT_SMTP_USERNAME=noreply@kusholconnect.com
DEFAULT_SMTP_FROM=noreply@kusholconnect.com

say() { printf '\n==== %s\n' "$*"; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

mode=interactive
case ${1:-} in
  "") ;;
  --from-stdin) mode=stdin ;;
  -h | --help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' && exit 0 ;;
  *) die "usage: set-api-env.sh [--from-stdin]" ;;
esac
[[ -f $API_ENV ]] || die "missing $API_ENV — run host/prepare-host.sh (or first-deploy.sh) first"
[[ -w $API_ENV ]] || die "cannot write $API_ENV — run as root"
if [[ $mode == interactive ]]; then
  [[ -t 0 ]] || die "needs a terminal for the hidden prompts — use ssh -t (or --from-stdin)"
fi

is_secret() { [[ $1 == *SECRET* || $1 == *API_KEY* || $1 == *APP_KEY* || $1 == *PASSWORD* ]]; }

# current KEY — the active (uncommented) value, surrounding single quotes removed; "" when unset.
current() {
  local v
  v=$(awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$API_ENV")
  if [[ $v == \'*\' && ${#v} -ge 2 ]]; then v=${v:1:${#v}-2}; fi
  printf '%s' "$v"
}

# literal VALUE — how the value is written so Compose's env_file parser keeps it byte for byte.
literal() {
  local v=$1
  if [[ $v =~ ^[A-Za-z0-9_./:@+=,%-]*$ ]]; then
    printf '%s' "$v"
  elif [[ $v != *"'"* ]]; then
    printf "'%s'" "$v"
  else
    return 1
  fi
}

# Pending edits, applied together at the end: KEY → value, or KEY → $OFF to comment it out.
declare -A EDIT=()
OFF=$'\x01off'

# take KEY VALUE — validates one value and queues it.
take() {
  [[ -n $2 ]] || die "$1 is empty (nothing was written)"
  literal "$2" >/dev/null || die "$1 contains a single quote, which env_file cannot carry literally (nothing was written)"
  EDIT[$1]=$2
}

# ── Interactive ──────────────────────────────────────────────────────────────────────────────────

# ask KEY — prompts for one value (hidden for secrets); Enter keeps the current one or the default.
ask() {
  local key=$1 have default_var value
  have=$(current "$key")
  default_var="DEFAULT_$key"
  [[ -n $have ]] || have=${!default_var:-}
  if is_secret "$key"; then
    read -rsp "  $key [$([[ -n $(current "$key") ]] && echo "set — Enter keeps it" || echo "not set")]: " value </dev/tty
    echo >/dev/tty
  else
    read -rp "  $key [${have:-not set}]: " value </dev/tty
  fi
  printf '%s' "${value:-$have}"
}

group() { # NAME DESCRIPTION KEYS… — one integration: keep, set or turn off
  local name=$1 desc=$2
  shift 2
  local keys=("$@") key answer state=off value
  for key in "${keys[@]}"; do
    if [[ -n $(current "$key") ]]; then
      state=on
      break
    fi
  done
  say "$name — $desc"
  echo "  currently: $state"
  read -rp "  Enter = keep · y = set · - = turn off: " answer </dev/tty
  case $answer in
    "") return 0 ;;
    -)
      for key in "${keys[@]}"; do EDIT[$key]=$OFF; done
      return 0
      ;;
    y | Y) ;;
    *) die "answer Enter, y or -" ;;
  esac
  for key in "${keys[@]}"; do
    value=$(ask "$key")
    take "$key" "$value"
  done
}

# ── --from-stdin ─────────────────────────────────────────────────────────────────────────────────

allowed() {
  local key
  for key in "${R2_KEYS[@]}" "${SMS_KEYS[@]}" "${SMTP_KEYS[@]}" "${KLIPY_KEYS[@]}"; do [[ $1 == "$key" ]] && return 0; done
  return 1
}

# unquote VALUE — drops one pair of surrounding single or double quotes (as written in a .env).
unquote() {
  local v=$1
  if [[ ${#v} -ge 2 && ($v == \'*\' || $v == \"*\") ]]; then v=${v:1:${#v}-2}; fi
  printf '%s' "$v"
}

read_stdin() {
  local line key
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z $line || $line == \#* ]] && continue
    [[ $line == [A-Z]*=* ]] || die "expected KEY=VALUE lines on stdin (nothing was written)"
    key=${line%%=*}
    allowed "$key" || die "$key is not one this script sets — R2_*, SMS_GATEWAY_*, SMTP_* or KLIPY_APP_KEY (nothing was written)"
    take "$key" "$(unquote "${line#*=}")"
  done
  [[ ${#EDIT[@]} -gt 0 ]] || die "no KEY=VALUE lines on stdin"
  local set_name n
  for set_name in R2 SMS SMTP KLIPY; do
    declare -n keys="${set_name}_KEYS"
    n=0
    for key in "${keys[@]}"; do
      if [[ -n ${EDIT[$key]:-} ]]; then n=$((n + 1)); fi
    done
    if [[ $n -ne 0 && $n -ne ${#keys[@]} ]]; then
      die "$set_name got $n of ${#keys[@]} values — send all of ${keys[*]} (nothing was written)"
    fi
    unset -n keys
  done
}

# ── Collect ──────────────────────────────────────────────────────────────────────────────────────

if [[ $mode == stdin ]]; then
  read_stdin
else
  group "Cloudflare R2" "attachments (all four, or none)" "${R2_KEYS[@]}"
  group "SAS Bulk SMS" "phone OTP in the mobile app (all four, or none — a partial set stops the api)" "${SMS_KEYS[@]}"
  group "SMTP" "email OTP from noreply@ (all five, or none)" "${SMTP_KEYS[@]}"
  group "KLIPY" "GIFs and stickers in chat (the KLIPY app key)" "${KLIPY_KEYS[@]}"
fi

if [[ ${#EDIT[@]} -eq 0 ]]; then
  say "Nothing to change"
  exit 0
fi

say "Updating $API_ENV"
for key in $(printf '%s\n' "${!EDIT[@]}" | sort); do
  if [[ ${EDIT[$key]} == "$OFF" ]]; then
    echo "  $key → off (commented out)"
  elif is_secret "$key"; then
    echo "  $key → (hidden, ${#EDIT[$key]} characters)"
  else
    echo "  $key → ${EDIT[$key]}"
  fi
done
if [[ $mode == interactive ]]; then
  read -rp "Write these changes? [y/N]: " answer </dev/tty
  [[ $answer == y || $answer == Y ]] || die "stopped — nothing was written"
fi

# ── Write ────────────────────────────────────────────────────────────────────────────────────────

backup="$API_ENV.bak-$(date -u +%Y%m%dT%H%M%SZ)"
(umask 077 && cp "$API_ENV" "$backup")
chmod 600 "$backup"

# set_key KEY LINE — replaces the active KEY= line, else the first commented #KEY= line, else
# appends. The line travels through the environment, so no character needs escaping.
set_key() {
  local tmp mode=append
  if grep -q "^$1=" "$API_ENV"; then
    mode=active
  elif grep -q "^#[[:space:]]*$1=" "$API_ENV"; then
    mode=commented
  fi
  tmp=$(mktemp "$API_ENV.XXXXXX") # mode 600: secrets are never world-readable, even briefly
  KC_KEY=$1 KC_LINE=$2 KC_MODE=$mode awk '
    BEGIN { k = ENVIRON["KC_KEY"]; line = ENVIRON["KC_LINE"]; mode = ENVIRON["KC_MODE"] }
    mode == "active" && index($0, k "=") == 1 { if (!done) print line; done = 1; next }
    mode == "commented" && !done && $0 ~ ("^#[[:space:]]*" k "=") { print line; done = 1; next }
    { print }
    END { if (mode == "append") print line }' "$API_ENV" >"$tmp"
  cat "$tmp" >"$API_ENV" # keeps the file's owner and mode (kushol, 600)
  rm -f "$tmp"
}

for key in "${!EDIT[@]}"; do
  if [[ ${EDIT[$key]} == "$OFF" ]]; then
    if grep -q "^$key=" "$API_ENV"; then set_key "$key" "#$key="; fi # the old value never lingers
  else
    set_key "$key" "$key=$(literal "${EDIT[$key]}")"
  fi
done
chmod 600 "$API_ENV"

# All-or-nothing check on what is now in the file (an earlier hand edit may have left a partial set).
for set_name in R2 SMS SMTP KLIPY; do
  declare -n keys="${set_name}_KEYS"
  filled=0
  for key in "${keys[@]}"; do
    if [[ -n $(current "$key") ]]; then filled=$((filled + 1)); fi
  done
  if [[ $filled -ne 0 && $filled -ne ${#keys[@]} ]]; then
    echo "WARNING: $set_name has $filled of ${#keys[@]} values — fill or turn off the rest (rerun this script)" >&2
  fi
  unset -n keys
done

say "Done — backup: $backup (it holds secrets; delete it once the release is healthy)"
echo "The api reads env/api.env when its containers are created. Apply it with the next deploy, or now:"
echo "  sudo -iu kushol $KC_ROOT/ops/compose.sh up -d api worker"
