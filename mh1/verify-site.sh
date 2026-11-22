#!/bin/bash
echo "stray one : $(sudo grep -c 'Set-Content\|Portal HTML written' /var/www/reyessitework/index.html)"
echo "stray send: $(sudo grep -c 'Set-Content\|Portal HTML written' /var/www/send/index.html)"
echo "phoenix   : $(curl -s https://reyessitework.telcom.stream/ | grep -c Phoenix)"
echo "phone     : $(curl -s https://reyessitework.telcom.stream/ | grep -c '347-762-3016')"
echo "headline  : $(curl -s https://reyessitework.telcom.stream/ | grep -c 'done right')"
echo "footer    : $(curl -s https://send.telcom.stream/ | grep -c '256-bit TLS')"
echo "images    : $(curl -s https://reyessitework.telcom.stream/ | grep -c 'img/')"
echo "--- one-pager tail ---"
curl -s https://reyessitework.telcom.stream/ | tail -4
echo "--- portal tail ---"
curl -s https://send.telcom.stream/ | tail -3
echo "--- nginx errors (last 5) ---"
sudo tail -5 /var/log/nginx/error.log
