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

# Compose pins images by digest; this seeds the initial pin, the hangar updater owns it after.
if ! command -v jq >/dev/null 2>&1; then
  JQ_SUDO=""; if [ "$(id -u)" -ne 0 ]; then JQ_SUDO="sudo"; fi
  $JQ_SUDO apt-get update -y >/dev/null 2>&1 || true
  $JQ_SUDO apt-get install -y jq >/dev/null 2>&1 || true
fi
MANIFEST_FILE="$(cd "$(dirname "$0")" && pwd)/releases/manifest.json"
FLASH_CHANNEL="${FLASH_CHANNEL:-stable}"
FLASH_VERSION="$(jq -r ".channels.\"${FLASH_CHANNEL}\".flashVersion // empty" "${MANIFEST_FILE}" 2>/dev/null)"
FLASH_APP_DIGEST="$(jq -r ".channels.\"${FLASH_CHANNEL}\".imageDigestMap.\"flash-app\" // empty" "${MANIFEST_FILE}" 2>/dev/null)"
FLASH_MONGO_DIGEST="$(jq -r ".channels.\"${FLASH_CHANNEL}\".imageDigestMap.\"flash-mongo\" // empty" "${MANIFEST_FILE}" 2>/dev/null)"
FLASH_STRATEGY_DIGEST="$(jq -r ".channels.\"${FLASH_CHANNEL}\".imageDigestMap.\"flash-strategy-runtime\" // empty" "${MANIFEST_FILE}" 2>/dev/null)"
FLASH_STRATEGY_BUN_DIGEST="$(jq -r ".channels.\"${FLASH_CHANNEL}\".imageDigestMap.\"flash-strategy-runtime-bun\" // empty" "${MANIFEST_FILE}" 2>/dev/null)"
if [ -z "${FLASH_VERSION}" ] || [ -z "${FLASH_APP_DIGEST}" ] || [ -z "${FLASH_MONGO_DIGEST}" ]; then
  echo "==> [02] ERROR: releases/manifest.json missing or channel '${FLASH_CHANNEL}' unreadable — cannot pin images" >&2
  exit 1
fi

# FLASH_HOSTNAME — public DNS name Caddy obtains a Let's Encrypt cert for. The
# droplet's PUBLIC IPv4 in dashed form via the free nip.io resolver
# (64.227.176.211 -> 64-227-176-211.nip.io). Source order matters: DO metadata
# is authoritative on a droplet; ifconfig.me is the off-DO fallback. We must NOT
# pick the host's private/anchor IP (hostname -I), which the internet can't reach.
detect_public_ip() {
  local ip
  ip="$(curl -s --max-time 3 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null)"
  if [ -z "${ip}" ]; then ip="$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)"; fi
  echo "${ip}"
}
PUBLIC_IP="$(detect_public_ip)"
FLASH_HOSTNAME=""
if [ -n "${PUBLIC_IP}" ]; then FLASH_HOSTNAME="${PUBLIC_IP//./-}.nip.io"; fi

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
  if ! grep -q '^FLASH_CHANNEL=' "${ENV_FILE}"; then
    echo "FLASH_CHANNEL=${FLASH_CHANNEL}" >> "${ENV_FILE}"
    echo "==> [02] FLASH_CHANNEL seeded as ${FLASH_CHANNEL}"
  fi
  # Seed-if-absent only: once present, the hangar updater is the single writer for these keys.
  for pinKey in FLASH_VERSION FLASH_APP_DIGEST FLASH_MONGO_DIGEST FLASH_STRATEGY_DIGEST FLASH_STRATEGY_BUN_DIGEST; do
    pinValue="$(eval "echo \${${pinKey}}")"
    if [ -n "${pinValue}" ] && ! grep -q "^${pinKey}=" "${ENV_FILE}"; then
      echo "${pinKey}=${pinValue}" >> "${ENV_FILE}"
      echo "==> [02] ${pinKey} seeded from manifest (${FLASH_CHANNEL})"
    fi
  done
  if grep -q '^FLASH_VERSION=latest$' "${ENV_FILE}"; then
    sed -i.bak "s/^FLASH_VERSION=latest$/FLASH_VERSION=${FLASH_VERSION}/" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
    echo "==> [02] FLASH_VERSION migrated latest → ${FLASH_VERSION}"
  fi
  # FLASH_HOSTNAME is IP-derived, not a cred — reconcile each run so a box that
  # changes IP (or predates HTTPS) gets the right hostname. Skip if detection
  # failed (empty) rather than clobbering a known-good value with nothing.
  if [ -n "${FLASH_HOSTNAME}" ]; then
    if grep -q '^FLASH_HOSTNAME=' "${ENV_FILE}"; then
      sed -i.bak "s/^FLASH_HOSTNAME=.*/FLASH_HOSTNAME=${FLASH_HOSTNAME}/" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
    else
      echo "FLASH_HOSTNAME=${FLASH_HOSTNAME}" >> "${ENV_FILE}"
    fi
    echo "==> [02] FLASH_HOSTNAME set to ${FLASH_HOSTNAME}"
  else
    echo "==> [02] WARNING: could not detect public IP — HTTPS hostname unset"
  fi
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
ADMIN_PIN=${ADMIN_PIN:-123456}
DOCKER_GID=${DOCKER_GID}
FLASH_CHANNEL=${FLASH_CHANNEL}
FLASH_VERSION=${FLASH_VERSION}
FLASH_APP_DIGEST=${FLASH_APP_DIGEST}
FLASH_MONGO_DIGEST=${FLASH_MONGO_DIGEST}
FLASH_STRATEGY_DIGEST=${FLASH_STRATEGY_DIGEST}
FLASH_STRATEGY_BUN_DIGEST=${FLASH_STRATEGY_BUN_DIGEST}
FLASH_HOSTNAME=${FLASH_HOSTNAME}
EOF

chmod 600 "${ENV_FILE}"
echo "==> [02] wrote .env (app:7200  mongo:7220  admin pin: see deploy screen or ADMIN_PIN in .env  v:${FLASH_VERSION})"