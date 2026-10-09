#!/usr/bin/env bash
# deploy/tests/flow.sh — runs the real ops/deploy.sh and ops/rollback.sh against fake `docker` and
# `curl` commands (no containers, no network): first deploy, partial deploy, red gate → automatic
# rollback, database behind, pull failure, bad input, operator rollback walking back the log.
# The container-backed dry-run (OPS-IT-001) is the owner's first deploy (DEPLOYMENT.md §3.8).
#   bash infra/deploy/tests/flow.sh   (from the docs repo)
set -uo pipefail

DEPLOY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$*"
}
expect() { if [[ $2 == "$3" ]]; then ok; else bad "$1: want [$2] got [$3]"; fi; }

# ── Fakes ───────────────────────────────────────────────────────────────────────────────────────
BIN=$WORK/bin
mkdir -p "$BIN"
cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
# fake `docker compose … pull|run|up|ps|logs`: the release file is the last --env-file.
args=("$@")
release=""
for ((i = 0; i < ${#args[@]}; i++)); do [[ ${args[i]} == --env-file ]] && release=${args[i + 1]}; done
api=$(sed -n 's/^API_TAG=//p' "$release")
web=$(sed -n 's/^WEB_TAG=//p' "$release")
sub=""
for a in "$@"; do case $a in pull | run | up | ps | logs) sub=$a && break ;; esac; done
echo "$sub api=$api web=$web" >>"$FAKE_STATE/docker.log"
case $sub in
  pull) [[ ${FAKE_PULL_FAIL:-} == 1 ]] && exit 1 ;;
  run)
    echo "database_version=20260930000003 expected_version=20260930000003 dirty=false"
    exit "${FAKE_SCHEMA_RC:-0}"
    ;;
  up) echo "$api $web" >"$FAKE_STATE/running" ;;
esac
exit 0
EOF
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
# fake curl: 200 everywhere, except /readyz while the api tag in FAKE_BAD_API is running.
url="" print_code=no fail_on_error=no
for a in "$@"; do
  case $a in
    http://* | https://*) url=$a ;;
    '%{http_code}') print_code=yes ;;
    --*) ;;
    -*f*) fail_on_error=yes ;;
  esac
done
read -r api _ <"$FAKE_STATE/running" 2>/dev/null || api=""
code=200
[[ -n ${FAKE_BAD_API:-} && $api == "$FAKE_BAD_API" && $url == */readyz ]] && code=503
[[ $print_code == yes ]] && printf '%s' "$code"
[[ $code == 200 || $fail_on_error == no ]] || exit 22
exit 0
EOF
# macOS has neither flock nor GNU `stat -c`; CI (Ubuntu) uses the real ones.
real_flock=yes
if ! command -v flock >/dev/null; then
  real_flock=no
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/flock"
fi
if ! stat -c %a / >/dev/null 2>&1; then
  cat >"$BIN/stat" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -c ]] && exec /usr/bin/stat -f %Lp "$3"
exec /usr/bin/stat "$@"
EOF
fi
chmod +x "$BIN"/*
export PATH="$BIN:$PATH" KC_GATE_TIMEOUT=1 KC_RETRY_DELAY=0

# ── A fresh /opt/kushol per scenario group ──────────────────────────────────────────────────────
ROOT=$WORK/root
new_root() {
  rm -rf "$ROOT"
  mkdir -p "$ROOT/env" "$ROOT/state"
  cp -R "$DEPLOY/ops" "$DEPLOY/compose.yaml" "$ROOT/"
  cp "$DEPLOY"/env/*.example "$ROOT/env/"
  for name in stack api web; do cp "$ROOT/env/$name.env.example" "$ROOT/env/$name.env"; done
  sed -i.bak -e 's|^DATABASE_URL=.*|DATABASE_URL=postgres://u:p@db.example/neondb?sslmode=require|' \
    -e 's|^JWT_SECRET=.*|JWT_SECRET=0123456789abcdef0123456789abcdef|' \
    -e 's|^OTP_PEPPER=.*|OTP_PEPPER=0123456789abcdef|' \
    -e 's|^PAYMENTS_WEBHOOK_SECRET=.*|PAYMENTS_WEBHOOK_SECRET=0123456789abcdef0123456789abcdef|' \
    -e 's|^ERP_SECRET_KEY=.*|ERP_SECRET_KEY=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=|' "$ROOT/env/api.env"
  rm -f "$ROOT"/env/*.bak
  chmod 600 "$ROOT"/env/*.env
  export FAKE_STATE=$ROOT/state
  unset FAKE_BAD_API FAKE_SCHEMA_RC FAKE_PULL_FAIL KC_LOCK_HELD
}
deploy() { "$ROOT/ops/deploy.sh" "$@" 2>"$WORK/stderr"; }
rollback() { "$ROOT/ops/rollback.sh" "$@" 2>"$WORK/stderr"; }
release() { tr '\n' ' ' <"$ROOT/state/release.env" | sed 's/ $//'; }
last_log() { tail -1 "$ROOT/state/releases.log" | cut -d' ' -f2-; }

new_root

# 1. First deploy.
out=$(deploy pilot api=main-aaaaaaa web=main-1111111)
expect "first deploy exit" 0 $?
expect "first deploy result line" "SERVING pilot api=main-aaaaaaa web=main-1111111" "$out"
expect "first deploy release" "API_TAG=main-aaaaaaa WEB_TAG=main-1111111" "$(release)"
expect "first deploy log" "pilot api=main-aaaaaaa web=main-1111111 SERVING" "$(last_log)"

# 2. api only — web keeps its tag.
out=$(deploy pilot api=main-bbbbbbb)
expect "api-only deploy exit" 0 $?
expect "api-only deploy keeps web" "API_TAG=main-bbbbbbb WEB_TAG=main-1111111" "$(release)"

# 3. Red gate → automatic rollback to what was serving.
out=$(FAKE_BAD_API=main-ccccccc deploy pilot api=main-ccccccc)
expect "red gate exit" 1 $?
expect "red gate result line" "ROLLED_BACK pilot api=main-bbbbbbb web=main-1111111" "$out"
expect "red gate release restored" "API_TAG=main-bbbbbbb WEB_TAG=main-1111111" "$(release)"
expect "red gate running restored" "main-bbbbbbb main-1111111" "$(cat "$ROOT/state/running")"
expect "red gate logged FAILED" "pilot api=main-ccccccc web=main-1111111 FAILED" "$(tail -2 "$ROOT/state/releases.log" | head -1 | cut -d' ' -f2-)"
expect "red gate logged auto-rollback" "pilot api=main-bbbbbbb web=main-1111111 SERVING auto-rollback" "$(last_log)"
expect "red gate incident lines" 2 "$(wc -l <"$ROOT/state/incidents.log" | tr -d ' ')"

# 4. Database behind → stop before any container changes.
before=$(wc -l <"$ROOT/state/docker.log")
out=$(FAKE_SCHEMA_RC=3 deploy pilot api=main-ddddddd)
expect "schema behind exit" 3 $?
expect "schema behind leaves release" "API_TAG=main-bbbbbbb WEB_TAG=main-1111111" "$(release)"
expect "schema behind never runs up" "" "$(tail -n +"$((before + 1))" "$ROOT/state/docker.log" | grep '^up' || true)"
if grep -q 'ops/migrate.sh main-ddddddd up --confirm' "$WORK/stderr"; then ok; else bad "schema behind names the owner's migrate command"; fi

# 5. Dirty schema and pull failure → nothing changed.
out=$(FAKE_SCHEMA_RC=4 deploy pilot api=main-ddddddd)
expect "schema dirty exit" 4 $?
out=$(FAKE_PULL_FAIL=1 deploy pilot api=main-ddddddd)
expect "pull failure exit" 5 $?
expect "pull failure leaves release" "API_TAG=main-bbbbbbb WEB_TAG=main-1111111" "$(release)"

# 6. Bad input.
out=$(deploy pilot api=latest)
expect "latest tag refused" 2 $?
out=$(deploy prod api=main-ddddddd)
expect "env name mismatch refused" 2 $?
out=$(deploy pilot api=main-ddddddd extra)
expect "unknown argument refused" 2 $?
cp "$ROOT/env/api.env" "$WORK/api.env.keep"
sed -i.bak 's|^JWT_SECRET=.*|JWT_SECRET=REPLACE_WITH_openssl_rand_base64_48|' "$ROOT/env/api.env" && rm -f "$ROOT/env/api.env.bak"
out=$(deploy pilot api=main-ddddddd)
expect "placeholder secret refused" 2 $?
if grep -q 'JWT_SECRET' "$WORK/stderr"; then ok; else bad "incomplete env names the key"; fi
cp "$WORK/api.env.keep" "$ROOT/env/api.env" && chmod 644 "$ROOT/env/api.env"
out=$(deploy pilot api=main-ddddddd)
expect "world-readable env refused" 2 $?
chmod 600 "$ROOT/env/api.env"

# 7. Operator rollback walks back the log, skipping FAILED and ROLLED_BACK releases.
out=$(rollback pilot)
expect "rollback exit" 0 $?
expect "rollback target" "API_TAG=main-aaaaaaa WEB_TAG=main-1111111" "$(release)"
if grep -q 'api=main-bbbbbbb web=main-1111111 ROLLED_BACK operator' "$ROOT/state/releases.log"; then ok; else bad "rollback marks the abandoned release"; fi
expect "rollback logged" "pilot api=main-aaaaaaa web=main-1111111 SERVING rollback" "$(last_log)"
out=$(rollback pilot)
expect "nothing left to roll back to" 2 $?

# 8. Before the first deploy there is nothing to roll back.
new_root
out=$(rollback pilot)
expect "rollback before first deploy" 2 $?
out=$(deploy pilot api=main-aaaaaaa)
expect "first deploy needs both tags" 2 $?

# 9. Concurrent deploys (real flock only).
if [[ $real_flock == yes ]]; then
  (
    exec 9>"$ROOT/state/deploy.lock"
    flock 9
    sleep 3
  ) &
  sleep 1
  out=$(deploy pilot api=main-aaaaaaa web=main-1111111)
  expect "second deploy refused while locked" 2 $?
  wait
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
