#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd systemctl
require_cmd ss

step "Installing systemd service"

install -m 644 "$PROJECT_ROOT/systemd/meshcentral.service" /etc/systemd/system/meshcentral.service
systemctl daemon-reload
systemctl enable meshcentral
systemctl restart meshcentral

if ! wait_for_service meshcentral 30; then
  systemctl status meshcentral --no-pager -l || true
  journalctl -u meshcentral -n 100 --no-pager -l || true
  die "MeshCentral did not become active. See the log above."
fi

if wait_for_port 443 30; then
  info "MeshCentral is listening on port 443."
else
  warn "Service is active but port 443 is not listening yet. Check: journalctl -u meshcentral -f"
fi

systemctl status meshcentral --no-pager -l | sed -n '1,12p' || true
info "Service installed and started."
