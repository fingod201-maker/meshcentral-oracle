#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DOMAIN=""
EMAIL=""
SKIP_DNS=0

usage() {
  cat <<'EOF'
Usage: preflight.sh --domain <hostname> --email <address> [--skip-dns]

Checks the target VM before installing MeshCentral:
  - OS version and architecture
  - RAM and free disk space
  - ports 80/443 availability
  - DNS A record and public IPv4 match
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
    --email) EMAIL="${2:?--email requires a value}"; shift 2 ;;
    --skip-dns) SKIP_DNS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$DOMAIN" ]] || die "--domain is required."
[[ -n "$EMAIL" ]] || die "--email is required."

step "Preflight checks"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "OS: ${PRETTY_NAME:-unknown}"
  if [[ "${ID:-}" != "ol" && "${ID:-}" != "oracle" && "${ID_LIKE:-}" != *"rhel"* ]]; then
    warn "This setup targets Oracle Linux / RHEL; detected ${ID:-unknown}."
  fi
else
  warn "Cannot read /etc/os-release."
fi

case "$(uname -m)" in
  x86_64|aarch64) info "Architecture: $(uname -m)" ;;
  *) warn "Unusual architecture: $(uname -m)" ;;
esac

require_cmd systemctl
require_cmd ss

mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if (( mem_mb > 0 && mem_mb < 900 )); then
  warn "Only ${mem_mb} MB RAM detected. The guide's minimum is 1 GB; add swap with scripts/add-swap.sh."
else
  info "Memory: ${mem_mb} MB"
fi

if [[ -d /opt ]]; then
  avail_mb=$(df -Pm /opt | awk 'NR==2 {print $4}')
  if (( avail_mb < 3072 )); then
    die "Only ${avail_mb} MB free on /opt. Need at least 3 GB (5 GB recommended) for MeshCentral."
  elif (( avail_mb < 5120 )); then
    warn "Only ${avail_mb} MB free on /opt; 5 GB or more is recommended."
  else
    info "Disk free on /opt: ${avail_mb} MB"
  fi
fi

if [[ ! "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
  die "Invalid domain: $DOMAIN"
fi
if (( ${#DOMAIN} > 253 )); then
  die "Domain is too long."
fi
if [[ "$DOMAIN" == *example.com* ]]; then
  warn "Domain contains example.com; replace it with your real hostname."
fi
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  die "Invalid email: $EMAIL"
fi

busy_ports=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E ':(80|443)$' || true)
if [[ -n "$busy_ports" ]]; then
  if systemctl is-active --quiet meshcentral 2>/dev/null; then
    info "Ports 80/443 are already in use by the running MeshCentral service (idempotent redeploy)."
  else
    die "Ports 80/443 are already in use: ${busy_ports//$'\n'/, }. Stop the conflicting service."
  fi
else
  info "Ports 80 and 443 are free."
fi

if (( SKIP_DNS )); then
  warn "Skipping DNS check at your request."
else
  require_cmd getent
  resolved=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)
  if [[ -z "$resolved" ]]; then
    die "DNS: $DOMAIN does not resolve to an IPv4 address. Add an A record first, or pass --skip-dns."
  fi
  info "DNS A record(s): $resolved"

  public_ip=""
  if command -v curl >/dev/null 2>&1; then
    public_ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
    if [[ -z "$public_ip" ]]; then
      public_ip=$(curl -4 -fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null || true)
    fi
  fi

  if [[ -n "$public_ip" ]]; then
    if [[ " $resolved " != *" $public_ip "* ]]; then
      die "DNS for $DOMAIN ($resolved) does not include this VM's public IPv4 ($public_ip). Fix DNS or pass --skip-dns."
    fi
    info "DNS matches this VM's public IPv4: $public_ip"
  else
    warn "Could not determine this VM's public IPv4; skipping the DNS-to-VM comparison."
  fi
fi

info "Preflight checks passed."
