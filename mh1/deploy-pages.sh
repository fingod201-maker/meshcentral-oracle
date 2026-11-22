#!/bin/bash
set -e
sudo install -m 644 -o opc -g opc /tmp/index.new.html /var/www/reyessitework/index.html
sudo install -m 644 -o opc -g opc /tmp/portal.new.html /var/www/send/index.html
echo "--- perms ---"
ls -l /var/www/reyessitework/index.html /var/www/send/index.html
echo "--- checks ---"
echo "mobileHero=$(grep -c 'linear-gradient(180deg,rgba(7,14,19,.42)' /var/www/reyessitework/index.html)"
echo "portalShared=$(grep -c 'id=\"shared\"' /var/www/send/index.html)"
echo "portalReady=$(grep -c 'id=\"ready\"' /var/www/send/index.html)"
echo "portalTo=$(grep -c "Folder for '+to" /var/www/send/index.html)"
echo "strayHeredoc=$(grep -c 'Set-Content' /var/www/reyessitework/index.html /var/www/send/index.html || true)"
echo "footerSite=$(grep -c '256-bit TLS' /var/www/reyessitework/index.html)"
echo "footerSend=$(grep -c '256-bit TLS' /var/www/send/index.html)"
