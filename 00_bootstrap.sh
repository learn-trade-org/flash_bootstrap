#!/bin/bash
# [00] FLASH bootstrap orchestrator — bare droplet -> running FLASH.
#
# Pull-and-run model: this installer carries NO flash source. It GENERATES a
# sibling flash/ runtime dir from assets/ (compose + launcher), then pulls the
# baked images from GHCR and runs them. The flash engine itself lives only in
# the private images on ghcr.io/learn-trade-org.
#
# First-run (manual): clone ONLY this repo onto the box, then:
#   cd flash_bootstrap && ./00_bootstrap.sh
#
# Orchestrates, in order (each step is its own script, standalone-runnable):
#   01_install_host.sh      apt prereqs + docker engine + compose plugin
#   01b_registry_login.sh   docker login ghcr.io (read token — for private pull)
#   02_gen_env.sh           write flash/.env  (app:7200, mongo:7220, pin from ADMIN_PIN)
#   02b_fleet_register.sh   register in the flashtrade.in fleet registry (one-click only)
#   03_compose_up.sh        pull images + docker compose up (no build)
#   04_server_maintenance.sh  run host tasks (server_maintenance/00_main.sh → e.g. swap)
#
# Bootstrap is provision-once, then walks away — it carries NO update logic.
# The running flash-updater container (part of the pulled stack) owns updates,
# rollback, and versioning from here on; see flash repo's container/updater/.
#
# Idempotent: re-running is safe — docker install skips if present, .env is
# never clobbered, flash/ assets are refreshed, compose up re-pulls in place.

set -e

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

# flash/ is GENERATED as a sibling of flash_bootstrap/ (was: git-cloned source).
FLASH_DIR="$(cd .. && pwd)/flash"
export FLASH_DIR

echo "==> FLASH bootstrap (runtime dir ${FLASH_DIR})"

# One-click deploys export FLASH_PROGRESS_URL + FLASH_CLOUD_ID (cloud-init); manual runs skip silently.
reportProgressStep() {
  if [ -z "${FLASH_PROGRESS_URL:-}" ] || [ -z "${FLASH_CLOUD_ID:-}" ]; then return 0; fi
  curl -s "${FLASH_PROGRESS_URL}?cloudId=${FLASH_CLOUD_ID}&step=$1" >/dev/null 2>&1 || true
}

# Materialize the runtime dir from assets — compose + launcher only, no source.
mkdir -p "${FLASH_DIR}"
cp "${SCRIPT_DIR}/assets/docker-compose.customer.yml" "${FLASH_DIR}/docker-compose.customer.yml"
cp "${SCRIPT_DIR}/assets/launch.sh" "${FLASH_DIR}/launch.sh"
cp "${SCRIPT_DIR}/assets/Caddyfile" "${FLASH_DIR}/Caddyfile"
chmod +x "${FLASH_DIR}/launch.sh"
echo "==> [00] generated ${FLASH_DIR} from assets/"

reportProgressStep DOCKER
bash "${SCRIPT_DIR}/01_install_host.sh"
bash "${SCRIPT_DIR}/01b_registry_login.sh"
bash "${SCRIPT_DIR}/02_gen_env.sh"
bash "${SCRIPT_DIR}/02b_fleet_register.sh"
reportProgressStep PULL
bash "${SCRIPT_DIR}/03_compose_up.sh"
reportProgressStep UP
bash "${SCRIPT_DIR}/04_server_maintenance.sh"

echo
echo "==> bootstrap complete."