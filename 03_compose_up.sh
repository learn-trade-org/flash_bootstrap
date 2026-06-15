#!/bin/bash
# [03] Bring up the FLASH stack via flash's prod launcher (launch.sh).
#
# Run by 00_bootstrap.sh (which exports FLASH_DIR), or standalone — when
# standalone, FLASH_DIR defaults to the sibling ../flash. Delegates to
# flash/launch.sh so compose lifecycle has one source of truth (prod compose
# only — no dev :5173). Uses sudo only when not already root.

set -e

FLASH_DIR="${FLASH_DIR:-$(cd "$(dirname "$0")/../flash" && pwd)}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# Bind mounts must be writable by the container user (UID 1000, per Dockerfile).
# On a root-cloned droplet the files are root-owned, so the container can't
# create node_modules (app) or write /data/db (mongo). Create the mongo data
# dir and align ownership of the WRITABLE mounts only — .git is left untouched
# to avoid git "dubious ownership" on later root-run pulls.
echo "==> [03] preparing bind-mount dirs (mkdir db/mongo + chown -> 1000:1000)"
mkdir -p "${FLASH_DIR}/db/mongo"
$SUDO chown -R 1000:1000 "${FLASH_DIR}/backend" "${FLASH_DIR}/frontend" "${FLASH_DIR}/db"

echo "==> [03] starting FLASH via launch.sh"
$SUDO bash "${FLASH_DIR}/launch.sh" start

echo
echo "==> [03] FLASH starting on http://$(hostname -I | awk '{print $1}'):7200"
echo "    login: admin / 123456   (first boot builds the bundle — give it ~1 min)"