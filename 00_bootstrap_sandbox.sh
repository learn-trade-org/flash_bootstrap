#!/bin/bash
# [00-sandbox] FLASH SANDBOX bootstrap — bare droplet -> running sandbox stack.
#
# Tag-based (:sandbox), standalone: no release manifest, no fleet registry, no self-updater.
# The point-in-time broker is in-process inside flash-app; only flash-app + mongo run.
#
# First-run: clone ONLY this repo onto the box, then (replay window + tape via env):
#   GHCR_USER=<u> GHCR_TOKEN=<read:packages PAT> \
#   SANDBOX_DATA_DIR=/opt/sandbox_data/day-wise SANDBOX_DATE=20260701 \
#   SANDBOX_VIRTUAL_START=2026-07-01T09:15:00+05:30 SANDBOX_VIRTUAL_END=2026-07-01T15:30:00+05:30 \
#   SANDBOX_CONTROL_KEY=<secret> ./00_bootstrap_sandbox.sh
#
# Stage the tape (day folders) under SANDBOX_DATA_DIR first, e.g.
#   rsync -av hesham@interserver.yuva.dev:/mnt/data/day-wise/20260701/ /opt/sandbox_data/day-wise/20260701/

set -e

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

FLASH_DIR="$(cd .. && pwd)/flash"
export FLASH_DIR

echo "==> FLASH sandbox bootstrap (runtime dir ${FLASH_DIR})"

mkdir -p "${FLASH_DIR}"
cp "${SCRIPT_DIR}/assets/docker-compose.sandbox.customer.yml" "${FLASH_DIR}/docker-compose.sandbox.customer.yml"
cp "${SCRIPT_DIR}/assets/launch_sandbox.sh" "${FLASH_DIR}/launch_sandbox.sh"
cp "${SCRIPT_DIR}/assets/Caddyfile" "${FLASH_DIR}/Caddyfile"
chmod +x "${FLASH_DIR}/launch_sandbox.sh"
echo "==> [00] generated ${FLASH_DIR} from assets/ (sandbox)"

bash "${SCRIPT_DIR}/01_install_host.sh"
bash "${SCRIPT_DIR}/01b_registry_login.sh"
bash "${SCRIPT_DIR}/02_gen_env_sandbox.sh"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

echo "==> [03] preparing data dirs (chown -> 1000:1000)"
mkdir -p "${FLASH_DIR}/db/mongo" "${FLASH_DIR}/db/strategy" "${FLASH_DIR}/db/strategy/.logs" "${FLASH_DIR}/db/tick" "${FLASH_DIR}/db/instrument"
$SUDO chown -R 1000:1000 "${FLASH_DIR}/db"
$SUDO chown 1000:1000 "${FLASH_DIR}/.env"

echo "==> [03] pulling :sandbox images + starting via launch_sandbox.sh"
$SUDO bash "${FLASH_DIR}/launch_sandbox.sh" start

echo
echo "==> sandbox bootstrap complete — http://$(hostname -I | awk '{print $1}'):$(grep -E '^APP_HOST_PORT=' "${FLASH_DIR}/.env" | cut -d= -f2)/"
