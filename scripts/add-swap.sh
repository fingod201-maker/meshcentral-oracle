#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root

step "Adding 2 GB swap (optional, for 1 GB Oracle instances)"

if swapon --show | grep -q .; then
  info "Swap is already enabled:"
  swapon --show
  exit 0
fi

SWAPFILE=/swapfile
if [[ -e "$SWAPFILE" ]]; then
  die "$SWAPFILE already exists but swap is not active. Inspect it before continuing."
fi

fallocate -l 2G "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=2048 status=progress
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"

if ! grep -q '^/swapfile ' /etc/fstab; then
  printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
fi

sysctl -w vm.swappiness=10 >/dev/null
if [[ -d /etc/sysctl.d ]]; then
  printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-meshcentral-swap.conf
fi

info "2 GB swap enabled and persisted."
