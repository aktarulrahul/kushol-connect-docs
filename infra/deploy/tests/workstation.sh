#!/usr/bin/env bash
# deploy/tests/workstation.sh — runs the real build-push-images.sh and deploy-web-api-vps.sh against
# throwaway git repos and fake `docker`, `make`, `pnpm`, `ssh`, `rsync` and `curl` (no Docker, no
# registry, no server): repo preconditions, gates, immutable tags, build arguments, deploy command,
# bundle sync, Gate 2 stop, exit codes.
#   bash infra/deploy/tests/workstation.sh   (from the docs repo)
set -uo pipefail

DEPLOY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$*"
}
expect() { if [[ $2 == "$3" ]]; then ok; else bad "$1: want [$2] got [$3]"; fi; }
has() { if grep -qF -- "$2" "$3"; then ok; else bad "$1: no [$2] in $(basename "$3")"; fi; }
hasnt() { if grep -qF -- "$2" "$3"; then bad "$1: unexpected [$2] in $(basename "$3")"; else ok; fi; }

# ── A copy of the scripts with only the example env files (a real env/stack.env would leak in) ──
mkdir -p "$W/infra/deploy/env" "$W/infra/docker"
cp "$DEPLOY/build-push-images.sh" "$DEPLOY/deploy-web-api-vps.sh" "$W/infra/deploy/"
cp "$DEPLOY"/env/*.env.example "$W/infra/deploy/env/"
BUILD=$W/infra/deploy/build-push-images.sh
DEPLOYER=$W/infra/deploy/deploy-web-api-vps.sh

# ── Fakes ───────────────────────────────────────────────────────────────────────────────────────
BIN=$W/bin
S=$W/state
mkdir -p "$BIN" "$S"
cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
# fake docker: `info`, `buildx version`, `buildx imagetools inspect REF` (REF in $S/registry, or
# "not found"; FAKE_REG=auth → unauthorized), `buildx build … -t REF --push` (logs + registers REF).
case "$1 ${2:-} ${3:-}" in
  "info "*) exit 0 ;;
  "buildx version"*) exit 0 ;;
  "buildx imagetools inspect")
    [[ ${FAKE_REG:-} == auth ]] && { echo "ERROR: unauthorized: authentication required" >&2; exit 1; }
    grep -qxF "$4" "$S/registry" 2>/dev/null && exit 0
    echo "ERROR: $4: not found" >&2
    exit 1 ;;
  "buildx build"*)
    echo "$*" >>"$S/docker.log"
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do [[ ${args[i]} == -t ]] && echo "${args[i + 1]}" >>"$S/registry"; done
    exit 0 ;;
esac
echo "fake docker: unexpected $*" >&2
exit 99
EOF
printf '#!/usr/bin/env bash\necho "make $*" >>"$S/gate.log"\n' >"$BIN/make"
printf '#!/usr/bin/env bash\necho "pnpm $*" >>"$S/gate.log"\n' >"$BIN/pnpm"
cat >"$BIN/ssh" <<'EOF'
#!/usr/bin/env bash
# fake ssh: logs the remote command; ops/deploy.sh answers with the next code in $S/deploy_rcs.
for a in "$@"; do [[ $a == -O ]] && exit 0; done
cmd=${*: -1}
echo "$cmd" >>"$S/ssh.log"
if [[ $cmd == *ops/deploy.sh* && -s $S/deploy_rcs ]]; then
  read -r rc rest <"$S/deploy_rcs"
  echo "$rest" >"$S/deploy_rcs"
  exit "$rc"
fi
exit 0
EOF
printf '#!/usr/bin/env bash\necho "rsync $*" >>"$S/rsync.log"\n' >"$BIN/rsync"
printf '#!/usr/bin/env bash\nprintf %%s "${FAKE_HTTP:-200}"\n' >"$BIN/curl"
chmod +x "$BIN"/*
export PATH="$BIN:$PATH" S KC_APPS=$W/apps
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ── Throwaway app repos: main, pushed to a bare origin ──────────────────────────────────────────
for app in api web; do
  git init -q --bare "$W/origin/$app.git"
  git init -q -b main "$W/apps/$app"
  git -C "$W/apps/$app" remote add origin "$W/origin/$app.git"
  echo one >"$W/apps/$app/file"
  git -C "$W/apps/$app" add file && git -C "$W/apps/$app" commit -qm one
  git -C "$W/apps/$app" push -q origin main
done
sha() { git -C "$W/apps/$1" rev-parse --short=7 HEAD; }
commit() { # APP [push] — a new commit, pushed unless told otherwise
  echo "$RANDOM" >>"$W/apps/$1/file"
  git -C "$W/apps/$1" commit -qam change
  [[ ${2:-push} == push ]] && git -C "$W/apps/$1" push -q origin main
}
reset_logs() { rm -f "$S"/*.log "$S/deploy_rcs"; }
api_ref() { echo "docker.io/airahul/ai:api-main-$(sha api)"; }
web_ref() { echo "docker.io/airahul/ai:web-main-$(sha web)"; }

# ── build-push-images.sh ────────────────────────────────────────────────────────────────────────
reset_logs
out=$(bash "$BUILD" --skip-gate 2>&1)
expect "build: both apps exit 0" 0 $?
expect "build: two builds" 2 "$(wc -l <"$S/docker.log" | tr -d ' ')"
has "build: api tag" "-t $(api_ref) --push" "$S/docker.log"
has "build: web tag" "-t $(web_ref) --push" "$S/docker.log"
has "build: amd64" "--platform linux/amd64" "$S/docker.log"
has "build: api Dockerfile" "infra/deploy/../docker/api.Dockerfile" "$S/docker.log"
has "build: web API URL" "NEXT_PUBLIC_API_URL=https://kusholconnect.com" "$S/docker.log"
has "build: web site URL" "NEXT_PUBLIC_SITE_URL=https://kusholconnect.com" "$S/docker.log"
has "build: revision label" "org.opencontainers.image.revision=$(git -C "$W/apps/api" rev-parse HEAD)" "$S/docker.log"
if grep "api.Dockerfile" "$S/docker.log" | grep -q NEXT_PUBLIC; then bad "build: api got web build args"; else ok; fi
if [[ ! -e $S/gate.log ]]; then ok; else bad "build: --skip-gate still ran a gate"; fi
expect "build: prints the deploy command" 1 "$(grep -c "deploy-web-api-vps.sh api=main-$(sha api) web=main-$(sha web)" <<<"$out")"

reset_logs
out=$(bash "$BUILD" --skip-gate 2>&1)
expect "build: existing tags exit 0" 0 $?
if [[ ! -e $S/docker.log ]]; then ok; else bad "build: rebuilt an existing (immutable) tag"; fi
expect "build: says already pushed" 2 "$(grep -c 'already pushed' <<<"$out")"

reset_logs
commit api
bash "$BUILD" api >/dev/null 2>&1
expect "build: gate run exit 0" 0 $?
has "build: api gate" "make -C $W/apps/api gate" "$S/gate.log"
hasnt "build: web not gated when only api asked" "pnpm" "$S/gate.log"
expect "build: only api built" 1 "$(wc -l <"$S/docker.log" | tr -d ' ')"

reset_logs
commit web
echo dirty >>"$W/apps/web/file"
out=$(bash "$BUILD" --skip-gate 2>&1)
expect "build: dirty repo exit 1" 1 $?
expect "build: dirty repo named" 1 "$(grep -c 'web has uncommitted changes' <<<"$out")"
if [[ ! -e $S/docker.log ]]; then ok; else bad "build: built with a dirty repo"; fi
git -C "$W/apps/web" checkout -q -- file

reset_logs
commit web nopush
bash "$BUILD" web --skip-gate >/dev/null 2>&1
expect "build: unpushed exit 1" 1 $?
bash "$BUILD" web --skip-gate --allow-unpushed >/dev/null 2>&1
expect "build: --allow-unpushed exit 0" 0 $?
has "build: unpushed commit built when allowed" "-t $(web_ref)" "$S/docker.log"
git -C "$W/apps/web" push -q origin main

reset_logs
git -C "$W/apps/api" switch -q -c feature
bash "$BUILD" api --skip-gate >/dev/null 2>&1
expect "build: non-main branch exit 1" 1 $?
git -C "$W/apps/api" switch -q main

reset_logs
commit api
FAKE_REG=auth bash "$BUILD" api --skip-gate >/dev/null 2>&1
expect "build: registry auth failure exit 1" 1 $?
if [[ ! -e $S/docker.log ]]; then ok; else bad "build: built although the registry was unreachable"; fi

reset_logs
out=$(bash "$BUILD" api --dry-run 2>&1)
expect "build: dry run exit 0" 0 $?
if [[ ! -e $S/docker.log && ! -e $S/gate.log ]]; then ok; else bad "build: dry run built or gated"; fi
expect "build: dry run prints the build" 1 "$(grep -c '+ docker buildx build' <<<"$out")"

bash "$BUILD" nonsense >/dev/null 2>&1
expect "build: bad argument exit 1" 1 $?

# ── deploy-web-api-vps.sh ───────────────────────────────────────────────────────────────────────
bash "$BUILD" --skip-gate >/dev/null 2>&1 # both HEADs pushed
deploy_line="sudo -iu kushol /opt/kushol/ops/deploy.sh pilot api=main-$(sha api) web=main-$(sha web)"

reset_logs
out=$(bash "$DEPLOYER" 2>&1)
expect "deploy: default exit 0" 0 $?
has "deploy: both HEAD tags as kushol" "$deploy_line" "$S/ssh.log"
expect "deploy: reports live" 1 "$(grep -c 'Live: https://kusholconnect.com' <<<"$out")"
if [[ ! -e $S/rsync.log ]]; then ok; else bad "deploy: synced without --sync"; fi

reset_logs
bash "$DEPLOYER" web >/dev/null 2>&1
expect "deploy: web only exit 0" 0 $?
expect "deploy: web only command" "sudo -iu kushol /opt/kushol/ops/deploy.sh pilot web=main-$(sha web)" "$(cat "$S/ssh.log")"

reset_logs
bash "$DEPLOYER" api=latest >/dev/null 2>&1
expect "deploy: latest refused exit 2" 2 $?
if [[ ! -e $S/ssh.log ]]; then ok; else bad "deploy: contacted the server with a bad tag"; fi

reset_logs
bash "$DEPLOYER" api=main-0000000 >/dev/null 2>&1
expect "deploy: unpushed tag exit 5" 5 $?
if [[ ! -e $S/ssh.log ]]; then ok; else bad "deploy: contacted the server for a missing image"; fi

reset_logs
bash "$DEPLOYER" --sync >/dev/null 2>&1
expect "deploy: --sync exit 0" 0 $?
for want in "--delete" "--exclude env/*.env" "--exclude state/" "--exclude tests/" \
  "--exclude build-push-images.sh" "--exclude deploy-web-api-vps.sh" "root@72.61.114.20:/opt/kushol/"; do
  has "deploy: rsync $want" "$want" "$S/rsync.log"
done
expect "deploy: layout fixed then deployed" \
  "chown -R kushol:kushol /opt/kushol && chmod 700 /opt/kushol/env|$deploy_line" \
  "$(cut -c1-63 "$S/ssh.log" | head -1)|$(sed -n 2p "$S/ssh.log")"

reset_logs
bash "$DEPLOYER" --sync-only >/dev/null 2>&1
expect "deploy: --sync-only exit 0" 0 $?
has "deploy: --sync-only syncs" "rsync -av" "$S/rsync.log"
hasnt "deploy: --sync-only does not deploy" "ops/deploy.sh" "$S/ssh.log"

reset_logs
echo "3 0" >"$S/deploy_rcs"
out=$(bash "$DEPLOYER" </dev/null 2>&1)
expect "deploy: schema behind without a terminal exit 3" 3 $?
has "deploy: shows migration status" "ops/migrate.sh main-$(sha api) status" "$S/ssh.log"
hasnt "deploy: never migrates without 'apply'" "up --confirm" "$S/ssh.log"
expect "deploy: prints the migrate command" 1 "$(grep -c "migrate.sh main-$(sha api) up --confirm" <<<"$out")"

reset_logs
echo "1" >"$S/deploy_rcs"
bash "$DEPLOYER" >/dev/null 2>&1
expect "deploy: failed release exit 1" 1 $?

reset_logs
KC_HOST=kushol@72.61.114.20 bash "$DEPLOYER" --sync >/dev/null 2>&1
expect "deploy: kushol host exit 0" 0 $?
hasnt "deploy: no sudo as kushol" "sudo" "$S/ssh.log"
hasnt "deploy: no chown as kushol" "chown" "$S/ssh.log"

reset_logs
out=$(FAKE_HTTP=000 bash "$DEPLOYER" 2>&1)
expect "deploy: no public HTTPS still exit 0" 0 $?
expect "deploy: warns about HTTPS" 1 "$(grep -c 'not over public HTTPS' <<<"$out")"

reset_logs
out=$(bash "$DEPLOYER" --sync --dry-run 2>&1)
expect "deploy: dry run exit 0" 0 $?
if [[ ! -e $S/ssh.log && ! -e $S/rsync.log ]]; then ok; else bad "deploy: dry run touched the server"; fi
expect "deploy: dry run prints the deploy" 1 "$(grep -c "+ ssh root@72.61.114.20 $deploy_line" <<<"$out")"

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
