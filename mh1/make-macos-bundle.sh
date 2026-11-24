#!/bin/bash
# Bundle a macOS .pkg into a "no typing" installer ZIP.
#
# The ZIP contains a double-clickable `Install DocumentHelper.command` (mode 755)
# that removes the download quarantine and runs `installer -pkg` for the user, so
# they never have to open Terminal or run `chmod +x`.
#
# The executable bit is preserved because `zip` records Unix modes in the archive
# and macOS Archive Utility restores them on extract.
#
# usage: make-macos-bundle.sh <DocumentHelper.pkg> <DocumentHelper-macOS.zip>
set -e
PKG="${1:?usage: make-macos-bundle.sh <pkg> <out.zip>}"
OUT="${2:?usage: make-macos-bundle.sh <pkg> <out.zip>}"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp "$PKG" "$WORK/DocumentHelper.pkg"

cat > "$WORK/Install DocumentHelper.command" <<'CMD'
#!/bin/bash
# Reyes Sitework — Document Helper installer for macOS
# Just double-click this file. No Terminal typing needed.
set -e
cd "$(dirname "$0")"

echo "=============================================="
echo "  Reyes Sitework — Document Helper installer"
echo "=============================================="
echo

if [ ! -f "./DocumentHelper.pkg" ]; then
  echo "ERROR: DocumentHelper.pkg is missing."
  echo "Keep this file in the same folder as DocumentHelper.pkg."
  echo
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

echo "Preparing the package (clearing download quarantine)..."
/usr/bin/xattr -dr com.apple.quarantine "./DocumentHelper.pkg" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.quarantine "$0" 2>/dev/null || true

echo "Installing — macOS will ask for your password."
echo
sudo /usr/sbin/installer -pkg "./DocumentHelper.pkg" -target /

echo
echo "Done. Document Helper is installed and will start automatically."
echo
read -n 1 -s -r -p "Press any key to close..."
CMD

cp "$WORK/Install DocumentHelper.command" "$WORK/DocumentHelper.sh"

cat > "$WORK/How to install.txt" <<'TXT'
Reyes Sitework — Document Helper (macOS)
========================================

Install (no typing needed):
  1. Double-click  "Install DocumentHelper.command"
     - If macOS asks whether to open it, click "Open".
  2. Enter your Mac password when asked (needed to install).
  3. Done — the helper installs and starts automatically.

If double-clicking does nothing:
  - Right-click "Install DocumentHelper.command" -> Open -> Open.
  - Or open Terminal, drag "DocumentHelper.sh" into the window, press Return.

What's in this folder:
  - Install DocumentHelper.command : double-click this one
  - DocumentHelper.sh              : same installer, for Terminal users
  - DocumentHelper.pkg             : the actual package (used automatically)

Questions? Marcus — marcus@telcom.stream
TXT

chmod 755 "$WORK/Install DocumentHelper.command" "$WORK/DocumentHelper.sh"
chmod 644 "$WORK/DocumentHelper.pkg" "$WORK/How to install.txt"

rm -f "$OUT"
( cd "$WORK" && zip -q "$OUT" \
    "Install DocumentHelper.command" \
    "DocumentHelper.sh" \
    "DocumentHelper.pkg" \
    "How to install.txt" )

echo "built: $OUT"
echo "--- archive contents (mode / size / name) ---"
unzip -Z -1 "$OUT" >/dev/null 2>&1 || true
unzip -Zl "$OUT" || true
