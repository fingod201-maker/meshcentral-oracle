#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOMAIN=""
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: promote-le.sh [--domain <hostname>] [--yes]

Switches Let's Encrypt from staging to production and waits for the real
certificate. Run this only after the staging certificate and DNS are working.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    --yes|-y) export ASSUME_YES=1; shift ;;
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
[[ -n "$DOMAIN" ]] || die "Could not determine the domain from $CONFIG. Pass --domain."

step "Promoting Let's Encrypt from staging to production"
cat <<EOF
This requests a real, browser-trusted certificate for $DOMAIN.
Let's Encrypt rate-limits failed production requests. Confirm that:
  - https://$DOMAIN works with the staging certificate (ignore the warning)
  - DNS points at this VM
  - ports 80 and 443 are open in firewalld and the Oracle VCN security list
EOF

confirm "Continue?" || die "Aborted."

systemctl stop meshcentral
trap 'systemctl start meshcentral >/dev/null 2>&1 || true' EXIT

node "$SCRIPT_DIR/patch-config.js" "$CONFIG" --production
chown meshcentral:meshcentral "$CONFIG"

systemctl start meshcentral
trap - EXIT

if ! wait_for_service meshcentral 30; then
  journalctl -u meshcentral -n 100 --no-pager -l || true
  die "MeshCentral failed to restart."
fi

info "Waiting for the production certificate (up to 2 minutes)..."
issued=0
for _ in $(seq 1 24); do
  issuer=$(printf '' | timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)
  if [[ "$issuer" == *"Let's Encrypt"* && "$issuer" != *"STAGING"* && "$issuer" != *"Fake"* ]]; then
    info "Certificate issuer: $issuer"
    issued=1
    break
  fi
  sleep 5
done

if (( issued == 0 )); then
  warn "Production certificate not detected yet."
  journalctl -u meshcentral -n 80 --no-pager -l || true
  die "Check the log above. Common causes: DNS mismatch, port 80 blocked, or a Let's Encrypt rate limit."
fi

if ! curl -fsS -o /dev/null --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/"; then
  warn "HTTPS request failed; check the service and certificate."
fi

info "Production TLS is active. Browse to https://$DOMAIN"
