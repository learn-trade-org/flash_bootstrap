#!/bin/bash
# [03] Pull the baked images + bring up the FLASH stack via the runtime
# launcher (flash/launch.sh).
#
# Run by 00_bootstrap.sh (which exports FLASH_DIR), or standalone — when
# standalone, FLASH_DIR defaults to the sibling ../flash. Delegates to
# flash/launch.sh so compose lifecycle has one source of truth (pull + up,
# no build). Uses sudo only when not already root.

set -e

FLASH_DIR="${FLASH_DIR:-$(cd "$(dirname "$0")/../flash" && pwd)}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# Data dirs must be writable by the container user (UID 1000, per image). On a
# root-run droplet the files are root-owned, so:
#   - mongo can't write /data/db
#   - app (UID 1000) can't READ .env (chmod 600, root-owned) → MONGO_* unset
#   - app can't write db/strategy, db/tick, db/instrument
# Only DATA + .env need aligning now — there's no backend/frontend source on
# the box anymore (code is baked into the pulled images).
echo "==> [03] preparing data dirs (mkdir db/* + chown -> 1000:1000)"
mkdir -p "${FLASH_DIR}/db/mongo" "${FLASH_DIR}/db/strategy" "${FLASH_DIR}/db/strategy/.logs" "${FLASH_DIR}/db/tick" "${FLASH_DIR}/db/instrument"
$SUDO chown -R 1000:1000 "${FLASH_DIR}/db"
$SUDO chown 1000:1000 "${FLASH_DIR}/.env"

echo "==> [03] pulling images + starting FLASH via launch.sh"
$SUDO bash "${FLASH_DIR}/launch.sh" start

echo
echo "==> [03] FLASH starting on http://$(hostname -I | awk '{print $1}'):7200"
FLASH_HOSTNAME="$(grep -E '^FLASH_HOSTNAME=' "${FLASH_DIR}/.env" | cut -d= -f2)"
if [ -n "${FLASH_HOSTNAME}" ]; then
  echo "    secure: https://${FLASH_HOSTNAME}/   (cert issues on first request, ~30s)"
fi
ADMIN_PIN="$(grep -E '^ADMIN_PIN=' "${FLASH_DIR}/.env" | cut -d= -f2)"
echo "    login: admin / ${ADMIN_PIN}   (first pull may take a minute)"