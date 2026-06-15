#!/bin/bash
# [00] FLASH bootstrap orchestrator — bare droplet -> running FLASH.
#
# Prereq (manual, first time): clone the private flash repo next to this dir.
#   ssh <droplet>
#   git clone <private flash repo>          # gives ./flash   (your git creds)
#   git clone <this flash_bootstrap repo>   # gives ./flash_bootstrap
#   cd flash_bootstrap && ./00_bootstrap.sh
#
# Orchestrates, in order (each step is its own script, standalone-runnable):
#   01_install_host.sh   apt prereqs + docker engine + compose plugin
#   02_gen_env.sh        write flash/.env  (app:7200, mongo:7220, pin 123456)
#   03_compose_up.sh     docker compose up  (prod compose only — no dev :5173)
#
# Idempotent: re-running is safe — docker install skips if present, .env is
# never clobbered, compose up rebuilds in place.

set -e

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

# flash/ is cloned as a sibling of flash_bootstrap/.
FLASH_DIR="$(cd .. && pwd)/flash"
export FLASH_DIR

if [ ! -f "${FLASH_DIR}/docker-compose.yml" ]; then
  echo "ERROR: ${FLASH_DIR}/docker-compose.yml not found." >&2
  echo "       Clone the private flash repo next to flash_bootstrap/ first." >&2
  exit 1
fi

echo "==> FLASH bootstrap (code at ${FLASH_DIR})"

bash "${SCRIPT_DIR}/01_install_host.sh"
bash "${SCRIPT_DIR}/02_gen_env.sh"
bash "${SCRIPT_DIR}/03_compose_up.sh"

echo
echo "==> bootstrap complete."