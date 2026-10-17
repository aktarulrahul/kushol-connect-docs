#!/usr/bin/env bash
# deploy/tests/run.sh — container-free checks of the deploy bundle (module 15 test plan):
#   OPS-UT-002 env parity · OPS-UT-003 tag scheme · release-log rollback targets · env completeness
#   · compose rules (loopback ports, caps, restart, healthchecks, no build, no Postgres/MinIO)
#   · no image builds in host scripts (OPS-BR-001) · template placeholders · bash syntax.
# Run from the docs repo (macOS bash 3.2 is enough): bash infra/deploy/tests/run.sh. The env-parity
# checks need the app repos beside docs/ (the workspace layout); without them they are skipped, loudly.
set -uo pipefail

DEPLOY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# The app repos sit beside docs/: kushol-connect/{docs/infra/deploy, applications/api, applications/web}.
APPS=${KC_APPS:-$DEPLOY/../../../applications}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$*"
}
expect() { # DESCRIPTION WANT GOT
  if [[ $2 == "$3" ]]; then ok; else bad "$1: want [$2] got [$3]"; fi
}

KC_ROOT=$TMP
# shellcheck source=deploy/ops/lib.sh
. "$DEPLOY/ops/lib.sh"

# ── OPS-UT-003: tag scheme ──────────────────────────────────────────────────────────────────────
for tag in main-abc1234 main-0123456789abcdef0123456789abcdef01234567 release-deadbee; do
  if valid_tag "$tag"; then ok; else bad "valid_tag rejected $tag"; fi
done
for tag in latest main-abc123 main-ABC1234 feature-abc1234 "main-abc1234;rm" "main-abc1234 " main- ""; do
  if valid_tag "$tag"; then bad "valid_tag accepted '$tag'"; else ok; fi
done

# ── Env completeness (OPS-US-005) ───────────────────────────────────────────────────────────────
cat >"$TMP/x.example" <<'EOF'
# comment
APP_ENV=production
DATABASE_URL=postgres://REPLACE
#OPTIONAL_KEY=
JWT_SECRET=REPLACE_ME
EOF
cat >"$TMP/x.env" <<'EOF'
APP_ENV=production
DATABASE_URL=postgres://u:p@h/db
JWT_SECRET=REPLACE_ME
EOF
expect "missing_keys flags placeholder values" "JWT_SECRET" "$(missing_keys "$TMP/x.example" "$TMP/x.env" | tr '\n' ' ' | sed 's/ $//')"
printf 'APP_ENV=\n' >"$TMP/y.env"
expect "missing_keys flags empty and absent keys" "APP_ENV DATABASE_URL JWT_SECRET" "$(missing_keys "$TMP/x.example" "$TMP/y.env" | tr '\n' ' ' | sed 's/ $//')"
expect "env_value takes the last assignment" "b=c" "$(printf 'K=a\nK=b=c\n' >"$TMP/z.env" && env_value "$TMP/z.env" K)"
for name in api web stack; do
  expect "$name.env.example has no unexpected required keys left empty" "" \
    "$(grep -E '^[A-Z][A-Z0-9_]*=$' "$DEPLOY/env/$name.env.example")"
done

# ── Release log → rollback target (OPS-US-004, BR-005) ──────────────────────────────────────────
log_file=$TMP/releases.log
cat >"$log_file" <<'EOF'
2026-10-01T10:00:00Z pilot api=main-aaaaaaa web=main-1111111 SERVING
2026-10-02T10:00:00Z pilot api=main-bbbbbbb web=main-1111111 SERVING
2026-10-03T10:00:00Z pilot api=main-ccccccc web=main-2222222 FAILED
2026-10-03T10:01:00Z pilot api=main-bbbbbbb web=main-1111111 SERVING auto-rollback
2026-10-04T10:00:00Z pilot api=main-ddddddd web=main-1111111 SERVING
EOF
expect "rollback target skips FAILED releases" "main-bbbbbbb main-1111111" "$(previous_release "$log_file" main-ddddddd main-1111111)"
echo "2026-10-04T11:00:00Z pilot api=main-ddddddd web=main-1111111 ROLLED_BACK operator" >>"$log_file"
echo "2026-10-04T11:01:00Z pilot api=main-bbbbbbb web=main-1111111 SERVING rollback" >>"$log_file"
expect "second rollback walks further back" "main-aaaaaaa main-1111111" "$(previous_release "$log_file" main-bbbbbbb main-1111111)"
expect "no target without history" "" "$(previous_release "$TMP/none.log" main-aaaaaaa main-1111111)"
write_release "$TMP/release.env" main-eeeeeee main-3333333
expect "write/read release" "main-eeeeeee main-3333333" "$(read_release "$TMP/release.env")"

# ── OPS-UT-002: api env parity with internal/config ─────────────────────────────────────────────
if [[ ! -r $APPS/api/internal/config/config.go ]]; then
  printf 'SKIP env parity: no api repo at %s (set KC_APPS)\n' "$APPS"
else
config_keys=$(grep -o 'env:"[A-Z][A-Z0-9_]*' "$APPS/api/internal/config/config.go" | cut -d'"' -f2 | sort -u)
example_keys=$(grep -oE '^#?[A-Z][A-Z0-9_]*=' "$DEPLOY/env/api.env.example" | tr -d '#=' | sort -u)
compose_api_keys=$(awk '/^  api:$/ { a = 1; next } /^  [a-z]/ { a = 0 } a && /^      [A-Z][A-Z0-9_]*:/ { sub(/^ +/, ""); sub(/:.*/, ""); print }' "$DEPLOY/compose.yaml" | sort -u)
echo "$config_keys" >"$TMP/config"
printf '%s\n%s\n' "$example_keys" "$compose_api_keys" | sort -u >"$TMP/covered"
expect "every config key is in api.env.example or compose.yaml" "" "$(comm -23 "$TMP/config" "$TMP/covered" | tr '\n' ' ')"
echo "$example_keys" >"$TMP/example"
expect "api.env.example has no keys the config does not read" "" "$(comm -13 "$TMP/config" "$TMP/example" | tr '\n' ' ')"
echo "$compose_api_keys" | grep -vx GOMEMLIMIT >"$TMP/compose_api" || true
expect "compose sets only keys the config reads (+GOMEMLIMIT)" "" "$(comm -13 "$TMP/config" "$TMP/compose_api" | tr '\n' ' ')"
fi

# web parity — the web repo's src/env.ts against web.env.example.
web_env_ts="$APPS/web/src/env.ts"
if [[ ! -r $web_env_ts ]]; then
  printf 'SKIP web env parity: no web repo at %s (set KC_APPS)\n' "$APPS"
else
  web_keys=$(grep -oE 'NEXT_PUBLIC_[A-Z0-9_]+' "$web_env_ts" | sort -u | tr '\n' ' ')
  web_example=$(grep -oE '^[A-Z][A-Z0-9_]*' "$DEPLOY/env/web.env.example" | sort -u | tr '\n' ' ')
  expect "web.env.example matches web src/env.ts" "$web_keys" "$web_example"
fi

# ── Compose rules ───────────────────────────────────────────────────────────────────────────────
compose=$DEPLOY/compose.yaml
services=$(awk '/^services:/ { s = 1; next } /^[a-z]/ { s = 0 } s && /^  [a-z][a-z0-9_-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$compose")
expect "compose services" "api redis web worker" "$(echo "$services" | sort | tr '\n' ' ' | sed 's/ $//')"
for svc in $services; do
  block=$(awk -v s="  $svc:" '$0 == s { a = 1; next } /^  [a-z]/ || /^[a-z]/ { a = 0 } a' "$compose")
  for rule in 'mem_limit:' 'restart: unless-stopped' 'healthcheck:' 'logging:'; do
    if grep -q "^    $rule" <<<"$block"; then ok; else bad "service $svc lacks '$rule' (OPS-BR-006)"; fi
  done
done
while IFS= read -r line; do
  if [[ $line =~ ports:\ \[\"127\.0\.0\.1:[^\"]+\"\]$ ]]; then ok; else bad "port not bound to 127.0.0.1 (F5): $line"; fi
done < <(grep -E '^\s+ports:' "$compose")
if grep -qE '^\s+build:' "$compose"; then bad "compose has a build: key (OPS-BR-001)"; else ok; fi
if grep -qiE 'image:.*(postgres|minio)' "$compose"; then bad "compose runs Postgres/MinIO (Neon + R2 are off-box)"; else ok; fi
if grep -qE '^\s+image:.*@sha256:[0-9a-f]{64}$' "$compose"; then ok; else bad "third-party images must be pinned by digest"; fi

# ── No image builds on the host (OPS-BR-001) ────────────────────────────────────────────────────
if grep -rnE 'docker (compose |buildx )?build|kc_compose build' "$DEPLOY/ops" "$DEPLOY/host" "$DEPLOY/hestia"; then
  bad "host scripts must only pull images"
else ok; fi

# ── Nginx templates: only known placeholders, balanced braces ───────────────────────────────────
for tpl in "$DEPLOY"/hestia/templates/*.tpl "$DEPLOY"/hestia/templates/*.stpl; do
  unknown=$(grep -oE '@[A-Z_]+@' "$tpl" | sort -u | grep -vxE '@(HTTP_PORT|HTTPS_PORT|API_PORT|WEB_PORT)@' || true)
  expect "$(basename "$tpl") placeholders" "" "$unknown"
  opens=$(tr -cd '{' <"$tpl" | wc -c | tr -d ' ')
  closes=$(tr -cd '}' <"$tpl" | wc -c | tr -d ' ')
  expect "$(basename "$tpl") braces" "$opens" "$closes"
  if grep -qF 'proxy_add_x_forwarded_for' "$tpl"; then bad "$(basename "$tpl") appends X-Forwarded-For"; else ok; fi
done

# ── Part B (OPS-BE-009/014/015): backup prune helper · backup env · scripts · maintenance flag ─
mkdir -p "$TMP/backups"
touch -t 202001010000 "$TMP/backups/old.dump.gz" "$TMP/backups/old.dump.gz.sha256"
touch "$TMP/backups/new.dump.gz" "$TMP/backups/new.dump.gz.sha256"
# backup.sh runs main when executed, so only its prune_list function is loaded here.
prune_src=$(sed -n '/^prune_list()/,/^}/p' "$DEPLOY/ops/backup.sh")
if [[ -n $prune_src ]]; then
  eval "$prune_src"
  pruned=$(prune_list "$TMP/backups" "$(date +%s)" 30)
  expect "prune_list flags exactly the two 2020 files" "2" "$(printf '%s\n' "$pruned" | grep -c old)"
  expect "prune_list keeps recent files" "0" "$(printf '%s\n' "$pruned" | grep -c new)"
else
  bad "prune_list helper missing from backup.sh"
fi

for f in backup.sh restore.sh redaction-probe.sh uptime-check.sh maintenance.sh; do
  if [[ -f "$DEPLOY/ops/$f" ]]; then ok; else bad "missing ops/$f"; fi
done

# backup.env.example declares every key backup.sh and restore.sh require (${KEY:?…}).
script_keys=$(grep -ohE '\$\{[A-Z][A-Z0-9_]*:\?' "$DEPLOY/ops/backup.sh" "$DEPLOY/ops/restore.sh" | tr -d '${:?' | sort -u)
example_keys=$(grep -oE '^[A-Z][A-Z0-9_]*=' "$DEPLOY/env/backup.env.example" | tr -d '=' | sort -u)
expect "backup.env.example covers the backup/restore keys" "" "$(comm -23 <(echo "$script_keys") <(echo "$example_keys") | tr '\n' ' ')"

# Maintenance flag wired into both web templates (OPS-BE-015).
for tpl in kushol-web.tpl kushol-web.stpl; do
  if grep -q "maintenance.flag" "$DEPLOY/hestia/templates/$tpl"; then ok; else bad "maintenance flag missing from $tpl"; fi
done

# ── Bash syntax ─────────────────────────────────────────────────────────────────────────────────
for script in "$DEPLOY"/*.sh "$DEPLOY"/ops/*.sh "$DEPLOY"/host/*.sh "$DEPLOY"/hestia/*.sh "$DEPLOY"/tests/*.sh; do
  if bash -n "$script" 2>"$TMP/syntax"; then ok; else bad "syntax: $script: $(cat "$TMP/syntax")"; fi
done

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
