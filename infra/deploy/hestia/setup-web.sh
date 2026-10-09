#!/usr/bin/env bash
# hestia/setup-web.sh — HestiaCP web domains for Kushol Connect (OPS-BE-006). Run as root:
#
#   sudo bash /opt/kushol/hestia/setup-web.sh
#
# Idempotent; run it twice:
#   1. before DNS points here — creates the HestiaCP user (if missing), the web domains
#      kusholconnect.com (+ www) and api.kusholconnect.com, and installs/applies the Kushol Nginx
#      templates (HTTP only; Nginx answers 502 until the containers run)
#   2. after DNS points here — issues Let's Encrypt certificates, then turns on force-HTTPS, HSTS and
#      the www → apex redirect
# Rerun after editing the templates in the repo, or after a HestiaCP upgrade (DEPLOYMENT.md §6).
set -euo pipefail
# shellcheck source=deploy/hestia/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
preflight

say "Nginx mode"
proxy_system=$(hestia_conf PROXY_SYSTEM)
web_system=$(hestia_conf WEB_SYSTEM)
if [[ $proxy_system == nginx ]]; then
  # nginx in front of apache2: Kushol domains use proxy templates and never reach apache.
  tpl_dir=$HESTIA/data/templates/web/nginx
  http_port='%proxy_port%'
  https_port='%proxy_ssl_port%'
  apply_tpl=v-change-web-domain-proxy-tpl
  ok "nginx proxy in front of $web_system → proxy templates"
elif [[ $web_system == nginx ]]; then
  tpl_dir=$HESTIA/data/templates/web/nginx/php-fpm
  http_port='%web_port%'
  https_port='%web_ssl_port%'
  apply_tpl=v-change-web-domain-tpl
  ok "nginx standalone → web templates"
else
  die "unsupported HestiaCP web stack (WEB_SYSTEM=$web_system PROXY_SYSTEM=$proxy_system) — nginx is required"
fi

say "Templates → $tpl_dir"
for name in kushol-web kushol-api; do
  for ext in tpl stpl; do
    sed -e "s/@HTTP_PORT@/$http_port/g" -e "s/@HTTPS_PORT@/$https_port/g" \
      -e "s/@API_PORT@/$API_PORT/g" -e "s/@WEB_PORT@/$WEB_PORT/g" \
      "$KC_ROOT/hestia/templates/$name.$ext" >"$tpl_dir/$name.$ext"
    chmod 644 "$tpl_dir/$name.$ext"
  done
  ok "$name (api → 127.0.0.1:$API_PORT, web → 127.0.0.1:$WEB_PORT)"
done

say "HestiaCP user and web domains"
ensure_hestia_user
add_domain() { # DOMAIN ALIASES ("none" = no www alias)
  if "$VBIN/v-list-web-domain" "$HESTIA_USER" "$1" >/dev/null 2>&1; then
    ok "$1 exists"
  else
    "$VBIN/v-add-web-domain" "$HESTIA_USER" "$1" "" no "$2"
    ok "added $1"
  fi
}
add_domain "$SITE_DOMAIN" "www.$SITE_DOMAIN"
add_domain "$API_DOMAIN" none
# Re-applied every run so template edits take effect (Hestia regenerates the vhost from it).
"$VBIN/$apply_tpl" "$HESTIA_USER" "$SITE_DOMAIN" kushol-web
"$VBIN/$apply_tpl" "$HESTIA_USER" "$API_DOMAIN" kushol-api
ok "templates applied"

say "TLS (Let's Encrypt)"
# tls DOMAIN [ALIAS] — certificate, then force-HTTPS and HSTS. Returns 1 while DNS is not ready.
tls() {
  local domain=$1 alias=${2:-} name names
  names=("$domain")
  [[ -n $alias ]] && names+=("$alias")
  for name in "${names[@]}"; do
    if ! resolves_here "$name"; then
      warn "$name does not resolve to $PUBLIC_IP yet — no certificate for $domain; rerun after the DNS change (DEPLOYMENT.md §4)"
      return 1
    fi
  done
  if [[ $(web_field "$HESTIA_USER" "$domain" SSL) == yes ]]; then
    ok "$domain has a certificate"
  else
    "$VBIN/v-add-letsencrypt-domain" "$HESTIA_USER" "$domain" "$alias" || {
      warn "Let's Encrypt failed for $domain — see /var/log/hestia/ and retry"
      return 1
    }
    ok "certificate issued for $domain${alias:+ + $alias}"
  fi
  if [[ $(web_field "$HESTIA_USER" "$domain" SSL_FORCE) != yes ]]; then
    "$VBIN/v-add-web-domain-ssl-force" "$HESTIA_USER" "$domain" || return 1
  fi
  if [[ $(web_field "$HESTIA_USER" "$domain" SSL_HSTS) != yes ]]; then
    "$VBIN/v-add-web-domain-ssl-hsts" "$HESTIA_USER" "$domain" || return 1
  fi
  ok "$domain: HTTPS forced, HSTS on"
}
site_tls=no
if tls "$SITE_DOMAIN" "www.$SITE_DOMAIN"; then site_tls=yes; fi
tls "$API_DOMAIN" || true

if [[ $site_tls == yes ]]; then
  say "www → apex (301)"
  if [[ $(web_field "$HESTIA_USER" "$SITE_DOMAIN" REDIRECT) == "$SITE_DOMAIN" ]]; then
    ok "in place"
  else
    "$VBIN/v-add-web-domain-redirect" "$HESTIA_USER" "$SITE_DOMAIN" "$SITE_DOMAIN" 301
    ok "added"
  fi
fi

say "Nginx"
nginx -t
systemctl reload nginx
ok "reloaded"

say "Check through this server's Nginx (502 is expected until the first deploy)"
for url in "http://$SITE_DOMAIN/" "http://$API_DOMAIN/healthz"; do
  host=${url#http://}
  host=${host%%/*}
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$host:80:$PUBLIC_IP" "$url" 2>/dev/null || true)
  ok "$url → ${code:-no answer}"
done
finish
