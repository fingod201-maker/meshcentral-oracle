#!/usr/bin/env bash
# Shared helpers for the MeshCentral deployment scripts.

if [[ -t 1 ]]; then
  COLOR_CYAN=$'\033[0;36m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_CYAN=''
  COLOR_RESET=''
fi

log() {
  printf '%s [%-5s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" "$2"
}

info() { log INFO "$*"; }
warn() { log WARN "$*" >&2; }
error() { log ERROR "$*" >&2; }
die() { error "$*"; exit 1; }

step() {
  printf '\n%s==> %s%s\n' "$COLOR_CYAN" "$*" "$COLOR_RESET"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This script must run as root. Use sudo."
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

confirm() {
  local prompt="$1" answer
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "No TTY available; refusing to continue without --yes."
    return 1
  fi
  read -r -p "$prompt [y/N] " answer || true
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

wait_for_service() {
  local unit="${1:-meshcentral}" tries="${2:-30}" i
  for ((i = 1; i <= tries; i++)); do
    if systemctl is-active --quiet "$unit"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_port() {
  local port="$1" tries="${2:-30}" i
  for ((i = 1; i <= tries; i++)); do
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq ":${port}$"; then
      return 0
    fi
    sleep 2
  done
  return 1
}
