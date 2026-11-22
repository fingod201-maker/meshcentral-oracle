#!/bin/bash
set -e

CONFIG=/opt/meshcentral/meshcentral-data/config.json
PLUGIN_DIR=/opt/meshcentral/meshcentral-data/plugins
mkdir -p "$PLUGIN_DIR"

node -e '
const fs = require("fs");
const p = "/opt/meshcentral/meshcentral-data/config.json";
const c = JSON.parse(fs.readFileSync(p, "utf8"));
c.settings = c.settings || {};
c.settings.plugins = { enabled: true };
fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
console.log("Plugins enabled in config");
'

download_repo() {
  local repo="$1" name="$2"
  rm -f "$name.zip"
  if curl -sL "https://github.com/$repo/archive/refs/heads/master.zip" -o "$name.zip" 2>/dev/null && [ -s "$name.zip" ]; then
    return 0
  fi
  rm -f "$name.zip"
  if curl -sL "https://github.com/$repo/archive/refs/heads/main.zip" -o "$name.zip" 2>/dev/null && [ -s "$name.zip" ]; then
    return 0
  fi
  return 1
}

PLUGINS=(
  "ryanblenis/MeshCentral-ScriptTask"
  "ryanblenis/MeshCentral-RoutePlus"
  "ryanblenis/MeshCentral-EventLog"
  "ryanblenis/MeshCentral-FileDistribution"
  "ryanblenis/MeshCentral-RegEdit"
  "v3DJG6GL/MeshCentral-QuickCommands"
)

for repo in "${PLUGINS[@]}"; do
  name=$(echo "$repo" | cut -d'/' -f2)
  echo "=== Downloading $repo ==="
  cd /tmp
  rm -rf "$name" "$name.zip"
  if download_repo "$repo" "$name"; then
    unzip -q "$name.zip" -d /tmp 2>/dev/null
    plugin_src=$(find /tmp -maxdepth 2 -name "config.json" -path "*$name*" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    if [ -n "$plugin_src" ] && [ -f "$plugin_src/config.json" ]; then
      short_name=$(node -e "const c=JSON.parse(require('fs').readFileSync('$plugin_src/config.json','utf8'));console.log(c.shortName || '$name'.toLowerCase())")
      target="$PLUGIN_DIR/$short_name"
      rm -rf "$target"
      cp -r "$plugin_src" "$target"
      chown -R meshcentral:meshcentral "$target"
      echo "Installed: $short_name from $repo"
    else
      echo "WARNING: Could not find config.json for $repo"
    fi
  else
    echo "WARNING: Failed to download $repo"
  fi
  rm -f "$name.zip"
done

echo "=== Installed plugins ==="
ls -la "$PLUGIN_DIR/"

echo "=== Plugin configs ==="
for d in "$PLUGIN_DIR"/*/; do
  if [ -f "$d/config.json" ]; then
    echo "--- $(basename $d) ---"
    node -e "const c=JSON.parse(require('fs').readFileSync('$d/config.json','utf8'));console.log('  name:',c.name,'version:',c.version,'shortName:',c.shortName)"
  fi
done
'@ | Set-Content -Path 'meshcentral-oracle\scripts\enable-plugins.sh' -NoNewline
Write-Host "Script rewritten"