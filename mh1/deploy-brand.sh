#!/bin/bash
set -euo pipefail

DATA=/opt/meshcentral/meshcentral-data
WEB=/opt/meshcentral/meshcentral-web
STAMP=$(date +%Y%m%d-%H%M%S)
SRC=/tmp/brand

sudo mkdir -p "$WEB/public/styles" "$WEB/public/scripts" "$WEB/public/images"

# Web overlay assets
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/custom.css"          "$WEB/public/styles/custom.css"
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/custom.js"           "$WEB/public/scripts/custom.js"
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/reyes-title.png"     "$WEB/public/images/reyes-title.png"
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/favicon.ico"         "$WEB/public/favicon.ico"
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/favicon-303x303.png" "$WEB/public/favicon-303x303.png"

# Domain pictures served by MeshCentral from the data path
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/reyes-title.png" "$DATA/reyes-title.png"
sudo install -m 644 -o meshcentral -g meshcentral "$SRC/login-bg.jpg"    "$DATA/login-bg.jpg"

# Config backup + install
sudo cp -a "$DATA/config.json" "$DATA/config.json.bak-$STAMP"
sudo install -m 600 -o meshcentral -g meshcentral "$SRC/config.json" "$DATA/config.json"
sudo python3 -m json.tool "$DATA/config.json" > /dev/null && echo "JSON OK"
echo "CONFIG_BACKUP=$DATA/config.json.bak-$STAMP"

sudo chown -R meshcentral:meshcentral "$WEB"
sudo systemctl restart meshcentral
sleep 5
echo "STATE=$(systemctl is-active meshcentral)"

echo "--- login page ---"
LOGIN_CODE=$(curl -sk -o /tmp/login.out -w '%{http_code}' https://127.0.0.1:8443/)
echo "LOGIN=$LOGIN_CODE"
grep -o '<title>[^<]*</title>' /tmp/login.out | head -1
echo "custom_css=$(grep -c 'styles/custom.css' /tmp/login.out)"
echo "custom_js=$(grep -c 'scripts/custom.js' /tmp/login.out)"
echo "title1=$(grep -c 'Mesh-Marcus Reyes' /tmp/login.out)"
echo "bg=$(grep -o "background-image:url('[^']*')" /tmp/login.out | head -1)"
echo "welcome=$(grep -o "welcomeText = decodeURIComponent('[^']*')" /tmp/login.out | head -1)"
echo "footer=$(grep -o '256-bit TLS[^<]*' /tmp/login.out | head -1)"

echo "--- asset routes ---"
echo "LOGO=$(curl -sk -o /tmp/logo.out -w '%{http_code} %{content_type} %{size_download}' https://127.0.0.1:8443/logo.png)"
echo "WELCOME=$(curl -sk -o /tmp/welcome.out -w '%{http_code} %{content_type} %{size_download}' https://127.0.0.1:8443/welcome.png)"
echo "FAVICON=$(curl -sk -o /dev/null -w '%{http_code} %{content_type}' https://127.0.0.1:8443/favicon.ico)"
echo "TOUCH=$(curl -sk -o /dev/null -w '%{http_code} %{content_type}' https://127.0.0.1:8443/favicon-303x303.png)"
echo "WORDMARK=$(curl -sk -o /dev/null -w '%{http_code} %{content_type}' https://127.0.0.1:8443/images/reyes-title.png)"
echo "CSSMARK=$(curl -sk https://127.0.0.1:8443/styles/custom.css | grep -c 'Reyes Sitework')"

echo "--- errors ---"
sudo journalctl -u meshcentral -n 12 --no-pager | grep -iE 'error|exception|failed|invalid' | tail -8 || echo "none"
