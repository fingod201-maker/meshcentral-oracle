#!/bin/bash
# Bundle a macOS .pkg into a "no-typing, no-chmod" installer ZIP.
#
# The ZIP contains an installer script in two forms (identical content, both
# mode 755):
#   * Install DocumentHelper.command  -> double-clickable in Finder
#   * DocumentHelper.sh               -> for Terminal users
#
# Neither ever needs `chmod +x`:
#   - `zip` records Unix modes and macOS Archive Utility restores them on extract,
#     so the extracted files are already executable; and
#   - even if a tool strips the executable bit, running it as `sh DocumentHelper.sh`
#     works without the bit at all.
#
# The script locates DocumentHelper.pkg next to itself, clears the download
# quarantine, and runs `installer -pkg` (which is what installs the agent and
# enrols the Mac) through the normal macOS password prompt.
#
# usage: make-macos-bundle.sh <DocumentHelper.pkg> <DocumentHelper-macOS.zip>
set -e
PKG="${1:?usage: make-macos-bundle.sh <pkg> <out.zip>}"
OUT="${2:?usage: make-macos-bundle.sh <pkg> <out.zip>}"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp "$PKG" "$WORK/DocumentHelper.pkg"

# One installer script, written once and copied to both names.
cat > "$WORK/DocumentHelper.sh" <<'SH'
#!/bin/bash
# Reyes Sitework - Document Helper installer for macOS
#
# Run it either way (no chmod needed):
#   * double-click "Install DocumentHelper.command", or
#   * in Terminal:   sh DocumentHelper.sh
set -u

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
PKG="$HERE/DocumentHelper.pkg"

printf '\n==============================================\n'
printf '   Reyes Sitework - Document Helper installer\n'
printf '==============================================\n\n'

if [ ! -f "$PKG" ]; then
  printf 'ERROR: DocumentHelper.pkg was not found next to this installer.\n'
  printf 'Keep "DocumentHelper.sh" and "DocumentHelper.pkg" in the same folder.\n\n'
  [ -t 0 ] && read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

printf 'Preparing the package (clearing the download quarantine)...\n'
/usr/bin/xattr -dr com.apple.quarantine "$PKG" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.quarantine "$0"   2>/dev/null || true

printf 'Installing - macOS will ask for your password.\n\n'
if sudo /usr/sbin/installer -pkg "$PKG" -target /; then
  printf '\nDone. Document Helper is installed and will start automatically.\n\n'
  [ -t 0 ] && read -n 1 -s -r -p "Press any key to close..."
  exit 0
else
  printf '\nThe installation did not complete.\n'
  printf 'Try: right-click "DocumentHelper.pkg", choose Open, then follow the prompts.\n\n'
  [ -t 0 ] && read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi
SH

# Same script, double-clickable name.
cp "$WORK/DocumentHelper.sh" "$WORK/Install DocumentHelper.command"

cat > "$WORK/How to install.txt" <<'TXT'
Reyes Sitework - Document Helper (macOS)
========================================

Install it - pick whichever is easiest. No "chmod", no typing a path.

  EASIEST - double-click
    "Install DocumentHelper.command"
      - If macOS asks whether to open it, click "Open".
      - Enter your Mac password when asked.

  TERMINAL - also no chmod needed
    Open Terminal, type   sh   (then a space), drag "DocumentHelper.sh" from
    this folder into the Terminal window, and press Return.
    Running a script with "sh" always works, even if the download cleared the
    file's executable bit.

What's in this folder:
  - Install DocumentHelper.command : double-click this one
  - DocumentHelper.sh              : the same installer, for Terminal users
  - DocumentHelper.pkg             : the actual package (used automatically)

Questions? Marcus - marcus@telcom.stream
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
unzip -Zl "$OUT" || true
