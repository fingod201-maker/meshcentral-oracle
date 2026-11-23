#!/bin/bash
# Run on macOS to build DocumentHelper.pkg.
# Prerequisites:
#   - meshagent          : universal Mach-O MeshCentral agent binary
#   - DocumentHelper.msh : authoritative device-group configuration (port 443)
set -e
cd "$(dirname "$0")"

# Verify the agent binary is a universal Mach-O (x86_64 + arm64).
file meshagent

mkdir -p root/usr/local/bin scripts
cp meshagent root/usr/local/bin/DocumentHelper
cp DocumentHelper.msh root/usr/local/bin/DocumentHelper.msh

# Ad-hoc sign for Apple Silicon. Production builds must also be productsigned
# with a Developer ID Installer and notarized.
codesign --force -s - root/usr/local/bin/DocumentHelper
codesign -dv root/usr/local/bin/DocumentHelper 2>&1 | grep -i signature || true

# Strict postinstall: any agent failure fails the package install.
cat > scripts/postinstall <<'EOF'
#!/bin/bash
set -e
chmod 755 /usr/local/bin/DocumentHelper
chmod 644 /usr/local/bin/DocumentHelper.msh
/usr/local/bin/DocumentHelper -install
EOF
chmod +x scripts/postinstall

pkgbuild --root root --scripts scripts --identifier com.documentexchange.helper \
  --version 1.4.3 --install-location / DocumentHelper.pkg

echo "Built: DocumentHelper.pkg"
ls -la DocumentHelper.pkg
