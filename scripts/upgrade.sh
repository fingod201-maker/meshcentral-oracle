#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd node
require_cmd npm

step "Upgrading MeshCentral"
bash "$SCRIPT_DIR/backup-now.sh"

systemctl stop meshcentral
trap 'systemctl start meshcentral >/dev/null 2>&1 || true' EXIT

cd /opt/meshcentral
npm install meshcentral@latest
chown -R meshcentral:meshcentral /opt/meshcentral

systemctl start meshcentral
trap - EXIT

if ! wait_for_service meshcentral 30; then
  journalctl -u meshcentral -n 100 --no-pager -l || true
  die "MeshCentral failed to restart after the upgrade."
fi

version=$(node -p "require('/opt/meshcentral/node_modules/meshcentral/package.json').version")
info "MeshCentral upgraded to ${version}."
