#!/bin/bash
# [02b] Register this droplet in the flashtrade.in fleet registry.
#
# One-click deploys export FLEET_REGISTRATION_TOKEN + FLASH_PROGRESS_URL +
# FLASH_CLOUD_ID via cloud-init; manual installs have none and skip silently.
# The returned dropletId + heartbeatSecret land in flash/.env for the
# updater's HMAC heartbeats. Registration failure NEVER blocks the install.

set -e

FLASH_DIR="${FLASH_DIR:-$(cd "$(dirname "$0")/../flash" && pwd)}"
ENV_FILE="${FLASH_DIR}/.env"

if [ -z "${FLEET_REGISTRATION_TOKEN:-}" ] || [ -z "${FLASH_PROGRESS_URL:-}" ] || [ -z "${FLASH_CLOUD_ID:-}" ]; then
  echo "==> [02b] fleet registration skipped (no cloud-init fleet env)"
  exit 0
fi

if grep -q "^FLEET_DROPLET_ID=" "${ENV_FILE}" 2>/dev/null; then
  echo "==> [02b] fleet registration already in .env — skipping"
  exit 0
fi

FLEET_BASE_URL="${FLASH_PROGRESS_URL%/deploy/progress}"
DROPLET_PUBLIC_IP="$(curl -s --max-time 5 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address || true)"

REGISTER_BODY="{\"registrationToken\":\"${FLEET_REGISTRATION_TOKEN}\",\"cloudId\":\"${FLASH_CLOUD_ID}\",\"channel\":\"stable\",\"ipAddress\":\"${DROPLET_PUBLIC_IP}\"}"
REGISTER_RESPONSE="$(curl -s --max-time 15 -X POST "${FLEET_BASE_URL}/fleet/register" -H 'Content-Type: application/json' -d "${REGISTER_BODY}" || true)"

FLEET_DROPLET_ID="$(printf '%s' "${REGISTER_RESPONSE}" | grep -o '"dropletId":"[^"]*"' | cut -d'"' -f4)"
FLEET_HEARTBEAT_SECRET="$(printf '%s' "${REGISTER_RESPONSE}" | grep -o '"heartbeatSecret":"[^"]*"' | cut -d'"' -f4)"

if [ -z "${FLEET_DROPLET_ID}" ] || [ -z "${FLEET_HEARTBEAT_SECRET}" ]; then
  echo "==> [02b] fleet registration FAILED (non-fatal): ${REGISTER_RESPONSE}"
  exit 0
fi

{
  echo "FLEET_API_URL=${FLEET_BASE_URL}"
  echo "FLEET_DROPLET_ID=${FLEET_DROPLET_ID}"
  echo "FLEET_HEARTBEAT_SECRET=${FLEET_HEARTBEAT_SECRET}"
} >> "${ENV_FILE}"

echo "==> [02b] registered in fleet as ${FLEET_DROPLET_ID}"
