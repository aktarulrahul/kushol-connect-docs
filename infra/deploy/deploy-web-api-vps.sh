#!/usr/bin/env bash
# deploy-web-api-vps.sh [api[=<tag>]] [web[=<tag>]] [--sync | --sync-only] [--dry-run]
#
# Deploys pushed images to the VPS from the owner's Mac: optional bundle sync → ops/deploy.sh on the
# server (pull → schema check → up → /readyz gate → smoke; a red gate rolls back by itself) → a
# public check over HTTPS. From the workspace root:
#
#   bash docs/infra/deploy/deploy-web-api-vps.sh                     # api + web at each repo's HEAD
#   bash docs/infra/deploy/deploy-web-api-vps.sh web                 # web only; the api keeps running
#   bash docs/infra/deploy/deploy-web-api-vps.sh api=main-e71c776    # an exact tag (redeploy, pin)
#   bash docs/infra/deploy/deploy-web-api-vps.sh --sync              # rsync docs/infra/deploy first
#   bash docs/infra/deploy/deploy-web-api-vps.sh --sync-only         # rsync only (scripts/templates)
#
# `api` / `web` without a tag mean main-<sha7> of that app repo's HEAD — what build-push-images.sh
# pushed. The tag must already be in the registry. If the new api needs migrations, ops/deploy.sh
# stops with nothing changed (exit 3); this script then shows them and applies them only after you
# type "apply" (Gate 2), and deploys again.
#
# Settings: KC_HOST (default root@<PUBLIC_IP>; use kushol@… once that user has your SSH key),
# KC_ENV (default KUSHOL_ENV), KC_APPS (default applications/ beside docs/). The rest comes from
# env/stack.env, falling back to env/stack.env.example. One SSH connection is shared by every step,
# so a password is asked once.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APPS=${KC_APPS:-$HERE/../../../applications}
REMOTE_ROOT=/opt/kushol
# Exit codes of ops/deploy.sh (ops/lib.sh)
EXIT_FAILED=1 EXIT_USAGE=2 EXIT_SCHEMA_BEHIND=3 EXIT_SCHEMA_DIRTY=4 EXIT_PULL=5

say() { printf '\n==== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit "${2:-$EXIT_USAGE}"
}
usage() { die "usage: deploy-web-api-vps.sh [api[=<tag>]] [web[=<tag>]] [--sync | --sync-only] [--dry-run]"; }

setting() { # KEY — environment, then env/stack.env, then env/stack.env.example
  local key=$1 file=$HERE/env/stack.env
  if [[ -n ${!key:-} ]]; then
    printf '%s' "${!key}"
    return
  fi
  [[ -r $file ]] || file=$file.example
  awk -v k="$key" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { printf "%s", v }' "$file"
}

api_tag="" web_tag="" sync=no deploy=yes dry=no
head_tag() {
  local repo=$APPS/$1
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "no $1 repo at $repo — pass $1=main-<sha7> (or set KC_APPS)"
  [[ -z $(git -C "$repo" status --porcelain) ]] || warn "$1 has uncommitted changes — they are not in main-$(git -C "$repo" rev-parse --short=7 HEAD)"
  printf 'main-%s' "$(git -C "$repo" rev-parse --short=7 HEAD)"
}
for arg in "$@"; do
  case $arg in
    api) api_tag=$(head_tag api) ;;
    web) web_tag=$(head_tag web) ;;
    api=*) api_tag=${arg#api=} ;;
    web=*) web_tag=${arg#web=} ;;
    --sync) sync=yes ;;
    --sync-only) sync=yes deploy=no ;;
    --dry-run) dry=yes ;;
    -h | --help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' && exit 0 ;;
    *) usage ;;
  esac
done
if [[ $deploy == yes && -z $api_tag && -z $web_tag ]]; then
  api_tag=$(head_tag api)
  web_tag=$(head_tag web)
fi
for tag in $api_tag $web_tag; do
  [[ $tag =~ ^(main|release)-[0-9a-f]{7,40}$ ]] || die "invalid tag '$tag' — expected main-<sha7> (latest is never deployed)"
done

ENV_NAME=${KC_ENV:-$(setting KUSHOL_ENV)}
HOST=${KC_HOST:-root@$(setting PUBLIC_IP)}
SITE_DOMAIN=$(setting SITE_DOMAIN)
API_DOMAIN=$(setting API_DOMAIN)
# Root (the default — kushol has no SSH key yet) runs the ops scripts as the deploy user.
as_kushol="sudo -iu kushol"
[[ ${HOST%%@*} == kushol ]] && as_kushol=""

# ── Registry: every tag must exist before the server is touched ────────────────────────────────
if [[ $deploy == yes ]]; then
  say "Images"
  if command -v docker >/dev/null && docker buildx version >/dev/null 2>&1; then
    for pair in "api:$api_tag" "web:$web_tag"; do
      app=${pair%%:*} tag=${pair#*:}
      [[ -n $tag ]] || continue
      if [[ $app == api ]]; then
        ref="$(setting API_IMAGE):$(setting API_TAG_PREFIX)$tag"
      else
        ref="$(setting WEB_IMAGE):$(setting WEB_TAG_PREFIX)$tag"
      fi
      if err=$(docker buildx imagetools inspect "$ref" 2>&1 >/dev/null); then
        echo "$app: $ref"
      else
        case $err in
          *"not found"* | *"manifest unknown"* | *MANIFEST_UNKNOWN*)
            die "$ref is not in the registry — build and push it first: bash docs/infra/deploy/build-push-images.sh $app" "$EXIT_PULL" ;;
          *) warn "could not check $ref ($err) — the server's pull will tell" ;;
        esac
      fi
    done
  else
    warn "no docker CLI here — not checking the registry; the server's pull will tell"
  fi
fi

# ── One shared SSH connection (a root password is asked once) ──────────────────────────────────
# Short socket path: macOS limits UNIX socket paths to 104 bytes.
SOCK_DIR=$(mktemp -d /tmp/kc-ssh.XXXXXX)
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$SOCK_DIR/%C" -o ControlPersist=300)
cleanup() {
  ssh "${SSH_OPTS[@]}" -O exit "$HOST" >/dev/null 2>&1 || true
  rm -rf "$SOCK_DIR"
}
trap cleanup EXIT
TTY=-T
[[ -t 0 && -t 1 ]] && TTY=-t
remote() { # COMMAND… — runs on the server; returns its exit code
  if [[ $dry == yes ]]; then
    printf '  + ssh %s %s\n' "$HOST" "$*"
    return 0
  fi
  ssh "${SSH_OPTS[@]}" "$TTY" "$HOST" "$@"
}

# ── Sync the bundle ─────────────────────────────────────────────────────────────────────────────
if [[ $sync == yes ]]; then
  say "Sync docs/infra/deploy → $HOST:$REMOTE_ROOT"
  # Never overwritten: real env files, server state. Not needed there: tests and these Mac scripts.
  rsync_args=(-av --delete --exclude 'env/*.env' --exclude 'state/' --exclude 'tests/'
    --exclude 'build-push-images.sh' --exclude 'deploy-web-api-vps.sh'
    -e "ssh ${SSH_OPTS[*]}" "$HERE/" "$HOST:$REMOTE_ROOT/")
  if [[ $dry == yes ]]; then
    printf '  + rsync'
    printf ' %q' "${rsync_args[@]}"
    printf '\n'
  else
    rsync "${rsync_args[@]}"
  fi
  # rsync copies the Mac's owner and modes; restore the layout host/prepare-host.sh sets.
  fix="chmod 700 $REMOTE_ROOT/env && chmod 600 $REMOTE_ROOT/env/*.env && chmod 755 $REMOTE_ROOT/ops/*.sh $REMOTE_ROOT/host/*.sh $REMOTE_ROOT/hestia/*.sh"
  [[ -n $as_kushol ]] && fix="chown -R kushol:kushol $REMOTE_ROOT && $fix"
  remote "$fix"
  echo "synced; server layout restored"
fi
[[ $deploy == yes ]] || exit 0

# ── Deploy ──────────────────────────────────────────────────────────────────────────────────────
deploy_args="$ENV_NAME${api_tag:+ api=$api_tag}${web_tag:+ web=$web_tag}"
say "Deploy $deploy_args on $HOST"
rc=0
remote "$as_kushol $REMOTE_ROOT/ops/deploy.sh $deploy_args" || rc=$?

if [[ $rc -eq $EXIT_SCHEMA_BEHIND && -n $api_tag ]]; then
  say "Database migrations (Gate 2 — your decision)"
  remote "$as_kushol $REMOTE_ROOT/ops/migrate.sh $api_tag status" || true
  echo
  echo "The production database is BEHIND api=$api_tag; nothing was changed. Applying runs every"
  echo "pending migration in that image against PRODUCTION (Neon branch restore is the only undo)."
  if [[ -t 0 && $dry == no ]]; then
    read -rp 'Type "apply" to apply them and deploy again (anything else stops): ' answer
  else
    answer=""
  fi
  [[ $answer == apply ]] || die "stopped before migrations — to apply later:
  ssh -t $HOST '$as_kushol $REMOTE_ROOT/ops/migrate.sh $api_tag up --confirm'
then run this script again" "$EXIT_SCHEMA_BEHIND"
  remote "$as_kushol $REMOTE_ROOT/ops/migrate.sh $api_tag up --confirm"
  say "Deploy $deploy_args on $HOST (after migrations)"
  rc=0
  remote "$as_kushol $REMOTE_ROOT/ops/deploy.sh $deploy_args" || rc=$?
fi

case $rc in
  0) ;;
  "$EXIT_FAILED") die "the new release failed its gate or smoke — the server rolled back to the previous release (see state/incidents.log)" "$rc" ;;
  "$EXIT_SCHEMA_DIRTY") die "the database schema is DIRTY (a migration failed midway) — fix forward first (DEPLOYMENT.md §7)" "$rc" ;;
  "$EXIT_PULL") die "the server could not pull the image — pushed? registry token expired? (images.md §4)" "$rc" ;;
  *) die "ops/deploy.sh exited $rc — see its output above (DEPLOYMENT.md §6 exit codes)" "$rc" ;;
esac

# ── Public check (informational: the server's smoke already passed) ────────────────────────────
say "Public check"
if [[ $dry == yes ]]; then
  echo "  (dry run — skipped)"
  exit 0
fi
public_ok=yes
for url in "https://$SITE_DOMAIN/" "https://$API_DOMAIN/readyz"; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -L "$url" 2>/dev/null) || code=000
  printf '   %-40s %s\n' "$url" "$code"
  [[ $code == 200 ]] || public_ok=no
done
if [[ $public_ok == yes ]]; then
  say "Live: https://$SITE_DOMAIN and https://$API_DOMAIN"
else
  warn "deployed and healthy on the server, but not over public HTTPS — no certificate yet? Run:
  ssh -t $HOST bash $REMOTE_ROOT/host/first-deploy.sh api=<tag> web=<tag>   (step 7 issues the certificates)"
fi
