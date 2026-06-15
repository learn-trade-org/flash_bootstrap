#!/bin/bash
# [02] Generate flash/.env for an end-user box.
#
# Run by 00_bootstrap.sh (which exports FLASH_DIR), or standalone — when
# standalone, FLASH_DIR defaults to the sibling ../flash.
#
# One-truth: .env is the single source for mongo creds + ports. We NEVER
# clobber an existing .env — once the random mongo passwords have created the
# DB users, regenerating them would lock the app out of its own data.
# Re-running is a safe no-op.
#
# Mongo passwords are random per box (openssl 16 bytes -> 32 hex). MONGO_HOST
# (`mongo`) + MONGO_PORT (27017) are the compose-internal service address, NOT
# the host-published ports (7200 app / 7220 mongo).

set -e

FLASH_DIR="${FLASH_DIR:-$(cd "$(dirname "$0")/../flash" && pwd)}"
ENV_FILE="${FLASH_DIR}/.env"

if [ -f "${ENV_FILE}" ]; then
  echo "==> [02] ${ENV_FILE} already exists — leaving it untouched."
  exit 0
fi

echo "==> [02] generating ${ENV_FILE}"

cat > "${ENV_FILE}" <<EOF
MONGO_ROOT_USER=flash
MONGO_ROOT_PASS=$(openssl rand -hex 16)
MONGO_PRIMARY_USER=app
MONGO_PRIMARY_PASS=$(openssl rand -hex 16)
MONGO_HOST=mongo
MONGO_PORT=27017
APP_HOST_PORT=7200
MONGO_HOST_PORT=7220
ADMIN_INITIAL_PIN=123456
EOF

chmod 600 "${ENV_FILE}"
echo "==> [02] wrote .env (app:7200  mongo:7220  admin pin:123456)"