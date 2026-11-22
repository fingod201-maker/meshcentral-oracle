#!/bin/bash
set -e

sudo mkdir -p /var/www/reyessitework/img
sudo cp /tmp/rey-index.html /var/www/reyessitework/index.html
sudo cp /tmp/reyimg/*.jpg /var/www/reyessitework/img/
sudo cp /tmp/portal.html /var/www/send/index.html

sudo chown -R nginx:nginx /var/www/reyessitework
sudo chown nginx:nginx /var/www/send/index.html
sudo chmod 755 /var/www/reyessitework /var/www/reyessitework/img
sudo chmod 644 /var/www/reyessitework/index.html /var/www/reyessitework/img/*.jpg /var/www/send/index.html
sudo restorecon -Rv /var/www/reyessitework /var/www/send/index.html >/dev/null

echo "=== stray heredoc text (must be 0) ==="
grep -c "Set-Content\|Portal HTML written" /var/www/reyessitework/index.html || true
grep -c "Set-Content\|Portal HTML written" /var/www/send/index.html || true

echo "=== files ==="
ls -la /var/www/reyessitework /var/www/reyessitework/img

echo "=== local fetch ==="
curl -s -o /dev/null -w "one-pager %{http_code}\n" https://reyessitework.telcom.stream/
curl -s -o /dev/null -w "portal    %{http_code}\n" https://send.telcom.stream/
for f in hero patio-stamped driveway-pour driveway-finished rebar-prep driveway-finish marcus; do
  curl -s -o /dev/null -w "$f %{http_code} %{content_type}\n" "https://reyessitework.telcom.stream/img/$f.jpg"
done

echo "=== copy checks ==="
curl -s https://reyessitework.telcom.stream/ | grep -c "Concrete flatwork, done right"
curl -s https://reyessitework.telcom.stream/ | grep -c "347-762-3016"
curl -s https://send.telcom.stream/ | grep -c "256-bit TLS"
