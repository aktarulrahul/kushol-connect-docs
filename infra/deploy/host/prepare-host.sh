#!/usr/bin/env bash
# host/prepare-host.sh — one-time host preparation on the Hostinger KVM 2 (OPS-BE-016).
#
#   sudo bash /opt/kushol/host/prepare-host.sh [--ssh-key-file FILE]
#
# Idempotent; safe to rerun. Run as root after syncing the deploy bundle to /opt/kushol
# (DEPLOYMENT.md §3). It:
#   1. records the host facts (free -m, df, ss -tlnp, Docker, HestiaCP) to state/host-check-*.txt
#   2. refuses if the chosen loopback ports or the Compose subnet are taken by the co-tenant apps
#   3. installs Docker Engine + Compose from Docker's apt repository when Docker is missing
#      (Hostinger's Docker Manager does not support the HestiaCP image) — an existing Docker and
#      its daemon.json are left alone; log rotation is set per service in compose.yaml
#   4. adds a 2 GB swap file when the host has no swap
#   5. creates the `kushol` deploy user (docker group, SSH key only, no password)
#   6. sets up /opt/kushol: env/ (0700, files 0600, created from the examples), state/
#   7. checks outbound SMTP (port 25) and HTTPS reachability
# The box is shared with two other apps: nothing here restarts Docker or touches their containers.
set -euo pipefail

KC_ROOT=/opt/kushol
DEPLOY_USER=kushol
ssh_key_file=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --ssh-key-file)
      ssh_key_file=${2:?--ssh-key-file needs a path}
      shift 2
      ;;
    *)
      echo "usage: prepare-host.sh [--ssh-key-file FILE]" >&2
      exit 2
      ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $(id -u) -eq 0 ]] || die "run as root (sudo bash $0)"
# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && . /etc/os-release
[[ ${ID:-} == ubuntu ]] || die "expected Ubuntu (found ${PRETTY_NAME:-unknown})"
[[ -r $KC_ROOT/compose.yaml && -d $KC_ROOT/env ]] || die "sync the deploy bundle to $KC_ROOT first (DEPLOYMENT.md §3)"

mkdir -p "$KC_ROOT/state"
stack_env=$KC_ROOT/env/stack.env
[[ -r $stack_env ]] || stack_env=$KC_ROOT/env/stack.env.example
# shellcheck source=/dev/null
. "$stack_env"
: "${API_PORT:?} ${WEB_PORT:?} ${KUSHOL_SUBNET:?}"

# ── 1. Host facts ───────────────────────────────────────────────────────────────────────────────
report=$KC_ROOT/state/host-check-$(date -u +%Y%m%dT%H%M%SZ).txt
say "Host facts → $report"
{
  echo "# host-check $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname -f)"
  echo "## os";        echo "${PRETTY_NAME:-}"; uname -r
  echo "## cpu";       nproc
  echo "## memory";    free -m
  echo "## swap";      swapon --show || true
  echo "## disk";      df -h /
  echo "## listening"; ss -tlnp
  echo "## hestia";    grep -E "^(VERSION|WEB_SYSTEM|PROXY_SYSTEM|MAIL_SYSTEM|ANTIVIRUS_SYSTEM|ANTISPAM_SYSTEM|WEBMAIL_SYSTEM|FIREWALL_SYSTEM)=" /usr/local/hestia/conf/hestia.conf 2>/dev/null || echo "HestiaCP not found"
  echo "## docker"
  if command -v docker >/dev/null; then
    docker --version
    docker compose version || true
    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' || true
    docker network ls --format '{{.Name}}' | while read -r net; do
      printf '%s\t%s\n' "$net" "$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net")"
    done
  else
    echo "not installed"
  fi
} >"$report" 2>&1
cat "$report"

# ── 2. Ports and subnet ─────────────────────────────────────────────────────────────────────────
say "Loopback ports $API_PORT (api) and $WEB_PORT (web)"
kushol_running=no
if command -v docker >/dev/null && [[ -n $(docker ps -q --filter label=com.docker.compose.project=kushol) ]]; then
  kushol_running=yes
fi
for port in "$API_PORT" "$WEB_PORT"; do
  if [[ -n $(ss -Htln "sport = :$port") && $kushol_running == no ]]; then
    die "port $port is already in use (see the listening table above) — choose another in $KC_ROOT/env/stack.env"
  fi
done
echo "ok"

if command -v docker >/dev/null; then
  say "Compose subnet $KUSHOL_SUBNET"
  while read -r net; do
    [[ $net == kushol_kushol ]] && continue
    for subnet in $(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net"); do
      if python3 -c 'import ipaddress,sys; a,b=(ipaddress.ip_network(x,strict=False) for x in sys.argv[1:]); sys.exit(0 if a.version==b.version and a.overlaps(b) else 1)' "$KUSHOL_SUBNET" "$subnet"; then
        die "KUSHOL_SUBNET $KUSHOL_SUBNET overlaps Docker network '$net' ($subnet) — choose another in $KC_ROOT/env/stack.env"
      fi
    done
  done < <(docker network ls --format '{{.Name}}')
  echo "ok"
fi

# ── 3. Docker Engine + Compose ──────────────────────────────────────────────────────────────────
say "Docker Engine"
if command -v docker >/dev/null; then
  echo "already installed: $(docker --version) — left as is"
  docker compose version >/dev/null 2>&1 || die "Docker is installed but the compose plugin is missing: apt-get install docker-compose-plugin"
else
  # https://docs.docker.com/engine/install/ubuntu/ (official apt repository, not the snap)
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  echo "installed: $(docker --version)"
fi

# ── 4. Swap ─────────────────────────────────────────────────────────────────────────────────────
say "Swap"
if [[ -n $(swapon --show --noheadings) ]]; then
  echo "present — left as is"
else
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  echo 'vm.swappiness=10' >/etc/sysctl.d/90-kushol-swap.conf
  sysctl -q -p /etc/sysctl.d/90-kushol-swap.conf
  echo "added 2 GB /swapfile"
fi

# ── 5. Deploy user ──────────────────────────────────────────────────────────────────────────────
say "Deploy user $DEPLOY_USER"
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "exists"
else
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
  passwd --lock "$DEPLOY_USER" >/dev/null
  echo "created (password login locked)"
fi
# docker group membership is root-equivalent: only operators' keys go in authorized_keys.
usermod -aG docker "$DEPLOY_USER"
if [[ -n $ssh_key_file ]]; then
  [[ -r $ssh_key_file ]] || die "cannot read $ssh_key_file"
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
  touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
  while read -r key; do
    [[ -z $key || $key == \#* ]] && continue
    grep -qxF "$key" "/home/$DEPLOY_USER/.ssh/authorized_keys" || echo "$key" >>"/home/$DEPLOY_USER/.ssh/authorized_keys"
  done <"$ssh_key_file"
  chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
  chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
  echo "authorized_keys updated from $ssh_key_file"
elif [[ ! -s /home/$DEPLOY_USER/.ssh/authorized_keys ]]; then
  warn "no SSH key installed for $DEPLOY_USER — rerun with --ssh-key-file <your .pub file>, or deploy as root with 'sudo -u $DEPLOY_USER'"
fi

# ── 6. /opt/kushol layout ───────────────────────────────────────────────────────────────────────
say "Layout $KC_ROOT"
for name in stack api web; do
  if [[ ! -e $KC_ROOT/env/$name.env ]]; then
    cp "$KC_ROOT/env/$name.env.example" "$KC_ROOT/env/$name.env"
    echo "created env/$name.env from the example — fill it in"
  fi
done
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$KC_ROOT"
chmod 700 "$KC_ROOT/env"
chmod 600 "$KC_ROOT"/env/*.env
chmod 755 "$KC_ROOT"/ops/*.sh "$KC_ROOT"/host/*.sh "$KC_ROOT"/hestia/*.sh
echo "ok"

# ── 7. Outbound checks ──────────────────────────────────────────────────────────────────────────
say "Outbound connectivity"
if timeout 8 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
  echo "port 25 out: open (mail can be delivered directly)"
else
  warn "port 25 out looks BLOCKED — mail to Gmail/Outlook will not leave; ask Hostinger support to unblock SMTP"
fi
# The registry answers 401 without a token — any HTTP answer proves it is reachable.
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://registry-1.docker.io/v2/ 2>/dev/null || true)
case $code in
  200 | 401) echo "Docker Hub registry: reachable" ;;
  *) warn "Docker Hub registry unreachable (HTTP ${code:-none})" ;;
esac

say "Next steps (DEPLOYMENT.md §3)"
cat <<EOF
  1. Fill $KC_ROOT/env/api.env (Neon DIRECT url, JWT_SECRET, OTP_PEPPER) and check stack.env/web.env.
  2. Log the deploy user in to Docker Hub with a READ-ONLY access token (private repo airahul/ai):
       sudo -iu $DEPLOY_USER docker login docker.io -u airahul
  3. bash $KC_ROOT/hestia/setup-web.sh      (web domains + Nginx templates; TLS once DNS points here)
  4. bash $KC_ROOT/hestia/setup-mail.sh     (mail domain + mailboxes)
EOF
