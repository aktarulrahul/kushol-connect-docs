# HestiaCP — web (Nginx, TLS) and mail

**Module:** `15-deployment-operations` (OPS-BE-006) + architecture plan §7 (mail) ·
**Last updated:** 2026-10-02 · Runbook: [`../DEPLOYMENT.md`](../DEPLOYMENT.md) §3.6, §4, §5

HestiaCP owns the parts of the server that face the internet: Nginx on ports 80/443, Let's Encrypt
certificates, the firewall and fail2ban, and the mail server. The Kushol containers sit behind it on
loopback ports and never bind 25/80/443/465/587/993.

## 1. Web

### 1.1 Domains and routing

Both domains belong to the HestiaCP user `kusholconnect`.

| Domain (HestiaCP web domain) | Alias | Template | Request | Goes to |
| --- | --- | --- | --- | --- |
| `kusholconnect.com` | `www.kusholconnect.com` | `kushol-web` | `/api/…` | api `127.0.0.1:8180` — same origin, so the web session cookie stays host-only and no CORS is needed |
| | | | everything else | web `127.0.0.1:3100` |
| | | | `www.…` (after TLS) | 301 → `https://kusholconnect.com…` |
| `api.kusholconnect.com` | none | `kushol-api` | `/api/v1/ws` | api, WebSocket upgrade, 300 s read/send timeout (05 chat; the app pings); not access-logged, because the session token is in the query string |
| | | | everything else | api (mobile REST, `/healthz`, `/readyz`, payment/ERP webhooks) |

Paths starting with a dot (except `/.well-known/`) return 404 on both. Request bodies are capped at
2 MB (`client_max_body_size 2m`) — uploads go straight to R2 through presigned URLs.

### 1.2 Headers

| Header | How |
| --- | --- |
| `Host`, `X-Forwarded-Proto`, `X-Real-IP` | set on every proxied request |
| `X-Forwarded-For` | **overwritten** with the client address (`$remote_addr`), never appended, so a client cannot forge its IP; the api trusts it only from the Compose subnet ([`stack.md`](stack.md) §1) |
| `X-Forwarded-Host` | web only |
| `X-Request-Id` | passed through untouched; the api reuses a valid incoming value (≤ 64 printable ASCII characters), otherwise generates a UUID v7, and echoes it on every response |
| `Connection ""` + HTTP/1.1 | keep-alive to the containers; `/api/v1/ws` sends `Upgrade`/`Connection: upgrade` instead |
| Security headers, web (`/`) | `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin` (added by the template). Content-Security-Policy: not yet — module 07 (08-gaps G-5) |
| Security headers, api (`/api/` and `api.`) | the api's own (`nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`) + HSTS from HestiaCP |

### 1.3 TLS

- Certificates: Let's Encrypt through HestiaCP (`v-add-letsencrypt-domain`), issued for
  `kusholconnect.com` + `www.kusholconnect.com` and for `api.kusholconnect.com`. HestiaCP renews
  them automatically; a failed renewal alerts in the panel, and the old certificate serves until it
  expires (edge case 7).
- HTTP → HTTPS 301 for every path (`v-add-web-domain-ssl-force`), HSTS one year
  (`v-add-web-domain-ssl-hsts`). Let's Encrypt's HTTP challenge still works: HestiaCP adds its own
  challenge location and the challenge follows the redirect.
- TLS 1.3 early data (0-RTT) is answered with `425 Too Early`, so a replayed request never reaches the
  apps; clients retry after the handshake.
- IPv4 only: HestiaCP's vhosts listen on the server's IPv4 address, so the zone has no AAAA records
  for the web names.

### 1.4 The templates

Source: [`../hestia/templates/`](../hestia/templates/) — `kushol-web.tpl` (HTTP), `kushol-web.stpl`
(HTTPS), `kushol-api.tpl`, `kushol-api.stpl`. They are HestiaCP templates: `%ip%`, `%domain_idn%`,
`%alias_idn%`, `%ssl_pem%`, `%ssl_key%`, `%home%`, `%user%`, `%domain%`, `%web_system%` are filled by
HestiaCP for each domain. Ours adds four placeholders that `setup-web.sh` fills when installing:

| Placeholder | Proxy mode (nginx → apache2) | nginx-only mode |
| --- | --- | --- |
| `@HTTP_PORT@` | `%proxy_port%` | `%web_port%` |
| `@HTTPS_PORT@` | `%proxy_ssl_port%` | `%web_ssl_port%` |
| `@API_PORT@` / `@WEB_PORT@` | `API_PORT` / `WEB_PORT` from `stack.env` | same |
| Installed into | `/usr/local/hestia/data/templates/web/nginx/` | `/usr/local/hestia/data/templates/web/nginx/php-fpm/` |
| Applied with | `v-change-web-domain-proxy-tpl` | `v-change-web-domain-tpl` |

They keep HestiaCP's include hooks — `nginx.forcessl.conf*`, `nginx.hsts.conf*`, `nginx.conf_*`,
`nginx.ssl.conf_*` — so force-HTTPS, HSTS, the www redirect and Let's Encrypt challenges keep working.
In proxy mode the apache vhost HestiaCP also creates is never reached.

**Changing routing or headers:** edit the template in the repo → re-sync the bundle → rerun
`hestia/setup-web.sh` (it re-renders and re-applies; `nginx -t` runs before the reload). Do not edit
the generated vhost files or switch the domain's template in the panel — the next rebuild or rerun
replaces them. Custom template names survive HestiaCP upgrades; rerunning after an upgrade is cheap.

**Changing a port:** edit `API_PORT`/`WEB_PORT` in `env/stack.env`, rerun `setup-web.sh`, then
`ops/deploy.sh pilot` (same tags) so Compose publishes the new port.

## 2. Mail

### 2.1 What exists after `setup-mail.sh`

Mail domain `kusholconnect.com` on HestiaCP's Exim (SMTP) + Dovecot (IMAP) with DKIM (2048-bit RSA),
anti-spam and anti-virus when HestiaCP has them installed, and webmail when a webmail client is
installed.

| Address | Kind | Quota | Who |
| --- | --- | --- | --- |
| `aktarul.islam@kusholconnect.com` | mailbox | 2048 MB | Aktarul Islam |
| `jafrin.myoria@kusholconnect.com` | mailbox | 2048 MB | Jafrin Myoria |
| `atiqul.islam@kusholconnect.com` | mailbox | 2048 MB | Atiqul Islam |
| `noreply@kusholconnect.com` | mailbox | 256 MB | the api: SMTP login for OTP and notification mail (03/06); From `Kushol Connect <noreply@…>`, Reply-To `hello@` |
| `hello@` | alias → `aktarul.islam@` | — | public contact on the landing page |
| `dmarc@` | alias → `aktarul.islam@` | — | DMARC aggregate reports |
| `postmaster@`, `abuse@` | aliases → `aktarul.islam@` | — | expected by other mail servers |

`noreply@` has no autoreply: replying to spam would send backscatter from the shared IP. Its HestiaCP
send-rate limit is the panel default until OTP volume is known (08-gaps G-10). The set of mailboxes
is `TODO: Confirm` (08-gaps G-9).

### 2.2 DNS for mail (Hostinger DNS)

| Type | Name | Value |
| --- | --- | --- |
| A | `mail` | `72.61.114.20` |
| A | `webmail` | `72.61.114.20` |
| MX | `@` | `mail.kusholconnect.com`, priority 10 |
| TXT | `@` | `v=spf1 mx ip4:72.61.114.20 ip6:2a02:4780:5e:99d7::1 -all` — the only SPF record; `ip6` stays because the server has IPv6 and Exim uses it |
| TXT | `mail._domainkey` | the DKIM public key `setup-mail.sh` prints (`v-list-mail-domain-dkim-dns`) |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@kusholconnect.com` → `p=quarantine` after 2–4 weeks of clean reports |
| PTR | — | unchanged `srv1100749.hstgr.cloud` (resolves back on IPv4 and IPv6; shared with the co-tenant apps) |

DNS stays on Hostinger's nameservers; HestiaCP's own DNS server is not used for this zone (running
both would split the truth).

### 2.3 Certificates for mail clients

Once `mail.` and `webmail.` resolve to the server, the second run of `setup-mail.sh` issues a Let's
Encrypt certificate for them (`v-add-letsencrypt-domain <user> kusholconnect.com '' yes`); HestiaCP
serves it to IMAP/SMTP clients by SNI and renews it.

### 2.4 Client settings

| Protocol | Server | Port / security | Login |
| --- | --- | --- | --- |
| IMAP | `mail.kusholconnect.com` | 993, SSL/TLS | full address + password |
| SMTP (sending) | `mail.kusholconnect.com` | 587, STARTTLS | full address + password |
| Webmail | `https://webmail.kusholconnect.com` | — | full address + password |

The api uses the same SMTP settings (`SMTP_*` in `env/api.env`, [`stack.md`](stack.md) §3.2): it
connects from its container to `mail.kusholconnect.com:587` on the same server.

### 2.5 Verifying deliverability

1. Send from webmail to a Gmail and an Outlook address; open "show original" and look for
   `spf=pass`, `dkim=pass`, `dmarc=pass`.
2. Score a message with a mail-tester service; check the IP on common blocklists.
3. Watch `dmarc@` reports for a few weeks before tightening DMARC.

A new, shared IP has no sending reputation: early mail may land in spam until volume is steady. The
other two apps on this IP affect Kushol's reputation and vice versa. If OTP mail is delayed or
filtered, the upgrade path is a transactional provider (architecture plan §7.3).

**Pitfalls found on 2026-10-09** (read the reason in `/var/log/exim4/mainlog`; frozen messages with
`exim -bp`, a failure notice's text with `exim -Mvb <id>`):

| Symptom in the log | Cause | Fix |
| --- | --- | --- |
| `rejected RCPT … in a black list at zen.spamhaus.org` for Gmail and every other sender | Spamhaus refuses lookups from public resolvers (this VPS uses Hostinger's and 1.1.1.1) and answers `127.255.255.254`, which Exim reads as "listed" | `setup-mail.sh` removes Spamhaus from `/etc/exim4/dnsbl.conf` (server-wide; original in `dnsbl.conf.orig`). To use Spamhaus again: a Spamhaus DQS key or a local recursive resolver |
| `550-5.7.26 … sender is unauthenticated … SPF [] … DKIM = did not pass` when a mailbox forwards to Gmail | forwarded failure notices have an empty sender, so Gmail checks the server name `srv1100749.hstgr.cloud`, which has no SPF of ours; with "do not store forwarded mail" the copy is lost | keep a local copy on forwarding mailboxes; publish the DKIM record |
| `** noreply@ubuntu-hestia.localhost: Too many "Received" headers - suspected mail loop` | the VPS image's panel contact points back at this server | `v-change-user-contact <user> <real address>` (`setup-mail.sh` flags it) |
| `550-5.1.1 The email account that you tried to reach does not exist` | a typo in the recipient | — |

### 2.6 Everyday mail administration

| Task | How |
| --- | --- |
| Add a mailbox | `MAILBOXES="new.person:2048" bash /opt/kushol/hestia/setup-mail.sh` (root) — password in the new credentials file |
| Change a password, quota, alias, forward | HestiaCP panel → Mail → `kusholconnect.com` (log in as admin, "login as" `kusholconnect`) |
| Remove a mailbox | panel — and remove it from the default `MAILBOXES` list in the repo if it should not come back |
| Backups | mailboxes are on the VPS disk only (`/home/kusholconnect/mail/`); HestiaCP user backups must be copied off-box — Part B (08-gaps G-7) |
