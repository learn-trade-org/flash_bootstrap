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

install_jq_if_missing() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi

  local sudoPrefix=""
  if [ "$(id -u)" -ne 0 ]; then
    sudoPrefix="sudo"
  fi

  $sudoPrefix apt-get update -y >/dev/null 2>&1 || true
  $sudoPrefix apt-get install -y jq >/dev/null 2>&1 || true
}

# Compose pins every image by digest, never a tag. This seeds the initial pin from
# flashtrade.in's release_registry; flash-updater owns the keys after that.
fetch_release_manifest() {
  local channel="$1"
  local registryUrl="$2"

  local requestBody
  requestBody="$(jq -cn --arg channel "${channel}" '{channel: $channel}')"

  curl -fsS --max-time 15 \
    -X POST "${registryUrl}/release/manifest" \
    -H "Content-Type: application/json" \
    -d "${requestBody}" \
    2>/dev/null || true
}

install_jq_if_missing

FLASH_CHANNEL="${FLASH_CHANNEL:-stable}"
FLASH_REGISTRY_URL="${FLASH_REGISTRY_URL:-https://flashtrade.in}"

MANIFEST_RESPONSE="$(fetch_release_manifest "${FLASH_CHANNEL}" "${FLASH_REGISTRY_URL}")"

FLASH_VERSION="$(jq -r '.data.manifest.flashVersion // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"
FLASH_APP_DIGEST="$(jq -r '.data.manifest.imageDigestMap."flash-app" // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"
FLASH_MONGO_DIGEST="$(jq -r '.data.manifest.imageDigestMap."flash-mongo" // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"
FLASH_STRATEGY_DIGEST="$(jq -r '.data.manifest.imageDigestMap."flash-strategy-runtime" // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"
FLASH_STRATEGY_BUN_DIGEST="$(jq -r '.data.manifest.imageDigestMap."flash-strategy-runtime-bun" // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"
FLASH_UPDATER_DIGEST="$(jq -r '.data.manifest.imageDigestMap."flash-updater" // empty' <<<"${MANIFEST_RESPONSE}" 2>/dev/null || true)"

if [ -z "${FLASH_VERSION}" ] || [ -z "${FLASH_APP_DIGEST}" ] || [ -z "${FLASH_MONGO_DIGEST}" ] || [ -z "${FLASH_UPDATER_DIGEST}" ]; then
  echo "==> [02] ERROR: could not fetch a usable manifest from ${FLASH_REGISTRY_URL}/release/manifest (channel '${FLASH_CHANNEL}') — cannot pin images" >&2
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

env_set() {
  local keyName="$1"
  local keyValue="$2"

  if grep -q "^${keyName}=" "${ENV_FILE}"; then
    sed -i.bak "s|^${keyName}=.*|${keyName}=${keyValue}|" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
  else
    echo "${keyName}=${keyValue}" >> "${ENV_FILE}"
  fi
}

env_seed_if_absent() {
  local keyName="$1"
  local keyValue="$2"

  if [ -n "${keyValue}" ] && ! grep -q "^${keyName}=" "${ENV_FILE}"; then
    echo "${keyName}=${keyValue}" >> "${ENV_FILE}"
    echo "==> [02] ${keyName} seeded from manifest (channel ${FLASH_CHANNEL})"
  fi
}

if [ -f "${ENV_FILE}" ]; then
  echo "==> [02] ${ENV_FILE} already exists — leaving creds untouched."

  # DOCKER_GID and FLASH_HOSTNAME are host-derived, not creds — reconcile every run,
  # a stale value breaks strategy-container deploys / HTTPS respectively.
  env_set "DOCKER_GID" "${DOCKER_GID}"
  echo "==> [02] DOCKER_GID set to ${DOCKER_GID} (host docker group)"

  if [ -n "${FLASH_HOSTNAME}" ]; then
    env_set "FLASH_HOSTNAME" "${FLASH_HOSTNAME}"
    echo "==> [02] FLASH_HOSTNAME set to ${FLASH_HOSTNAME}"
  else
    echo "==> [02] WARNING: could not detect public IP — HTTPS hostname unset"
  fi

  # FLASH_CHANNEL + every digest key: seed-if-absent only. Once present, flash-updater
  # is the single writer — a bootstrap re-run must never fight its own update cycle.
  env_seed_if_absent "FLASH_CHANNEL" "${FLASH_CHANNEL}"
  env_seed_if_absent "FLASH_VERSION" "${FLASH_VERSION}"
  env_seed_if_absent "FLASH_APP_DIGEST" "${FLASH_APP_DIGEST}"
  env_seed_if_absent "FLASH_MONGO_DIGEST" "${FLASH_MONGO_DIGEST}"
  env_seed_if_absent "FLASH_STRATEGY_DIGEST" "${FLASH_STRATEGY_DIGEST}"
  env_seed_if_absent "FLASH_STRATEGY_BUN_DIGEST" "${FLASH_STRATEGY_BUN_DIGEST}"
  env_seed_if_absent "FLASH_UPDATER_DIGEST" "${FLASH_UPDATER_DIGEST}"
  env_seed_if_absent "FLEET_REGISTRATION_TOKEN" "${FLEET_REGISTRATION_TOKEN:-}"

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
FLASH_UPDATER_DIGEST=${FLASH_UPDATER_DIGEST}
FLASH_HOSTNAME=${FLASH_HOSTNAME}
FLEET_REGISTRATION_TOKEN=${FLEET_REGISTRATION_TOKEN:-}
EOF

chmod 600 "${ENV_FILE}"
echo "==> [02] wrote .env (app:7200  mongo:7220  admin pin: see deploy screen or ADMIN_PIN in .env  v:${FLASH_VERSION})"