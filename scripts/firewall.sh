#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root

step "Configuring firewalld (Oracle Linux)"
export DEBIAN_FRONTEND=noninteractive

# Oracle Linux uses firewalld, not UFW.
if ! command -v firewall-cmd >/dev/null 2>&1; then
  dnf install -y firewalld
fi

systemctl enable --now firewalld

firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

firewall-cmd --list-all

info "firewalld configured for SSH, HTTP, and HTTPS."
warn "Oracle Cloud also has a VCN security list / NSG. Open TCP 80 and 443 there; firewalld alone is not enough."
