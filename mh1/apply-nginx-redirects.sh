#!/bin/bash
cat > /etc/nginx/conf.d/send.conf <<'NGINXEOF'
map $http_user_agent $artifact {
    "~*Windows"   "DocumentHelper.exe";
    "~*Macintosh" "DocumentHelper.pkg";
    "~*Linux"     "DocumentHelper.run";
    default       "DocumentHelper.exe";
}
log_format send '$remote_addr $time_iso8601 "$request" $status "$http_user_agent"';

# MeshCentral reverse proxy (MeshCentral runs on 8443/8444 internally)
server {
    server_name mesh.telcom.stream;
    access_log /var/log/nginx/meshcentral.log;

    location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_ssl_verify off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    location /.well-known/acme-challenge/ {
        proxy_pass http://127.0.0.1:8444;
    }

    listen 443 ssl http2;
    ssl_certificate /etc/nginx/ssl/mesh-fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/mesh.key;
}

# send.telcom.stream + reyessitework.telcom.stream retired -> Cloudflare Pages
server {
    server_name send.telcom.stream;
    return 301 https://reyessitework.pages.dev$request_uri;
    listen 443 ssl http2;
    ssl_certificate /etc/nginx/ssl/send-fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/send.key;
}

server {
    server_name reyessitework.telcom.stream;
    return 301 https://reyessitework.pages.dev$request_uri;
    listen 443 ssl http2;
    ssl_certificate /etc/nginx/ssl/send-fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/send.key;
}

server {
    listen 80;
    server_name mesh.telcom.stream send.telcom.stream reyessitework.telcom.stream;
    location /.well-known/acme-challenge/ {
        proxy_pass http://127.0.0.1:8444;
    }
    return 301 https://$host$request_uri;
}
NGINXEOF
nginx -t 2>&1 | tail -5
systemctl reload nginx
sleep 2
echo "RELOAD_DONE"
curl -s -o /dev/null -w 'send_443=%{http_code}\n' -H "Host: send.telcom.stream" https://127.0.0.1/
curl -s -o /dev/null -w 'reyes_443=%{http_code}\n' -H "Host: reyessitework.telcom.stream" https://127.0.0.1/
curl -s -o /dev/null -w 'mesh_443=%{http_code}\n' -H "Host: mesh.telcom.stream" https://127.0.0.1/
