#!/bin/bash
# [02-sandbox] Generate flash/.env for a SANDBOX box. Tag-based (:sandbox) — no release manifest,
# no image digests. The replay window + tape dir come from the operator via env vars.
#
# Required env: SANDBOX_DATA_DIR SANDBOX_DATE SANDBOX_VIRTUAL_START SANDBOX_VIRTUAL_END
# Optional env: SANDBOX_CONTROL_KEY SANDBOX_DATA_MODE(=tick) ADMIN_PIN APP_HOST_PORT(=7200) MONGO_HOST_PORT(=7220)
#
# Never clobbers an existing .env (random mongo passwords already created the DB users).

set -e

FLASH_DIR="${FLASH_DIR:-$(cd "$(dirname "$0")/../flash" && pwd)}"
ENV_FILE="${FLASH_DIR}/.env"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "==> [02-sandbox] ERROR: ${name} is required" >&2
    exit 1
  fi
}
require_env SANDBOX_DATA_DIR
require_env SANDBOX_DATE
require_env SANDBOX_VIRTUAL_START
require_env SANDBOX_VIRTUAL_END

if ! echo "${SANDBOX_DATE}" | grep -qE '^[0-9]{8}$'; then
  echo "==> [02-sandbox] ERROR: SANDBOX_DATE must be YYYYMMDD, got: ${SANDBOX_DATE}" >&2
  exit 1
fi

DOCKER_GID="$(getent group docker | cut -d: -f3)"
DOCKER_GID="${DOCKER_GID:-999}"

# FLASH_HOSTNAME = public IPv4 in dashed form via nip.io (Caddy auto-issues a LE cert for it).
detect_public_ip() {
  local ip
  ip="$(curl -s --max-time 3 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null)"
  if [ -z "${ip}" ]; then ip="$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)"; fi
  echo "${ip}"
}
PUBLIC_IP="$(detect_public_ip)"
FLASH_HOSTNAME=""
if [ -n "${PUBLIC_IP}" ]; then FLASH_HOSTNAME="${PUBLIC_IP//./-}.nip.io"; fi

env_set() {
  local keyName="$1"
  local keyValue="$2"
  if grep -q "^${keyName}=" "${ENV_FILE}"; then
    sed -i.bak "s|^${keyName}=.*|${keyName}=${keyValue}|" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
  else
    echo "${keyName}=${keyValue}" >> "${ENV_FILE}"
  fi
}

# The replay config + host-derived gid are reconciled every run; mongo creds are written once.
write_sandbox_config() {
  env_set "DOCKER_GID"            "${DOCKER_GID}"
  if [ -n "${FLASH_HOSTNAME}" ]; then env_set "FLASH_HOSTNAME" "${FLASH_HOSTNAME}"; fi
  env_set "SANDBOX_DATA_DIR"      "${SANDBOX_DATA_DIR}"
  env_set "SANDBOX_DATA_MODE"     "${SANDBOX_DATA_MODE:-tick}"
  env_set "SANDBOX_DATE"          "${SANDBOX_DATE}"
  env_set "SANDBOX_VIRTUAL_START" "${SANDBOX_VIRTUAL_START}"
  env_set "SANDBOX_VIRTUAL_END"   "${SANDBOX_VIRTUAL_END}"
  env_set "SANDBOX_CONTROL_KEY"   "${SANDBOX_CONTROL_KEY:-}"
}

if [ -f "${ENV_FILE}" ]; then
  echo "==> [02-sandbox] ${ENV_FILE} exists — leaving creds untouched, reconciling sandbox config"
  write_sandbox_config
  exit 0
fi

echo "==> [02-sandbox] generating ${ENV_FILE}"
cat > "${ENV_FILE}" <<EOF
MONGO_ROOT_USER=flash
MONGO_ROOT_PASS=$(openssl rand -hex 16)
MONGO_PRIMARY_USER=app
MONGO_PRIMARY_PASS=$(openssl rand -hex 16)
MONGO_HOST=mongo
MONGO_PORT=27017
APP_HOST_PORT=${APP_HOST_PORT:-7200}
MONGO_HOST_PORT=${MONGO_HOST_PORT:-7220}
ADMIN_PIN=${ADMIN_PIN:-123456}
DOCKER_GID=${DOCKER_GID}
FLASH_HOSTNAME=${FLASH_HOSTNAME}
SANDBOX_DATA_DIR=${SANDBOX_DATA_DIR}
SANDBOX_DATA_MODE=${SANDBOX_DATA_MODE:-tick}
SANDBOX_DATE=${SANDBOX_DATE}
SANDBOX_VIRTUAL_START=${SANDBOX_VIRTUAL_START}
SANDBOX_VIRTUAL_END=${SANDBOX_VIRTUAL_END}
SANDBOX_CONTROL_KEY=${SANDBOX_CONTROL_KEY:-}
EOF

chmod 600 "${ENV_FILE}"
echo "==> [02-sandbox] wrote .env (app:${APP_HOST_PORT:-7200}  mongo:${MONGO_HOST_PORT:-7220}  tape:${SANDBOX_DATA_DIR}  window:${SANDBOX_VIRTUAL_START}..${SANDBOX_VIRTUAL_END})"
