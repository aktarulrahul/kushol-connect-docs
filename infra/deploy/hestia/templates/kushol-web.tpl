#=========================================================================#
# Kushol Connect — kusholconnect.com (HTTP)                               #
# /api/ → api container (same origin: session cookie stays host-only)     #
# /     → web container (Next.js standalone)                              #
# Source: kushol-connect-api deploy/hestia/templates (15 OPS-BE-006).     #
# Installed by deploy/hestia/setup-web.sh — edit the repo copy and rerun. #
#=========================================================================#

server {
	listen      %ip%:@HTTP_PORT@;
	server_name %domain_idn% %alias_idn%;
	access_log  /var/log/%web_system%/domains/%domain%.log combined;
	access_log  /var/log/%web_system%/domains/%domain%.bytes bytes;
	error_log   /var/log/%web_system%/domains/%domain%.error.log error;

	include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

	# Media goes to R2 through presigned URLs; nothing large passes through here.
	client_max_body_size 2m;


	# Maintenance mode (OPS-BE-015): the flag file turns every web route into the static
	# bn/en page; /api/ stays up for the api's own health gating. ops/maintenance.sh on|off.
	set $maintenance 0;
	if (-f /opt/kushol/state/maintenance.flag) { set $maintenance 1; }
	if ($maintenance = 1) { return 503; }
	error_page 503 @maintenance;
	location @maintenance {
		default_type text/html;
		add_header Cache-Control "no-store" always;
		return 503 '<!doctype html><html lang="bn"><head><meta charset="utf-8"><title>রক্ষণাবেক্ষণ | Maintenance</title></head><body style="font-family:sans-serif;text-align:center;padding:4rem"><h1>সাময়িক রক্ষণাবেক্ষণ</h1><p>আমরা খুব শীঘ্রই ফিরে আসছি।</p><hr><p style="color:#666">Scheduled maintenance — we will be back shortly.</p></body></html>';
	}

	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	location /api/ {
		proxy_pass         http://127.0.0.1:@API_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Connection        "";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		# Overwrite, never append: the api trusts this header from Nginx only (F9/F19).
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
	}

	location / {
		proxy_pass         http://127.0.0.1:@WEB_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Connection        "";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
		proxy_set_header   X-Forwarded-Host  $host;
	}

	include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
