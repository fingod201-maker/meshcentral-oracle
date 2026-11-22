#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

USERNAME=""
EMAIL=""
PASSWORD=""
PASSWORD2=""

usage() {
  cat <<'EOF'
Usage: create-admin.sh [--user <name>] [--email <address>]

Creates the first MeshCentral account and promotes it to site administrator.
This is an optional headless alternative to the guide's browser flow.

The password is prompted for (never put it on the command line). If you set
MC_ADMIN_PASSWORD in the environment, that value is used instead.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:?--user requires a value}"; shift 2 ;;
    --email) EMAIL="${2:?--email requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root
require_cmd node
require_cmd sudo

CONFIG=/opt/meshcentral/meshcentral-data/config.json
[[ -f "$CONFIG" ]] || die "Config not found: $CONFIG"

step "Creating the MeshCentral site administrator (optional guide step 7)"
cat <<'EOF'
This helper produces the same result as creating the first account in the
browser: a site administrator. The password is passed to the MeshCentral CLI,
so it may briefly appear in the process list. Use the browser flow instead if
that is a concern.
EOF

if [[ -z "$USERNAME" ]]; then
  read -r -p "Admin username: " USERNAME
fi
if [[ -z "$EMAIL" ]]; then
  read -r -p "Admin email: " EMAIL
fi

[[ "$USERNAME" =~ ^[A-Za-z0-9._-]{3,64}$ ]] || die "Username must be 3-64 characters: letters, digits, dot, underscore, or dash."
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "Invalid email: $EMAIL"

if [[ -n "${MC_ADMIN_PASSWORD:-}" ]]; then
  PASSWORD="$MC_ADMIN_PASSWORD"
else
  read -r -s -p "Admin password (min 12 chars): " PASSWORD
  printf '\n'
  read -r -s -p "Confirm password: " PASSWORD2
  printf '\n'
  [[ "$PASSWORD" == "$PASSWORD2" ]] || die "Passwords do not match."
fi
(( ${#PASSWORD} >= 12 )) || die "Password must be at least 12 characters."

systemctl stop meshcentral
trap 'systemctl start meshcentral >/dev/null 2>&1 || true' EXIT

sudo -u meshcentral bash -c 'cd /opt/meshcentral && /usr/bin/node node_modules/meshcentral --createaccount "$1" --pass "$2" --email "$3"' _ "$USERNAME" "$PASSWORD" "$EMAIL"
sudo -u meshcentral bash -c 'cd /opt/meshcentral && /usr/bin/node node_modules/meshcentral --adminaccount "$1"' _ "$USERNAME"

systemctl start meshcentral
trap - EXIT

if ! wait_for_service meshcentral 30; then
  journalctl -u meshcentral -n 100 --no-pager -l || true
  die "MeshCentral failed to restart."
fi

info "Administrator '$USERNAME' created."
warn "Log in and enroll 2FA immediately."
