#!/bin/bash
# Fetch step — bring the new flash.version + images onto the box WITHOUT touching the running app.
set -euo pipefail
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${BIN_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/flash_bootstrap"
FLASH_DIR="${ROOT_DIR}/flash"

cd "${BOOTSTRAP_DIR}"
git pull --ff-only origin master

# Refresh runtime files from the freshly-pulled assets (the compose/launcher may have changed).
cp assets/docker-compose.customer.yml assets/launch.sh assets/Caddyfile "${FLASH_DIR}/"

# Reconcile .env FLASH_VERSION (+ DOCKER_GID) from the new flash.version — never clobbers creds.
bash 02_gen_env.sh

cd "${FLASH_DIR}"
docker compose -f docker-compose.customer.yml pull
