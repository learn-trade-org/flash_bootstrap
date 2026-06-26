#!/bin/bash
# Apply step — recreate only the containers whose image changed (a no-op on a quiet night).
set -euo pipefail
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${BIN_DIR}/.." && pwd)"
FLASH_DIR="${ROOT_DIR}/flash"
BOOTSTRAP_DIR="${ROOT_DIR}/flash_bootstrap"

cd "${FLASH_DIR}"
docker compose -f docker-compose.customer.yml up -d
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | flash-update | redeployed FLASH_VERSION=$(grep -E '^FLASH_VERSION=' .env | cut -d= -f2)"

# Self-refresh the updater scripts for the NEXT run — last action, so overwriting bin/ is safe now.
cp "${BOOTSTRAP_DIR}"/update/*.sh "${BIN_DIR}/"
