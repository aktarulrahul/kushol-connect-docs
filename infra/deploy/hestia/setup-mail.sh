#!/usr/bin/env bash
# hestia/setup-mail.sh — mail for kusholconnect.com on HestiaCP's Exim + Dovecot
# (docs/infra/architecture-and-deployment.md §7). Run as root:
#
#   sudo bash /opt/kushol/hestia/setup-mail.sh
#
# Idempotent. Creates the mail domain (DKIM 2048, anti-spam, anti-virus when ClamAV is installed,
# webmail), the four mailboxes and the aliases below, and prints the DNS records to add. Run it
# again once those records resolve to issue the Let's Encrypt certificate for mail. and webmail.
# It also drops Spamhaus from Exim's blocklists when Spamhaus refuses this server's resolver (that
# rejected all inbound mail) and flags panel users whose notification address loops.
# Passwords are generated here and written only to a root-only file under /root (hestia/lib.sh);
# existing mailboxes are never touched, so rerunning never changes a password.
set -euo pipefail
# shellcheck source=deploy/hestia/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
preflight

# account:quota-MB. Three people, plus noreply@ — the api's SMTP login for OTP and notification
# mail (03/06), From "Kushol Connect <noreply@…>", Reply-To hello@.
MAILBOXES=${MAILBOXES:-"aktarul.islam:2048 jafrin.myoria:2048 atiqul.islam:2048 noreply:256"}
# Aliases delivered to ALIAS_OWNER's mailbox: hello@ is the public contact on the landing page;
# dmarc@ receives DMARC reports; postmaster@/abuse@ are expected by other mail servers.
MAIL_ALIASES=${MAIL_ALIASES:-"hello dmarc postmaster abuse"}
ALIAS_OWNER=${ALIAS_OWNER:-aktarul.islam}
domain=$SITE_DOMAIN

say "Preflight"
[[ -n $(hestia_conf MAIL_SYSTEM) ]] || die "HestiaCP has no mail system installed"
supports_password_file || die "this HestiaCP cannot read passwords from a file — update HestiaCP first (passwords must not go on the command line)"
ensure_hestia_user

say "Mail domain $domain"
if "$VBIN/v-list-mail-domain" "$HESTIA_USER" "$domain" >/dev/null 2>&1; then
  ok "exists"
else
  antispam=no
  antivirus=no
  [[ -n $(hestia_conf ANTISPAM_SYSTEM) ]] && antispam=yes
  [[ -n $(hestia_conf ANTIVIRUS_SYSTEM) ]] && antivirus=yes
  "$VBIN/v-add-mail-domain" "$HESTIA_USER" "$domain" "$antispam" "$antivirus" yes 2048
  ok "added (DKIM 2048, anti-spam $antispam, anti-virus $antivirus)"
fi
[[ $(mail_field "$HESTIA_USER" "$domain" DKIM) == yes ]] || warn "DKIM is off for $domain — turn it on in HestiaCP → Mail → $domain"

say "Mailboxes"
read -r -a mailboxes <<<"$MAILBOXES"
for entry in "${mailboxes[@]}"; do
  account=${entry%%:*}
  quota=${entry##*:}
  if "$VBIN/v-list-mail-account" "$HESTIA_USER" "$domain" "$account" >/dev/null 2>&1; then
    ok "$account@$domain exists (password unchanged)"
    continue
  fi
  password=$(new_password)
  file=$(password_file "$password")
  if "$VBIN/v-add-mail-account" "$HESTIA_USER" "$domain" "$account" "$file" "$quota"; then
    rm -f "$file"
    record_secret "$account@$domain" "$password"
    ok "created $account@$domain (quota $quota MB)"
  else
    rm -f "$file"
    die "could not create $account@$domain"
  fi
done

say "Aliases → $ALIAS_OWNER@$domain"
read -r -a aliases <<<"$MAIL_ALIASES"
for alias in "${aliases[@]}"; do
  rc=0
  out=$("$VBIN/v-add-mail-account-alias" "$HESTIA_USER" "$domain" "$ALIAS_OWNER" "$alias" 2>&1) || rc=$?
  case $rc in
    0) ok "added $alias@$domain" ;;
    "$E_EXISTS") ok "$alias@$domain exists" ;;
    *) warn "could not add $alias@$domain (exit $rc: $out) — add it in HestiaCP → Mail → $domain" ;;
  esac
done

say "TLS for mail clients (Let's Encrypt)"
names=("mail.$domain")
if [[ -n $(mail_field "$HESTIA_USER" "$domain" WEBMAIL) ]]; then
  names+=("$(mail_field "$HESTIA_USER" "$domain" WEBMAIL_ALIAS)")
fi
if [[ $(mail_field "$HESTIA_USER" "$domain" SSL) == yes ]]; then
  ok "certificate present"
else
  ready=yes
  for name in "${names[@]}"; do resolves_here "$name" || ready=no; done
  if [[ $ready == yes ]]; then
    if "$VBIN/v-add-letsencrypt-domain" "$HESTIA_USER" "$domain" "" yes; then
      ok "certificate issued for ${names[*]}"
    else
      warn "Let's Encrypt failed for ${names[*]} — see /var/log/hestia/ and rerun"
    fi
  else
    warn "${names[*]} do not resolve to $PUBLIC_IP yet — add the DNS records below, then rerun for the certificate"
  fi
fi

say "Outbound SMTP"
if timeout 8 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
  ok "port 25 out is open"
else
  warn "port 25 out looks BLOCKED — mail will not leave the server; ask Hostinger support to unblock SMTP"
fi

say "Inbound spam blocklists (Exim DNSBL — server-wide)"
# Spamhaus refuses lookups that arrive through public resolvers (this VPS uses Hostinger's and
# 1.1.1.1) and answers 127.255.255.x. Exim's `dnslists` check reads any answer as "listed", so every
# inbound message — Gmail included — was rejected "in a black list at zen.spamhaus.org" (2026-10-09).
# The test entry 127.0.0.2 shows what this server's resolver gets: 127.0.0.x means Spamhaus works.
dnsbl=/etc/exim4/dnsbl.conf
if [[ -f $dnsbl ]] && grep -q spamhaus "$dnsbl"; then
  answer=$(getent ahostsv4 2.0.0.127.zen.spamhaus.org | awk 'NR == 1 { print $1 }')
  if [[ $answer == 127.0.0.* ]]; then
    ok "Spamhaus answers this server's resolver ($answer for the test entry) — kept"
  else
    [[ -e $dnsbl.orig ]] || cp "$dnsbl" "$dnsbl.orig"
    sed -i '/spamhaus/d' "$dnsbl"
    ok "removed Spamhaus from $dnsbl — it refuses this server's resolver (${answer:-no answer}); original kept as $dnsbl.orig"
  fi
else
  ok "Spamhaus not in use"
fi

say "Panel notifications"
# The VPS image ships an admin contact like noreply@ubuntu-hestia.localhost; that name points at this
# server, so every panel notice loops until Exim freezes it ("Too many Received headers").
for conf in "$HESTIA"/data/users/*/user.conf; do
  user=$(basename "$(dirname "$conf")")
  contact=$(sed -n "s/^CONTACT='\(.*\)'$/\1/p" "$conf")
  case $contact in
    "" | *.localhost | *.local) warn "HestiaCP user $user sends its notices to '${contact:-nobody}', which loops — set a real address: $VBIN/v-change-user-contact $user <address>" ;;
    *) ok "$user → $contact" ;;
  esac
done

say "DNS records to add (Hostinger DNS: hPanel → Domains → $domain → DNS)"
spf="v=spf1 mx ip4:$PUBLIC_IP${PUBLIC_IP6:+ ip6:$PUBLIC_IP6} -all"
cat <<EOF
   A     mail            $PUBLIC_IP
   A     webmail         $PUBLIC_IP
   MX    @               mail.$domain   (priority 10)
   TXT   @               $spf
   TXT   _dmarc          v=DMARC1; p=none; rua=mailto:dmarc@$domain
   TXT   mail._domainkey (the DKIM value below — HestiaCP generated it)
   PTR   unchanged: $PUBLIC_IP → $(hostname -f) already resolves back (shared with the co-tenant apps)
EOF
"$VBIN/v-list-mail-domain-dkim-dns" "$HESTIA_USER" "$domain" || warn "could not list the DKIM record"

say "Mail client settings for the team"
cat <<EOF
   IMAP     mail.$domain : 993 (SSL/TLS)
   SMTP     mail.$domain : 587 (STARTTLS), login = full address
   Webmail  https://$(mail_field "$HESTIA_USER" "$domain" WEBMAIL_ALIAS)
   api      SMTP_* in /opt/kushol/env/api.env: SMTP_USERNAME=noreply@$domain, SMTP_PASSWORD from the credentials file
EOF
finish
