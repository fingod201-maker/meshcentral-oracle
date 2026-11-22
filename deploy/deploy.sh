#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  # Strip CRLF so a .env written by Windows editors works under bash.
  ENV_FILE=$(mktemp)
  tr -d '\r' < "$PROJECT_ROOT/.env" > "$ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  rm -f "$ENV_FILE"
fi

ACTION="deploy"
VM_HOST="${VM_HOST:-}"
VM_USER="${VM_USER:-opc}"
KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
DOMAIN="${DOMAIN:-}"
LE_EMAIL="${LE_EMAIL:-}"
SITE_TITLE="${SITE_TITLE:-My Mesh}"
NODE_MAJOR="${NODE_MAJOR:-20}"
LE_PRODUCTION="${LE_PRODUCTION:-false}"
SKIP_DNS=0
SKIP_FIREWALL=0
ASSUME_YES=0
REMOTE_DIR="${REMOTE_DIR:-}"

usage() {
  cat <<'EOF'
Usage: deploy.sh --host <ip-or-host> [options]

Actions:
  --action deploy|finalize|promote|verify|status|logs|backup|create-admin|upgrade

Options:
  --host <host>          Oracle VM public IP or hostname
  --user <name>          SSH user (default: opc)
  --key <path>           SSH private key
  --port <n>             SSH port (default: 22)
  --domain <hostname>    MeshCentral hostname
  --email <address>      Let's Encrypt email
  --title <text>         Browser title (default: My Mesh)
  --node-major <n>       Node major version (default: 20)
  --production           Use Let's Encrypt production immediately
  --staging              Use Let's Encrypt staging (default)
  --skip-dns             Skip the DNS-to-VM check
  --skip-firewall        Do not configure firewalld
  --yes                  Assume yes for confirmations

Values can also come from .env (DOMAIN, LE_EMAIL, VM_HOST, VM_USER, SSH_KEY, etc.).
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[0;36m==> %s\033[0m\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="${2:?--action requires a value}"; shift 2 ;;
    --host) VM_HOST="${2:?--host requires a value}"; shift 2 ;;
    --user) VM_USER="${2:?--user requires a value}"; shift 2 ;;
    --key) KEY="${2:?--key requires a value}"; shift 2 ;;
    --port) SSH_PORT="${2:?--port requires a value}"; shift 2 ;;
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    --email) LE_EMAIL="${2:?--email requires a value}"; shift 2 ;;
    --title) SITE_TITLE="${2:?--title requires a value}"; shift 2 ;;
    --node-major) NODE_MAJOR="${2:?--node-major requires a value}"; shift 2 ;;
    --production) LE_PRODUCTION=true; shift ;;
    --staging) LE_PRODUCTION=false; shift ;;
    --skip-dns) SKIP_DNS=1; shift ;;
    --skip-firewall) SKIP_FIREWALL=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$ACTION" in
  deploy|finalize|promote|verify|status|logs|backup|create-admin|upgrade) ;;
  *) die "Invalid action: $ACTION" ;;
esac

[[ -n "$VM_HOST" ]] || die "--host is required (or set VM_HOST in .env)."
command -v ssh >/dev/null 2>&1 || die "ssh is required."
command -v scp >/dev/null 2>&1 || die "scp is required."

if [[ -n "$KEY" ]]; then
  KEY="${KEY/#\~/$HOME}"
  [[ -f "$KEY" ]] || die "SSH key not found: $KEY"
fi

if [[ -z "$REMOTE_DIR" ]]; then
  if [[ "$VM_USER" == "root" ]]; then
    REMOTE_DIR="/root/meshcentral-oracle"
  else
    REMOTE_DIR="/home/$VM_USER/meshcentral-oracle"
  fi
fi

SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes)
if [[ -n "$KEY" ]]; then
  SSH_OPTS+=(-i "$KEY")
  SCP_OPTS+=(-i "$KEY")
fi

TARGET="$VM_USER@$VM_HOST"
SUDO=""
if [[ "$VM_USER" != "root" ]]; then
  SUDO="sudo "
fi

quote() { printf '%q' "$1"; }

invoke_remote() {
  local command="$1"
  ssh "${SSH_OPTS[@]}" "$TARGET" "$command"
}

invoke_sudo() {
  local command="$1"
  ssh "${SSH_OPTS[@]}" "$TARGET" "${SUDO}${command}"
}

invoke_sudo_tty() {
  local command="$1"
  ssh -t "${SSH_OPTS[@]}" "$TARGET" "${SUDO}${command}"
}

sync_bundle() {
  info "Copying deployment bundle to ${TARGET}:${REMOTE_DIR}"
  invoke_remote "mkdir -p $(quote "$REMOTE_DIR")"
  invoke_remote "rm -rf $(quote "$REMOTE_DIR/config") $(quote "$REMOTE_DIR/scripts") $(quote "$REMOTE_DIR/systemd")"
  scp "${SCP_OPTS[@]}" -r \
    "$PROJECT_ROOT/config" \
    "$PROJECT_ROOT/scripts" \
    "$PROJECT_ROOT/systemd" \
    "$TARGET:$REMOTE_DIR/"
  invoke_remote "chmod +x $(quote "$REMOTE_DIR/scripts")/*.sh"
}

info "Testing SSH connection to $TARGET"
ssh "${SSH_OPTS[@]}" "$TARGET" 'echo ok' >/dev/null

if [[ "$VM_USER" != "root" ]]; then
  if ! ssh "${SSH_OPTS[@]}" "$TARGET" 'sudo -n true' >/dev/null 2>&1; then
    die "Passwordless sudo is required for '$VM_USER'. Configure NOPASSWD or use --user root."
  fi
fi

case "$ACTION" in
  deploy)
    [[ -n "$DOMAIN" ]] || die "--domain is required for deploy (or set DOMAIN in .env)."
    [[ -n "$LE_EMAIL" ]] || die "--email is required for deploy (or set LE_EMAIL in .env)."

    sync_bundle
    cmd="bash $(quote "$REMOTE_DIR/scripts/bootstrap.sh") --domain $(quote "$DOMAIN") --email $(quote "$LE_EMAIL") --title $(quote "$SITE_TITLE") --node-major $NODE_MAJOR"
    if [[ "$LE_PRODUCTION" == "true" ]]; then
      cmd+=" --production"
    else
      cmd+=" --staging"
    fi
    if (( SKIP_DNS )); then cmd+=" --skip-dns"; fi
    if (( SKIP_FIREWALL )); then cmd+=" --skip-firewall"; fi
    invoke_sudo "$cmd"

    cat <<EOF

Bootstrap complete.
  1. Open https://$DOMAIN and create the first account (site administrator).
  2. Run: ./deploy/deploy.sh --action finalize --host $VM_HOST --domain $DOMAIN --yes
  3. Run: ./deploy/deploy.sh --action promote  --host $VM_HOST --domain $DOMAIN --yes
  4. Log in, enroll 2FA, then add a device group and agent.
EOF
    ;;

  finalize)
    sync_bundle
    cmd="bash $(quote "$REMOTE_DIR/scripts/finalize.sh")"
    if (( ASSUME_YES )); then cmd+=" --yes"; fi
    invoke_sudo "$cmd"
    ;;

  promote)
    sync_bundle
    cmd="bash $(quote "$REMOTE_DIR/scripts/promote-le.sh")"
    if [[ -n "$DOMAIN" ]]; then cmd+=" --domain $(quote "$DOMAIN")"; fi
    if (( ASSUME_YES )); then cmd+=" --yes"; fi
    invoke_sudo "$cmd"
    ;;

  verify)
    sync_bundle
    cmd="bash $(quote "$REMOTE_DIR/scripts/verify.sh")"
    if [[ -n "$DOMAIN" ]]; then cmd+=" --domain $(quote "$DOMAIN")"; fi
    invoke_sudo "$cmd"
    ;;

  status)
    invoke_remote 'systemctl status meshcentral --no-pager -l || true'
    printf '\n'
    invoke_remote "ss -ltnp | grep -E ':(80|443)$' || true"
    printf '\n'
    invoke_sudo 'firewall-cmd --list-all || true'
    ;;

  logs)
    invoke_sudo 'journalctl -u meshcentral -n 200 --no-pager -l'
    ;;

  backup)
    sync_bundle
    invoke_sudo "bash $(quote "$REMOTE_DIR/scripts/backup-now.sh")"
    ;;

  create-admin)
    sync_bundle
    invoke_sudo_tty "bash $(quote "$REMOTE_DIR/scripts/create-admin.sh")"
    ;;

  upgrade)
    sync_bundle
    invoke_sudo "bash $(quote "$REMOTE_DIR/scripts/upgrade.sh")"
    ;;
esac
