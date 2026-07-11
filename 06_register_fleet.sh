#!/bin/bash
# [06] Register this box with the fleet registry — one immutable identity per droplet (INV-11).
# Idempotent: an existing .flash_identity.json is never regenerated (lost file = new identity;
# the old one decays to UNREACHABLE and an operator decommissions it — history is never grafted).
#
#   FLEET_REGISTRATION_TOKEN=… ./06_register_fleet.sh [--owner INTERNAL|CUSTOMER] [--registry-url https://flashtrade.in]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLASH_DIR="${FLASH_DIR:-$(cd "${SCRIPT_DIR}/../flash" && pwd)}"
IDENTITY_FILE="${FLASH_DIR}/.flash_identity.json"

OWNER_LABEL="CUSTOMER"
REGISTRY_URL="https://flashtrade.in"
while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER_LABEL="${2:?--owner needs INTERNAL|CUSTOMER}"; shift 2 ;;
    --registry-url) REGISTRY_URL="${2:?--registry-url needs a value}"; shift 2 ;;
    *) echo "==> [06] unknown arg $1" >&2; exit 1 ;;
  esac
done

if [ -f "${IDENTITY_FILE}" ]; then
  echo "==> [06] ${IDENTITY_FILE} exists — identity is immutable, skipping"
  exit 0
fi
if [ -z "${FLEET_REGISTRATION_TOKEN:-}" ]; then
  echo "==> [06] FLEET_REGISTRATION_TOKEN unset — skipping fleet registration (box will not heartbeat)"
  exit 0
fi

CHANNEL="$(grep -E '^FLASH_CHANNEL=' "${FLASH_DIR}/.env" 2>/dev/null | cut -d= -f2)"
CHANNEL="${CHANNEL:-stable}"
PUBLIC_IP="$(curl -s --max-time 3 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || true)"

RESPONSE="$(curl -fsS --max-time 15 -X POST "${REGISTRY_URL}/fleet/register" \
  -H "Content-Type: application/json" \
  -d "$(jq -cn --arg token "${FLEET_REGISTRATION_TOKEN}" --arg owner "${OWNER_LABEL}" --arg channel "${CHANNEL}" --arg ip "${PUBLIC_IP}" '{registrationToken:$token,ownerLabel:$owner,channel:$channel,ipAddress:(if $ip == "" then null else $ip end)}')")"

DROPLET_ID="$(echo "${RESPONSE}" | jq -r '.data.dropletId // empty')"
HEARTBEAT_SECRET="$(echo "${RESPONSE}" | jq -r '.data.heartbeatSecret // empty')"
if [ -z "${DROPLET_ID}" ] || [ -z "${HEARTBEAT_SECRET}" ]; then
  echo "==> [06] registration failed: ${RESPONSE}" >&2
  exit 1
fi

jq -cn --arg dropletId "${DROPLET_ID}" --arg secret "${HEARTBEAT_SECRET}" --arg url "${REGISTRY_URL}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{dropletId:$dropletId,heartbeatSecret:$secret,registryUrl:$url,registeredAt:$at}' > "${IDENTITY_FILE}"
chmod 600 "${IDENTITY_FILE}"
echo "==> [06] registered as ${DROPLET_ID} (${OWNER_LABEL}, ${CHANNEL}) → ${IDENTITY_FILE}"
