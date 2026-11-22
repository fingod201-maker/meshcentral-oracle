#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NODE_MAJOR="${NODE_MAJOR:-20}"

usage() {
  cat <<'EOF'
Usage: install-node.sh [--major 20|22|24]

Installs Node.js from NodeSource. The guide uses Node 20.
Oracle Linux (RHEL-based) uses the RPM repository.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --major) NODE_MAJOR="${2:?--major requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ "$NODE_MAJOR" =~ ^(20|22|24)$ ]] || die "Unsupported Node major version: $NODE_MAJOR (MeshCentral requires Node 20 or newer)"
require_root

step "Installing Node.js ${NODE_MAJOR}.x from NodeSource (RPM)"
export DEBIAN_FRONTEND=noninteractive

# Oracle Linux is RHEL-based: use dnf and the RPM repository.
dnf install -y ca-certificates curl

if command -v node >/dev/null 2>&1; then
  current_major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
  if [[ "$current_major" == "$NODE_MAJOR" ]] && command -v npm >/dev/null 2>&1; then
    info "Node.js $(node --version) is already installed."
    info "npm $(npm --version)"
    exit 0
  fi
  warn "Node.js $(node --version) is installed; installing ${NODE_MAJOR}.x."
fi

curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
dnf install -y nodejs

hash -r
node --version
npm --version
info "Node.js installation complete."
