#!/usr/bin/env bash
# Invoked by terraform_data.deploy. Expects CLOUDFLARE_API_TOKEN in the
# environment, plus the LARAFEED_* variables set by the module.
set -euo pipefail

: "${LARAFEED_SOURCE_DIR:?}"
: "${LARAFEED_WRANGLER_CONFIG:?}"
: "${LARAFEED_SECRETS_FILE:?}"

cd "$LARAFEED_SOURCE_DIR"

# The generated config is the default environment; never pick a named one.
unset CLOUDFLARE_ENV
export CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV=false
export LARAFEED_WRANGLER_CONFIG

if [[ "${LARAFEED_INSTALL_DEPS:-true}" == "true" ]]; then
    bun install --frozen-lockfile
fi

# The Vite plugin writes .wrangler/deploy/config.json, which redirects the
# config-less wrangler commands below to the built artifact.
bun scripts/cloudflare-build.ts
bunx --no-install wrangler deploy --dry-run

bunx --no-install wrangler d1 migrations apply DB --remote --config "$LARAFEED_WRANGLER_CONFIG"

bunx --no-install wrangler deploy --secrets-file "$LARAFEED_SECRETS_FILE"
