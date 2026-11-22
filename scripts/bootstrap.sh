#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOMAIN="${DOMAIN:-}"
EMAIL="${LE_EMAIL:-}"
TITLE="${SITE_TITLE:-My Mesh}"
NODE_MAJOR="${NODE_MAJOR:-20}"
LE_PRODUCTION="${LE_PRODUCTION:-false}"
SKIP_DNS=0
SKIP_FIREWALL=0
ADD_SWAP=auto

usage() {
  cat <<'EOF'
Usage: bootstrap.sh --domain <hostname> --email <address> [options]

Runs guide steps 2-6:
  2. install Node.js from NodeSource
  3. create the meshcentral user and npm install meshcentral
  4. write config.json with built-in Let's Encrypt
  5. install and start the systemd service
  6. configure firewalld

Options:
  --title <text>       Browser title (default: My Mesh)
  --node-major <n>     Node major version (default: 20)
  --production         Use Let's Encrypt production immediately
  --staging            Use Let's Encrypt staging (default)
  --skip-dns           Skip the DNS-to-VM check
  --skip-firewall      Do not configure firewalld
  --add-swap           Always add 2 GB swap before installing
  --no-swap            Never add swap automatically
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    --email) EMAIL="${2:?--email requires a value}"; shift 2 ;;
    --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
    --node-major) NODE_MAJOR="${2:?--node-major requires a value}"; shift 2 ;;
    --production) LE_PRODUCTION=true; shift ;;
    --staging) LE_PRODUCTION=false; shift ;;
    --skip-dns) SKIP_DNS=1; shift ;;
    --skip-firewall) SKIP_FIREWALL=1; shift ;;
    --add-swap) ADD_SWAP=yes; shift ;;
    --no-swap) ADD_SWAP=no; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$DOMAIN" ]] || die "--domain is required."
[[ -n "$EMAIL" ]] || die "--email is required."
[[ "$NODE_MAJOR" =~ ^(20|22|24)$ ]] || die "Unsupported Node major version: $NODE_MAJOR (MeshCentral requires Node 20 or newer)"
require_root

step "MeshCentral bootstrap for Oracle Cloud (Oracle Linux)"
info "Domain: $DOMAIN"
info "Email: $EMAIL"
info "Site title: $TITLE"
info "Node major: $NODE_MAJOR"
if [[ "$LE_PRODUCTION" == "true" ]]; then
  info "Let's Encrypt mode requested: production"
else
  info "Let's Encrypt mode requested: staging (an existing production config is preserved)"
fi

preflight_args=(--domain "$DOMAIN" --email "$EMAIL")
if (( SKIP_DNS )); then
  preflight_args+=(--skip-dns)
fi
bash "$SCRIPT_DIR/preflight.sh" "${preflight_args[@]}"

# Oracle Linux ships with SELinux enforcing. MeshCentral needs to bind 80/443
# and write to /opt/meshcentral; set SELinux to permissive to avoid denials.
if command -v getenforce >/dev/null 2>&1; then
  selinux_mode=$(getenforce 2>/dev/null || echo Disabled)
  if [[ "$selinux_mode" == "Enforcing" ]]; then
    warn "SELinux is Enforcing. Setting to Permissive for MeshCentral."
    setenforce 0 || warn "Could not set SELinux to Permissive at runtime."
    if [[ -f /etc/selinux/config ]]; then
      sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
      info "SELinux set to Permissive in /etc/selinux/config (persistent)."
    fi
  else
    info "SELinux mode: $selinux_mode"
  fi
fi

if [[ "$ADD_SWAP" == "yes" ]]; then
  bash "$SCRIPT_DIR/add-swap.sh"
elif [[ "$ADD_SWAP" == "auto" ]]; then
  mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  if (( mem_mb > 0 && mem_mb < 1500 )) && ! swapon --show 2>/dev/null | grep -q .; then
    info "Low memory (${mem_mb} MB) and no swap; adding 2 GB swap before npm install."
    bash "$SCRIPT_DIR/add-swap.sh"
  fi
fi

bash "$SCRIPT_DIR/install-node.sh" --major "$NODE_MAJOR"
bash "$SCRIPT_DIR/install-meshcentral.sh"

configure_args=(--domain "$DOMAIN" --email "$EMAIL" --title "$TITLE")
if [[ "$LE_PRODUCTION" == "true" ]]; then
  configure_args+=(--production)
else
  configure_args+=(--staging)
fi
bash "$SCRIPT_DIR/configure.sh" "${configure_args[@]}"

bash "$SCRIPT_DIR/install-service.sh"

if (( SKIP_FIREWALL )); then
  warn "Skipping firewalld configuration at your request."
else
  bash "$SCRIPT_DIR/firewall.sh"
  info "Restarting MeshCentral so it can retry certificate issuance with the firewall open."
  systemctl restart meshcentral
  wait_for_service meshcentral 30 || warn "MeshCentral did not become active after the firewall restart."
fi

CONFIG=/opt/meshcentral/meshcentral-data/config.json
EFFECTIVE_PRODUCTION=$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).letsencrypt.production" "$CONFIG" 2>/dev/null || echo "$LE_PRODUCTION")
CERT_NOTE=""
if [[ "$EFFECTIVE_PRODUCTION" != "true" ]]; then
  CERT_NOTE=" (accept the staging certificate warning)"
fi

step "Bootstrap complete"
cat <<EOF
MeshCentral is installed and running.

Next steps from the guide:
  1. Open https://$DOMAIN$CERT_NOTE
  2. Create the first account NOW. It becomes the site administrator, and
     anyone who reaches the server before you do can claim that role.
  3. Run: sudo bash $SCRIPT_DIR/finalize.sh --yes
  4. Run: sudo bash $SCRIPT_DIR/promote-le.sh --domain $DOMAIN --yes
  5. Log in, enroll 2FA, then add a device group and agent.

Useful commands:
  sudo systemctl status meshcentral --no-pager
  sudo journalctl -u meshcentral -f
  sudo bash $SCRIPT_DIR/verify.sh --domain $DOMAIN
EOF
