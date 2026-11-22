#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: finalize.sh [--yes]

Post-admin hardening, matching steps 8, 10, and 11 of the guide:
  - close open registration (newAccounts: false)
  - require 2FA for every account (force2factor: true)
  - set a 12-character minimum password
  - enable daily auto-backup (24 hours, keep 30 days)

Run this only after the site administrator account exists.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) export ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root
require_cmd node

CONFIG=/opt/meshcentral/meshcentral-data/config.json
[[ -f "$CONFIG" ]] || die "Config not found: $CONFIG"
systemctl is-active --quiet meshcentral || die "MeshCentral is not active. Start it before finalizing."

step "Locking down MeshCentral (guide steps 8, 10, 11)"
cat <<'EOF'
This will:
  - set domains[""].newAccounts = false
  - require 2FA for all accounts (force2factor: true)
  - set a 12-character minimum password
  - enable daily auto-backup (24 hours, keep 30 days)

Make sure you have already created the site administrator account in the browser.
EOF

confirm "Continue?" || die "Aborted."

systemctl stop meshcentral
trap 'systemctl start meshcentral >/dev/null 2>&1 || true' EXIT

node "$SCRIPT_DIR/patch-config.js" "$CONFIG" --harden --auto-backup
chown meshcentral:meshcentral "$CONFIG"
install -d -o meshcentral -g meshcentral -m 700 /opt/meshcentral/meshcentral-backups

systemctl start meshcentral
trap - EXIT

if ! wait_for_service meshcentral 30; then
  journalctl -u meshcentral -n 100 --no-pager -l || true
  die "MeshCentral failed to restart."
fi

info "Registration is closed, 2FA is enforced, and auto-backup is enabled."
warn "The next login will require enrolling a TOTP authenticator or a security key."
info "Auto-backup path: /opt/meshcentral/meshcentral-backups"
