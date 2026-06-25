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

# DOCKER_GID — the gid of the host's `docker` group. compose `group_add` reads
# ${DOCKER_GID} so flash_app (uid 1000) can reach /var/run/docker.sock to run
# strategy containers. AUTO-DETECTED from the host (it varies per box — e.g. 989
# vs 999 depending on install order); falls back to 999 if the group is absent.
# A wrong gid → app can't read the socket → strategy deploy fails with
# `container_engine_fault` ("typo in the url or port?").
DOCKER_GID="$(getent group docker | cut -d: -f3)"
DOCKER_GID="${DOCKER_GID:-999}"

# FLASH_VERSION — the image tag the customer compose pulls. Pinned in the
# flash_bootstrap/flash.version file (owner bumps it per ship); falls back to
# `latest`. docker compose reads ${FLASH_VERSION} from this .env automatically.
FLASH_VERSION="$(cat "$(dirname "$0")/flash.version" 2>/dev/null | tr -d '[:space:]')"
FLASH_VERSION="${FLASH_VERSION:-latest}"

if [ -f "${ENV_FILE}" ]; then
  echo "==> [02] ${ENV_FILE} already exists — leaving creds untouched."
  # DOCKER_GID is host-derived, not a cred — reconcile it to the detected value
  # on every run (a stale/wrong gid breaks strategy-container deploys).
  if grep -q '^DOCKER_GID=' "${ENV_FILE}"; then
    sed -i.bak "s/^DOCKER_GID=.*/DOCKER_GID=${DOCKER_GID}/" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
  else
    echo "DOCKER_GID=${DOCKER_GID}" >> "${ENV_FILE}"
  fi
  echo "==> [02] DOCKER_GID set to ${DOCKER_GID} (host docker group)"
  # FLASH_VERSION may change between ships — keep it in sync with flash.version.
  if grep -q '^FLASH_VERSION=' "${ENV_FILE}"; then
    sed -i.bak "s/^FLASH_VERSION=.*/FLASH_VERSION=${FLASH_VERSION}/" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
  else
    echo "FLASH_VERSION=${FLASH_VERSION}" >> "${ENV_FILE}"
  fi
  echo "==> [02] FLASH_VERSION pinned to ${FLASH_VERSION}"
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
DOCKER_GID=${DOCKER_GID}
FLASH_VERSION=${FLASH_VERSION}
EOF

chmod 600 "${ENV_FILE}"
echo "==> [02] wrote .env (app:7200  mongo:7220  admin pin:123456  v:${FLASH_VERSION})"