#=========================================================================#
# Kushol Connect — api.kusholconnect.com (HTTP)                           #
# Mobile REST + WebSocket (/ws) + webhooks → api container                #
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

	client_max_body_size 2m;

	location ~ /\.(?!well-known\/) {
		deny all;
		return 404;
	}

	# Chat gateway (05) at the contract path GET /api/v1/ws; the app pings, so 300 s idle is plenty.
	# The session token travels in the query string, so this route is not access-logged.
	location = /api/v1/ws {
		access_log off;
		proxy_pass         http://127.0.0.1:@API_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Upgrade           $http_upgrade;
		proxy_set_header   Connection        "upgrade";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
		proxy_read_timeout 300s;
		proxy_send_timeout 300s;
	}

	# Attachment upload (05, owner 2026-10-18): the client streams the file to the api, which streams
	# it on to R2. Only this route takes more than 2 MB: 21 MB covers the largest kind's 20 MB cap
	# (the api enforces each kind's cap and sniffs the bytes). Not spooled to disk here, and the
	# read timeout covers the api's 10-minute upload window for slow mobile links.
	location = /api/v1/media/upload {
		client_max_body_size    21m;
		proxy_request_buffering off;
		proxy_pass         http://127.0.0.1:@API_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Connection        "";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		# Overwrite, never append: the api trusts this header from Nginx only (F9/F19).
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
		proxy_read_timeout 660s;
	}

	# Profile photo upload (03 · owner 2026-10-20): the photo streams to the api, which checks it
	# and stores it in R2. The api caps it at 10 MB; the 2 MB server default made larger phone
	# photos fail with 413, so nobody else ever saw them.
	location = /api/v1/me/avatar {
		client_max_body_size    11m;
		proxy_request_buffering off;
		proxy_pass         http://127.0.0.1:@API_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Connection        "";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		# Overwrite, never append: the api trusts this header from Nginx only (F9/F19).
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
		proxy_read_timeout 360s;
	}

	location / {
		proxy_pass         http://127.0.0.1:@API_PORT@;
		proxy_http_version 1.1;
		proxy_set_header   Connection        "";
		proxy_set_header   Host              $host;
		proxy_set_header   X-Real-IP         $remote_addr;
		# Overwrite, never append: the api trusts this header from Nginx only (F9/F19).
		proxy_set_header   X-Forwarded-For   $remote_addr;
		proxy_set_header   X-Forwarded-Proto $scheme;
	}

	include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
