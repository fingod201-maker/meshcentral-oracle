#!/bin/bash
# Verify MeshCentral reverse-proxy enrollment health (run on the VM as opc).
set -e

echo "=== SERVICES ==="
systemctl is-active meshcentral nginx

echo "=== STARTUP LOG (relevant lines) ==="
journalctl -u meshcentral -n 120 --no-pager \
  | grep -iE 'running on|web certificate|SHA384|cert hash|Loaded|error|exception' \
  | tail -n 30 || true

echo "=== PUBLIC WS 443 ==="
curl -sk --http1.1 --max-time 8 -D - -o /dev/null https://127.0.0.1:443/agent.ashx \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Protocol: meshcentral" || true

echo "=== BAD HASH COUNT (last 200 lines) ==="
journalctl -u meshcentral -n 200 --no-pager | grep -c 'Agent bad web cert hash' || true

echo "=== CONFIG SNAPSHOT ==="
sudo -n grep -E '"(port|aliasPort|redirPort|certUrl|newAccounts)"' /opt/meshcentral/meshcentral-data/config.json || true
