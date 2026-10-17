#!/usr/bin/env bash
# build-push-images.sh [api] [web] [--skip-gate] [--allow-unpushed] [--dry-run]
#
# Builds the api and/or web image from each app repo's committed `main` and pushes it to the private
# registry (docs/images.md §2). Runs on the owner's Mac — Docker running, `docker login -u airahul`
# done — never on the VPS (OPS-BR-001). From the workspace root:
#
#   bash docs/infra/deploy/build-push-images.sh          # both apps
#   bash docs/infra/deploy/build-push-images.sh web      # web only
#
# Per app: on `main`, clean and pushed (the tag names that commit) → the app's gate (api `make gate`,
# web `pnpm gate`) → skip if <image>:<prefix>main-<sha7> already exists (tags are immutable,
# OPS-BR-005) → `docker buildx build --platform linux/amd64 --push`. Prints the deploy command.
#
#   --skip-gate       skip the gates (CI already ran them on that commit)
#   --allow-unpushed  build a local commit that origin/main does not have yet
#   --dry-run         check everything, print the gate/build commands instead of running them
#
# Settings: image names, tag prefixes and the web's NEXT_PUBLIC_* values come from env/stack.env and
# env/web.env (falling back to the .example files); API_IMAGE, WEB_IMAGE, API_TAG_PREFIX,
# WEB_TAG_PREFIX override them. KC_APPS points at the app repos (default: applications/ beside docs/).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APPS=${KC_APPS:-$HERE/../../../applications}
[[ -d $APPS ]] && APPS=$(cd "$APPS" && pwd) # readable paths in messages

say() { printf '\n==== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
usage() { die "usage: build-push-images.sh [api] [web] [--skip-gate] [--allow-unpushed] [--dry-run]"; }

apps=() gate=yes allow_unpushed=no dry=no
for arg in "$@"; do
  case $arg in
    api | web) apps+=("$arg") ;;
    --skip-gate) gate=no ;;
    --allow-unpushed) allow_unpushed=yes ;;
    --dry-run) dry=yes ;;
    -h | --help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' && exit 0 ;;
    *) usage ;;
  esac
done
[[ ${#apps[@]} -gt 0 ]] || apps=(api web)

# setting KEY FILE — the environment wins, then env/FILE.env, then env/FILE.env.example.
setting() {
  local key=$1 file=$HERE/env/$2.env
  if [[ -n ${!key:-} ]]; then
    printf '%s' "${!key}"
    return
  fi
  [[ -r $file ]] || file=$file.example
  awk -v k="$key" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { printf "%s", v }' "$file"
}
run() {
  if [[ $dry == yes ]]; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# ── Preflight: tools, then every selected repo — before any long gate or build ──────────────────
say "Preflight"
command -v docker >/dev/null || die "docker is not installed"
docker buildx version >/dev/null 2>&1 || die "docker buildx is missing (it ships with Docker Desktop)"
if [[ $dry == no ]]; then
  docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop"
fi
[[ -d $APPS ]] || die "no app repos at $APPS — run this from the workspace (or set KC_APPS)"

repos=() refs=() shas=() todo=()
for app in "${apps[@]}"; do
  repo=$APPS/$app
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git repository"
  branch=$(git -C "$repo" branch --show-current)
  [[ $branch == main ]] || die "$app is on branch '$branch' — images are built from main (git -C $repo switch main)"
  dirty=$(git -C "$repo" status --porcelain)
  [[ -z $dirty ]] || die "$app has uncommitted changes — commit or stash them; the tag must name exactly the code in the image:
$dirty"
  git -C "$repo" fetch --quiet origin main 2>/dev/null || warn "$app: could not fetch origin/main — comparing with the last fetched copy"
  if ! git -C "$repo" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    if [[ $allow_unpushed == yes ]]; then
      warn "$app: HEAD is not on origin/main yet (--allow-unpushed)"
    else
      die "$app: HEAD is not on origin/main — push it first (git -C $repo push), or pass --allow-unpushed"
    fi
  fi
  sha=$(git -C "$repo" rev-parse --short=7 HEAD)
  if [[ $app == api ]]; then
    ref="$(setting API_IMAGE stack):$(setting API_TAG_PREFIX stack)main-$sha"
  else
    ref="$(setting WEB_IMAGE stack):$(setting WEB_TAG_PREFIX stack)main-$sha"
  fi
  # Tags are immutable: an existing tag is never rebuilt. "not found" is the only answer that means
  # "build it"; anything else (not logged in, network) stops here instead of after a long build.
  if err=$(docker buildx imagetools inspect "$ref" 2>&1 >/dev/null); then
    echo "$app: $ref is already pushed — skipping (tags are immutable)"
    continue
  fi
  case $err in
    *"not found"* | *"manifest unknown"* | *MANIFEST_UNKNOWN*) ;;
    *) die "cannot query the registry for $ref — logged in? (docker login -u airahul)
$err" ;;
  esac
  echo "$app: will build $ref"
  repos+=("$repo") refs+=("$ref") shas+=("$sha") todo+=("$app")
done

api_url=$(setting NEXT_PUBLIC_API_URL web)
site_url=$(setting NEXT_PUBLIC_SITE_URL web)

# ── Gates (what CI's gate job runs) ─────────────────────────────────────────────────────────────
if [[ ${#todo[@]} -gt 0 && $gate == yes ]]; then
  for i in "${!todo[@]}"; do
    say "Gate: ${todo[i]}"
    case ${todo[i]} in
      api) run make -C "${repos[i]}" gate ;;
      web) run pnpm --dir "${repos[i]}" gate ;;
    esac
  done
elif [[ ${#todo[@]} -gt 0 ]]; then
  warn "gates skipped (--skip-gate) — publish only commits whose gate is green"
fi

# ── Build and push ──────────────────────────────────────────────────────────────────────────────
# (guarded: macOS bash 3.2 treats an empty array as unset under `set -u`)
[[ ${#todo[@]} -gt 0 ]] && for i in "${!todo[@]}"; do
  app=${todo[i]}
  say "Build + push: $app → ${refs[i]}"
  args=(buildx build --platform linux/amd64 -f "$HERE/../docker/$app.Dockerfile"
    --label "org.opencontainers.image.revision=$(git -C "${repos[i]}" rev-parse HEAD)"
    -t "${refs[i]}" --push)
  if [[ $app == web ]]; then
    # NEXT_PUBLIC_* are inlined at build time — the image serves exactly this origin (images.md §3.2).
    args+=(--build-arg "NEXT_PUBLIC_API_URL=$api_url" --build-arg "NEXT_PUBLIC_SITE_URL=$site_url")
  fi
  run docker "${args[@]}" "${repos[i]}"
done

# ── Next step ───────────────────────────────────────────────────────────────────────────────────
say "Done"
deploy_args=""
for app in "${apps[@]}"; do
  deploy_args="$deploy_args $app=main-$(git -C "$APPS/$app" rev-parse --short=7 HEAD)"
done
[[ $dry == yes ]] && echo "(dry run — nothing was built or pushed)"
echo "Deploy with:"
echo "  bash docs/infra/deploy/deploy-web-api-vps.sh$deploy_args"
