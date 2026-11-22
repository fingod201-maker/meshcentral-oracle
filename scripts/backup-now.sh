#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd tar

step "Creating a manual MeshCentral backup"

SRC=/opt/meshcentral/meshcentral-data
[[ -d "$SRC" ]] || die "Data directory not found: $SRC"

DEST=/var/backups/meshcentral
install -d -m 700 "$DEST"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ARCHIVE="$DEST/meshcentral-data-$STAMP.tar.gz"

tar -czf "$ARCHIVE" -C /opt/meshcentral meshcentral-data
chmod 600 "$ARCHIVE"
find "$DEST" -type f -name 'meshcentral-data-*.tar.gz' -mtime +30 -delete

info "Backup: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
warn "Copy this archive off the VM. See README.md for the rclone cron example."
