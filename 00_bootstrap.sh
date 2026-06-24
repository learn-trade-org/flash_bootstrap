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
#   02_gen_env.sh           write flash/.env  (app:7200, mongo:7220, pin 123456)
#   03_compose_up.sh        pull images + docker compose up (no build)
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

# Materialize the runtime dir from assets — compose + launcher only, no source.
mkdir -p "${FLASH_DIR}"
cp "${SCRIPT_DIR}/assets/docker-compose.customer.yml" "${FLASH_DIR}/docker-compose.customer.yml"
cp "${SCRIPT_DIR}/assets/launch.sh" "${FLASH_DIR}/launch.sh"
chmod +x "${FLASH_DIR}/launch.sh"
echo "==> [00] generated ${FLASH_DIR} from assets/"

bash "${SCRIPT_DIR}/01_install_host.sh"
bash "${SCRIPT_DIR}/01b_registry_login.sh"
bash "${SCRIPT_DIR}/02_gen_env.sh"
bash "${SCRIPT_DIR}/03_compose_up.sh"

echo
echo "==> bootstrap complete."