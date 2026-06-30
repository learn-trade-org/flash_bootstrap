#!/bin/bash
# [05] Install the nightly auto-updater. Materializes a stable sibling bin/ (never git-pulled, so a
# pull can't rewrite a running script) with the update scripts, and registers a cron job that runs
# bin/00_main.sh at 00:00 UTC via root's crontab. Idempotent: re-running refreshes bin/ and the line.
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

# Install into root's crontab (visible via `crontab -l`). Non-interactive — piped to `crontab -`,
# so NO editor prompt. Idempotent: drop any prior flash_update line, then append the current one.
echo "==> [05] registering cron (00:00 UTC daily) in root's crontab"
CRON_LINE="0 0 * * * ${BIN_DIR}/00_main.sh >> ${BIN_DIR}/flash_update.log 2>&1 # flash_update"
( $SUDO crontab -l 2>/dev/null | grep -v 'flash_update' ; echo "${CRON_LINE}" ) | $SUDO crontab -

echo "==> [05] updater installed → 'crontab -l' shows the job, logs ${BIN_DIR}/flash_update.log"
