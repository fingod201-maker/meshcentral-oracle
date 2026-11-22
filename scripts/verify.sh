#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOMAIN=""

usage() {
  cat <<'EOF'
Usage: verify.sh [--domain <hostname>]

Prints service, port, firewall, DNS, HTTPS, certificate, and config status.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root
require_cmd node
require_cmd openssl
require_cmd curl
require_cmd timeout

CONFIG=/opt/meshcentral/meshcentral-data/config.json
[[ -f "$CONFIG" ]] || die "Config not found: $CONFIG"

if [[ -z "$DOMAIN" ]]; then
  DOMAIN=$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).settings.cert" "$CONFIG")
fi

step "MeshCentral verification"
fail=0

if systemctl is-active --quiet meshcentral; then
  info "Service: active"
else
  error "Service: inactive"
  fail=1
fi

if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq ':443$'; then
  info "Port 443: listening"
else
  error "Port 443: not listening"
  fail=1
fi

if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq ':80$'; then
  info "Port 80: listening (HTTP redirect / ACME)"
else
  warn "Port 80: not listening"
fi

printf '\n--- firewalld ---\n'
firewall-cmd --list-all 2>/dev/null || true

printf '\n--- Config ---\n'
node - "$CONFIG" <<'NODE'
const fs = require('fs');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const domain = (config.domains && config.domains['']) || {};
console.log(`  cert:                 ${config.settings && config.settings.cert}`);
console.log(`  newAccounts:          ${domain.newAccounts}`);
console.log(`  force2factor:         ${domain.passwordRequirements && domain.passwordRequirements.force2factor}`);
console.log(`  autoBackup:           ${config.settings && config.settings.autoBackup ? 'enabled' : 'disabled'}`);
console.log(`  letsencrypt.production: ${config.letsencrypt && config.letsencrypt.production}`);
NODE

if command -v getent >/dev/null 2>&1; then
  printf '\n--- DNS ---\n'
  getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print "  " $1}' | sort -u || true
fi

printf '\n--- HTTPS (loopback, certificate verification relaxed) ---\n'
code=$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" 2>/dev/null || true)
if [[ "$code" =~ ^(200|302|401)$ ]]; then
  info "HTTPS: HTTP $code"
else
  warn "HTTPS: HTTP ${code:-failed}"
fi

printf '\n--- Certificate ---\n'
cert_info=$(printf '' | timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null || true)
if [[ -n "$cert_info" ]]; then
  printf '%s\n' "$cert_info" | sed 's/^/  /'
else
  warn "Could not read the certificate."
fi

printf '\n--- Recent warnings ---\n'
journalctl -u meshcentral -p warning -n 20 --no-pager -l || true

exit "$fail"
