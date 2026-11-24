#!/bin/bash
# Build and deploy the Cloudflare Pages bundle for reyessitework.pages.dev.
#
#   export CLOUDFLARE_API_TOKEN=...      # Cloudflare Pages: Edit token
#   export CLOUDFLARE_ACCOUNT_ID=...     # account id
#   ./deploy-cf-pages.sh [bundle-dir]
#
# Requires `wrangler` on PATH (npm i -g wrangler).
set -e
: "${CLOUDFLARE_API_TOKEN:?export CLOUDFLARE_API_TOKEN (Pages: Edit)}"
: "${CLOUDFLARE_ACCOUNT_ID:?export CLOUDFLARE_ACCOUNT_ID}"
PROJECT=${CF_PAGES_PROJECT:-reyessitework}
DIR=${1:-/tmp/pages}
HERE=$(cd "$(dirname "$0")" && pwd)

bash "$HERE/mk-pages-dir.sh" "$DIR"
wrangler pages deploy "$DIR" \
  --project-name="$PROJECT" \
  --branch=main \
  --commit-dirty=true
