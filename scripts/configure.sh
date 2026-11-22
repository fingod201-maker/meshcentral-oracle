#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOMAIN=""
EMAIL=""
TITLE="My Mesh"
LE_PRODUCTION=false

usage() {
  cat <<'EOF'
Usage: configure.sh --domain <hostname> --email <address> [--title <text>] [--staging|--production]

Writes /opt/meshcentral/meshcentral-data/config.json from the project template.
Staging is the default, matching the guide's first-run advice.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    --email) EMAIL="${2:?--email requires a value}"; shift 2 ;;
    --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
    --staging) LE_PRODUCTION=false; shift ;;
    --production) LE_PRODUCTION=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$DOMAIN" ]] || die "--domain is required."
[[ -n "$EMAIL" ]] || die "--email is required."
require_root
require_cmd node

step "Writing MeshCentral config"

DATA_DIR=/opt/meshcentral/meshcentral-data
CONFIG="$DATA_DIR/config.json"
install -d -o meshcentral -g meshcentral -m 750 "$DATA_DIR"

if [[ -f "$CONFIG" ]]; then
  backup="$CONFIG.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$CONFIG" "$backup"
  chown meshcentral:meshcentral "$backup"
  info "Existing config backed up to $backup"
fi

node "$SCRIPT_DIR/render-config.js" \
  "$PROJECT_ROOT/config/config.json.template" \
  "$CONFIG" \
  "$DOMAIN" \
  "$EMAIL" \
  "$TITLE" \
  "$LE_PRODUCTION"

chown meshcentral:meshcentral "$CONFIG"
chmod 600 "$CONFIG"

info "Config written: $CONFIG"

# The renderer preserves production=true from an existing config, so report the
# effective value rather than the flag that was passed.
effective_production=$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).letsencrypt.production" "$CONFIG")
if [[ "$effective_production" == "true" ]]; then
  warn "Let's Encrypt production mode is active. DNS and ports 80/443 must already work."
else
  info "Let's Encrypt staging mode is active. The browser will warn until you run promote-le.sh."
fi
