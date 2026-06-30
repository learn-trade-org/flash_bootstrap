#!/bin/bash
# [05] Install the nightly auto-updater. Materializes a stable sibling bin/ (never git-pulled, so a
# pull can't rewrite a running script) with the update scripts, and registers a cron job that runs
# bin/00_main.sh at 00:00 UTC. Idempotent: re-running refreshes bin/ and rewrites the cron file.
#
# Run by 00_bootstrap.sh, or standalone.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"          # flash_bootstrap
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"            # parent (sibling of flash + flash_bootstrap)
BIN_DIR="${ROOT_DIR}/bin"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# Fresh Debian droplets ship WITHOUT cron — the /etc/cron.d file below is inert until the daemon
# exists and runs. Install + enable it here so 05 is self-contained (also when re-run standalone).
echo "==> [05] ensuring the cron daemon is installed + running"
if ! dpkg -s cron >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y cron
fi
if command -v systemctl >/dev/null 2>&1; then
  $SUDO systemctl enable --now cron
else
  $SUDO service cron start || true
fi

echo "==> [05] materializing updater scripts into ${BIN_DIR}"
mkdir -p "${BIN_DIR}"
cp "${SCRIPT_DIR}"/update/*.sh "${BIN_DIR}/"
chmod +x "${BIN_DIR}"/*.sh

echo "==> [05] registering cron (00:00 UTC daily)"
$SUDO tee /etc/cron.d/flash_update >/dev/null <<EOF
# FLASH nightly auto-update — pull the new flash.version + images and redeploy.
0 0 * * * root ${BIN_DIR}/00_main.sh >> ${BIN_DIR}/flash_update.log 2>&1
EOF
$SUDO chmod 644 /etc/cron.d/flash_update

echo "==> [05] updater installed → cron 00:00 UTC, logs ${BIN_DIR}/flash_update.log"
