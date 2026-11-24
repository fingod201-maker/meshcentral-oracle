#!/bin/bash
#
# mac/build.sh - build, ad-hoc sign, package and verify the Reyes Sitework
#                "Document Helper" installer for macOS.
#
# MUST be run on macOS: it uses pkgbuild, productbuild, codesign, pkgutil and
# spctl. The GitHub Actions workflow .github/workflows/mac-pkg.yml runs it on a
# macos-latest runner. Nothing here can be built on Linux.
#
# Inputs (checked in - do NOT substitute, re-download or rebuild):
#   meshagent          : universal Mach-O MeshCentral agent (x86_64 + arm64)
#   DocumentHelper.msh : the device-group configuration the agent loads
#
# Why the .msh matters (and why this package ships it):
#   This agent carries no embedded server address. At startup it reads
#   "<executable>.msh" from its own directory; without it the agent logs
#   "No MeshCentral settings found, place .msh file with this executable and
#   restart" and never connects. Ship the binary WITHOUT the .msh and the Mac
#   installs cleanly but stays offline. The .msh is therefore a hard requirement.
#
# Why the package does NOT run "meshagent --install":
#   The agent's real install verb is "-install" (there is no "--install"), and
#   its self-installer only copies the .msh when handed the exact literal
#   argument '--copy-msh="1"'. MeshCentral's own macOS package sidesteps both
#   pitfalls entirely: it ships a fixed layout plus launchd units and lets
#   launchd start the agent. This package does the same, so the helper comes up
#   as root before any user logs in and at every boot.
#
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.4.2
ID=com.documentexchange.helper
SVC=com.documentexchange.helper
EXE=DocumentHelper
OUT=DocumentHelper.pkg
COMPONENT=DocumentHelper-component.pkg
BIN=/usr/local/bin/$EXE

# Its own rm: a previous run chowns build/ to root, so a plain rm would fail.
sudo rm -rf build
mkdir -p build/root/usr/local/bin
mkdir -p build/root/Library/LaunchDaemons build/root/Library/LaunchAgents

# --- payload: agent binary + its server configuration, side by side ----------
cp meshagent          "build/root/usr/local/bin/$EXE"
cp DocumentHelper.msh "build/root/usr/local/bin/$EXE.msh"
chmod 755 "build/root/usr/local/bin/$EXE"
chmod 644 "build/root/usr/local/bin/$EXE.msh"

# Ad-hoc sign the payload. arm64 binaries must carry at least an ad-hoc
# signature to execute at all. Replace with a Developer ID signature once a
# certificate exists (see the commented block at the end of this script).
codesign --force -s - "build/root/usr/local/bin/$EXE"

# --- payload: launchd units --------------------------------------------------
# Root LaunchDaemon: this is the "background helper". It runs the agent as root
# at load and at every boot, before login. No arguments (the agent reads its
# .msh from the working directory).
cat > "build/root/Library/LaunchDaemons/$SVC.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$SVC</string>
    <key>ProgramArguments</key>
    <array>
      <string>$BIN</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/usr/local/bin/</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
      <key>Crashed</key>
      <true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
  </dict>
</plist>
PLIST

# GUI LaunchAgent: lets the agent share the console user's audit session so
# remote desktop (screen capture + input) works. Best effort.
cat > "build/root/Library/LaunchAgents/$SVC-launchagent.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$SVC-launchagent</string>
    <key>ProgramArguments</key>
    <array>
      <string>$BIN</string>
      <string>-kvmagent</string>
    </array>
    <key>LimitLoadToSessionType</key>
    <array>
      <string>LoginWindow</string>
      <string>Aqua</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/usr/local/bin/</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
      <key>Crashed</key>
      <true/>
    </dict>
  </dict>
</plist>
PLIST

chmod 644 "build/root/Library/LaunchDaemons/$SVC.plist" \
          "build/root/Library/LaunchAgents/$SVC-launchagent.plist"

chmod +x scripts/preinstall scripts/postinstall

# Payload files must install owned by root:wheel.
sudo chown -R root:wheel build/root

# --- build the component package, then the distribution package --------------
cd build
pkgbuild --root root --scripts ../scripts \
  --identifier "$ID" --version "$VERSION" \
  --ownership preserve --install-location / "$COMPONENT"

productbuild --distribution ../distribution.xml --resources ../res/ \
  --package-path . "$OUT"
cd ..

# ============================================================================
# Verification - the job fails if any check fails.
# ============================================================================
echo
echo "== verify =="
FAIL=0

# Extract as root: pkgutil records the payload's real uid/gid, and a non-root
# extraction silently drops root:wheel (which would fail check 3 on CI). The
# distribution expansion only needs to be readable, so it stays unprivileged.
sudo rm -rf chk chkdist
sudo pkgutil --expand-full "build/$COMPONENT" chk
pkgutil --expand "build/$OUT" chkdist

# pkgutil spells the payload dir "Payload"; tolerate "payload" too.
PAYLOAD=""
for cand in chk/Payload chk/payload; do
  if [ -d "$cand" ]; then PAYLOAD="$cand"; fi
done

ok()  { echo "  ok   : $1"; }
bad() { echo "  FAIL : $1"; FAIL=1; }

# 1. Payload is a Mach-O universal binary.
if file "$PAYLOAD$BIN" | grep -q universal; then ok "payload is a Mach-O universal binary (x86_64 + arm64)"
else bad "payload is not a universal binary: $(file "$PAYLOAD$BIN")"; fi

# 2. Payload carries an ad-hoc signature.
if codesign -dv --verbose=2 "$PAYLOAD$BIN" 2>&1 | grep -qi 'Signature=adhoc'; then ok "payload carries Signature=adhoc"
else bad "payload is not ad-hoc signed"; fi

# 3. Payload is -rwxr-xr-x and root:wheel.
if [ "$(stat -f %Sp "$PAYLOAD$BIN")" = "-rwxr-xr-x" ]; then ok "payload mode is -rwxr-xr-x"
else bad "payload mode is $(stat -f %Sp "$PAYLOAD$BIN")"; fi
if [ "$(stat -f %Su:%Sg "$PAYLOAD$BIN")" = "root:wheel" ]; then ok "payload is owned by root:wheel"
else bad "payload is owned by $(stat -f %Su:%Sg "$PAYLOAD$BIN")"; fi

# 4. Both scripts are present and executable in the expanded package.
if [ -f chk/Scripts/preinstall ] && [ -x chk/Scripts/preinstall ]; then ok "preinstall present + executable"
else bad "preinstall missing or not executable"; fi
if [ -f chk/Scripts/postinstall ] && [ -x chk/Scripts/postinstall ]; then ok "postinstall present + executable"
else bad "postinstall missing or not executable"; fi

# 5. Distribution contains the title.
if grep -q 'Document Exchange Helper' chkdist/Distribution; then ok "Distribution contains the title 'Document Exchange Helper'"
else bad "Distribution is missing the title"; fi

# 6. The server configuration is shipped and correct. Without this the Mac
#    installs but never connects, so it is asserted here, loudly.
if [ -f "$PAYLOAD$BIN.msh" ]; then ok "server config shipped: ${BIN}.msh"
else bad "server config (${BIN}.msh) is NOT in the payload - the agent would not connect"; fi
if grep -q 'MeshServer=wss://mesh.telcom.stream:443/agent.ashx' "$PAYLOAD$BIN.msh" 2>/dev/null; then ok ".msh points at wss://mesh.telcom.stream:443/agent.ashx"
else bad ".msh does not point at the MeshCentral server"; fi
if grep -q 'MeshID=0x2112FD7D8C08A45F7B646FE30180E13B15F29894B27B2D0A97CC289B54C042A9A44C6EA414502B08EC2AE470D9DB2036' "$PAYLOAD$BIN.msh" 2>/dev/null; then ok ".msh carries the device-group id"
else bad ".msh is missing the device-group id"; fi

# 7. The LaunchDaemon unit is shipped and runs the agent.
if [ -f "$PAYLOAD/Library/LaunchDaemons/$SVC.plist" ]; then ok "LaunchDaemon unit shipped"
else bad "LaunchDaemon unit missing"; fi
if grep -q "$BIN" "$PAYLOAD/Library/LaunchDaemons/$SVC.plist" 2>/dev/null; then ok "LaunchDaemon runs $BIN"
else bad "LaunchDaemon does not run the agent"; fi

# 8. The package is unsigned. This is the hard, environment-independent check:
#    pkgutil reports "no signature" for a package with no Developer ID/Installer
#    signature. Capture first and grep second: with `set -o pipefail`, pkgutil's
#    non-zero exit for an unsigned package would otherwise fail the pipeline
#    even when the match succeeds.
SIG_OUT="$(pkgutil --check-signature "build/$OUT" 2>&1 || true)"
echo "  pkgutil: ${SIG_OUT:-<no output>}"
if echo "$SIG_OUT" | grep -qiE 'no signature|not signed|unsigned'; then ok "package is unsigned (no signature)"
else bad "package unexpectedly carries a signature"; fi

# 8b. spctl rejection is the documented Gatekeeper outcome for an unsigned
#     install, but `spctl` exits non-zero when it rejects (hence `|| true`
#     above). Gatekeeper is also disabled on some CI runners, so only assert
#     rejection where assessments actually run.
SPCTL_OUT="$(spctl -a -vvv -t install "build/$OUT" 2>&1 || true)"
echo "  spctl  : ${SPCTL_OUT:-<no output>}"
SPCTL_STATUS="$(spctl --status 2>&1 || true)"
if echo "$SPCTL_STATUS" | grep -q 'assessments enabled'; then
  if echo "$SPCTL_OUT" | grep -q rejected; then ok "spctl rejects the unsigned package (expected)"
  else bad "spctl did not reject the package, but Gatekeeper is enabled"; fi
else
  ok "spctl not asserted: Gatekeeper assessments are disabled on this runner"
fi

echo
if [ "$FAIL" -ne 0 ]; then
  echo "VERIFY FAILED"
  exit 1
fi

# 9. Print the artifact hash for the release manifest.
shasum -a 256 "build/$OUT"
echo "OK: build/$OUT"

# ---------------------------------------------------------------------------
# Later, once a Developer ID Installer certificate exists, sign and notarize:
#
#   security create-keychain -p "$CI_KEYCHAIN_PW" build.keychain
#   security import cert.p12 -k build.keychain -P "$CERT_PW" -T /usr/bin/productsign
#   productsign --sign "Developer ID Installer: Reyes Sitework (TEAMID)" \
#               "build/$OUT" "build/$OUT.signed"
#   xcrun notarytool submit "build/$OUT.signed" --keychain-profile AC_PASSWORD --wait
#   xcrun stapler staple "build/$OUT.signed"
#
# Then swap "$OUT" for the signed artifact. Do not add this until the
# certificate exists - an unsigned-but-notarizable build is worse than none.
# ---------------------------------------------------------------------------
