#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd node
require_cmd npm

step "Installing MeshCentral under /opt/meshcentral"

if ! id meshcentral >/dev/null 2>&1; then
  # Oracle Linux (RHEL) uses /sbin/nologin.
  nologin_shell=/sbin/nologin
  [[ -x /usr/sbin/nologin ]] && nologin_shell=/usr/sbin/nologin
  useradd -r -m -d /opt/meshcentral -s "$nologin_shell" meshcentral
  info "Created system user 'meshcentral'."
else
  info "System user 'meshcentral' already exists."
fi

install -d -o meshcentral -g meshcentral -m 755 /opt/meshcentral
cd /opt/meshcentral

if [[ -f /opt/meshcentral/node_modules/meshcentral/meshcentral.js ]]; then
  version=$(node -p "require('/opt/meshcentral/node_modules/meshcentral/package.json').version" 2>/dev/null || echo unknown)
  info "MeshCentral ${version} is already installed; skipping npm install."
else
  info "Running npm install meshcentral (this can take several minutes)."
  npm install meshcentral
fi

chown -R meshcentral:meshcentral /opt/meshcentral

version=$(node -p "require('/opt/meshcentral/node_modules/meshcentral/package.json').version")
info "MeshCentral ${version} installed in /opt/meshcentral."
