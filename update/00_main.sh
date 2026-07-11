#!/bin/bash
# Hangar — nightly updater state machine (runs from the stable sibling bin/, outside the git
# repo, so a pull never rewrites the running script). Every run audits exactly once via trap.
#
#   FETCH_MANIFEST → CHECK → DOWNLOAD → PREFLIGHT → APPLY → HEALTH_GATE → COMMIT
#                      │defer                                    │fail
#                      ▼                                         ▼
#                    AUDIT ◂──────────────────────────────── ROLLBACK (to last_good.json)
set -euo pipefail
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${BIN_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/flash_bootstrap"
FLASH_DIR="${ROOT_DIR}/flash"
ENV_FILE="${FLASH_DIR}/.env"
STATE_DIR="${BIN_DIR}/hangar_state"
COMPOSE_FILE="${FLASH_DIR}/docker-compose.customer.yml"
MANIFEST_FILE="${FLASH_UPDATE_MANIFEST_FILE:-${BOOTSTRAP_DIR}/releases/manifest.json}"
REGISTRY="ghcr.io/learn-trade-org"
INITIATOR="${FLASH_UPDATE_INITIATOR:-CRON}"

source "${BIN_DIR}/lib_audit.sh"
source "${BIN_DIR}/lib_manifest.sh"
source "${BIN_DIR}/lib_health.sh"
if [ -f "${BIN_DIR}/lib_fleet.sh" ]; then source "${BIN_DIR}/lib_fleet.sh"; fi

audit_init "${STATE_DIR}"
# Heartbeat is fire-and-forget — a dead registry must never fail the run.
trap 'audit_finish; type fleet_send_heartbeat_after_run >/dev/null 2>&1 && fleet_send_heartbeat_after_run || true' EXIT

fail_count_bump() {
  local currentCount
  currentCount="$(jq -r --arg h "${MANIFEST_HASH}" 'select(.manifestHash == $h) | .failCount' "${STATE_DIR}/failed_manifest.json" 2>/dev/null || true)"
  currentCount="${currentCount:-0}"
  jq -cn --arg h "${MANIFEST_HASH}" --argjson c "$((currentCount + 1))" '{manifestHash:$h,failCount:$c}' > "${STATE_DIR}/failed_manifest.json"
}

# ── FETCH_MANIFEST ────────────────────────────────────────────────────────────
audit_state "FETCH_MANIFEST"
cd "${BOOTSTRAP_DIR}"
# Emergency runs skip the fetch — the network/repo may BE the incident.
if [ "${INITIATOR}" = "CRON" ] || [ "${INITIATOR}" = "MANUAL" ]; then
  git pull --ff-only origin master
  cp assets/docker-compose.customer.yml assets/launch.sh assets/Caddyfile "${FLASH_DIR}/"
fi

CHANNEL="$(env_get "${ENV_FILE}" "FLASH_CHANNEL")"
CHANNEL="${CHANNEL:-stable}"
if ! manifest_read "${MANIFEST_FILE}" "${CHANNEL}"; then
  OUTCOME="MANIFEST_INVALID"
  exit 0
fi
FROM_VERSION="$(env_get "${ENV_FILE}" "FLASH_VERSION")"
TO_VERSION="${TARGET_VERSION}"
APP_PORT="$(env_get "${ENV_FILE}" "APP_HOST_PORT")"
APP_PORT="${APP_PORT:-7200}"

CURRENT_APP_DIGEST="$(env_get "${ENV_FILE}" "FLASH_APP_DIGEST")"
CURRENT_MONGO_DIGEST="$(env_get "${ENV_FILE}" "FLASH_MONGO_DIGEST")"

# Seed the rollback target from what runs NOW, before attempting any change.
if [ ! -f "${STATE_DIR}/last_good.json" ] && [ -n "${CURRENT_APP_DIGEST}" ] && [ -n "${CURRENT_MONGO_DIGEST}" ]; then
  jq -cn --arg v "${FROM_VERSION}" \
    --arg app "${CURRENT_APP_DIGEST}" --arg mongo "${CURRENT_MONGO_DIGEST}" \
    --arg strategy "$(env_get "${ENV_FILE}" "FLASH_STRATEGY_DIGEST")" --arg bun "$(env_get "${ENV_FILE}" "FLASH_STRATEGY_BUN_DIGEST")" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{flashVersion:$v,imageDigestMap:{"flash-app":$app,"flash-mongo":$mongo,"flash-strategy-runtime":$strategy,"flash-strategy-runtime-bun":$bun},committedAt:$at,seededFromRunning:true}' \
    > "${STATE_DIR}/last_good.json"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | seeded last_good.json from running digests (${FROM_VERSION})"
fi

if [ "${CURRENT_APP_DIGEST}" = "${TARGET_APP_DIGEST}" ] && [ "${CURRENT_MONGO_DIGEST}" = "${TARGET_MONGO_DIGEST}" ]; then
  # .env alone can lie after a crash mid-APPLY — NOOP only when the app REPORTS the target version.
  reportedVersion="$(curl -s --max-time 10 "http://localhost:${APP_PORT}/health" | jq -r '.data.version.app // empty' 2>/dev/null || true)"
  if [ "${reportedVersion}" = "${TARGET_VERSION}" ]; then
    OUTCOME="NOOP"
    exit 0
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | .env matches target but app reports '${reportedVersion:-none}' — resuming APPLY (crash-mid-apply recovery)"
fi

# ── CHECK ─────────────────────────────────────────────────────────────────────
audit_state "CHECK"
# Trading-window guard (INV-10): 08:45–16:15 IST = 03:15–10:45 UTC.
minutesNowUtc=$((10#$(date -u +%H) * 60 + 10#$(date -u +%M)))
if [ "${FLASH_UPDATE_SKIP_WINDOW_GUARD:-0}" != "1" ] && [ "${minutesNowUtc}" -ge 195 ] && [ "${minutesNowUtc}" -le 645 ]; then
  OUTCOME="DEFERRED_WINDOW"
  exit 0
fi

failedHash="$(jq -r '.manifestHash // empty' "${STATE_DIR}/failed_manifest.json" 2>/dev/null || true)"
failedCount="$(jq -r '.failCount // 0' "${STATE_DIR}/failed_manifest.json" 2>/dev/null || echo 0)"
if [ "${failedHash}" = "${MANIFEST_HASH}" ] && [ "${failedCount}" -ge 2 ]; then
  OUTCOME="SKIPPED_FAILED_MANIFEST"
  exit 0
fi

freeDiskGb="$(df -Pk "${ROOT_DIR}" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
if [ "${freeDiskGb}" -lt 3 ]; then
  OUTCOME="DEFERRED_DISK"
  exit 0
fi
docker info >/dev/null

# ── DOWNLOAD (pull by digest — the running app is untouched) ─────────────────
audit_state "DOWNLOAD"
if ! {
  docker pull "${REGISTRY}/flash-app@${TARGET_APP_DIGEST}" &&
  docker pull "${REGISTRY}/flash-mongo@${TARGET_MONGO_DIGEST}" &&
  { [ -z "${TARGET_STRATEGY_DIGEST}" ] || docker pull "${REGISTRY}/flash-strategy-runtime@${TARGET_STRATEGY_DIGEST}"; } &&
  { [ -z "${TARGET_STRATEGY_BUN_DIGEST}" ] || docker pull "${REGISTRY}/flash-strategy-runtime-bun@${TARGET_STRATEGY_BUN_DIGEST}"; }
}; then
  fail_count_bump
  OUTCOME="DOWNLOAD_FAILED"
  exit 0
fi

# ── PREFLIGHT ─────────────────────────────────────────────────────────────────
audit_state "PREFLIGHT"
if ! curl -fsS --max-time 10 "http://localhost:${APP_PORT}/health" >/dev/null 2>&1; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | WARN baseline /health not responding — proceeding (the update may BE the fix; rollback target exists)"
fi
# Data-compat window (ADR-005); legacy FLASH_VERSION=latest predates the law → treated compatible.
if [ -n "${FROM_VERSION}" ] && [ "${FROM_VERSION}" != "latest" ] && ! semver_lte "${TARGET_MIN_COMPAT}" "${FROM_VERSION}"; then
  fail_count_bump
  OUTCOME="PREFLIGHT_FAILED"
  exit 0
fi

# ── APPLY ─────────────────────────────────────────────────────────────────────
audit_state "APPLY"
env_write_target "${ENV_FILE}"
cd "${FLASH_DIR}"
docker compose -f docker-compose.customer.yml up -d
bash "${BOOTSTRAP_DIR}/04_server_maintenance.sh" || true

# ── HEALTH_GATE ───────────────────────────────────────────────────────────────
audit_state "HEALTH_GATE"
if health_gate "${TARGET_VERSION}" "${APP_PORT}"; then
  # ── COMMIT ──────────────────────────────────────────────────────────────────
  audit_state "COMMIT"
  jq -cn --arg v "${TARGET_VERSION}" \
    --arg app "${TARGET_APP_DIGEST}" --arg mongo "${TARGET_MONGO_DIGEST}" \
    --arg strategy "${TARGET_STRATEGY_DIGEST}" --arg bun "${TARGET_STRATEGY_BUN_DIGEST}" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{flashVersion:$v,imageDigestMap:{"flash-app":$app,"flash-mongo":$mongo,"flash-strategy-runtime":$strategy,"flash-strategy-runtime-bun":$bun},committedAt:$at}' \
    > "${STATE_DIR}/last_good.json"
  rm -f "${STATE_DIR}/failed_manifest.json"
  # Success path only — a broken repo script must never overwrite a working bin/.
  cp "${BOOTSTRAP_DIR}"/update/*.sh "${BIN_DIR}/"
  OUTCOME="SUCCESS"
  exit 0
fi

# ── ROLLBACK ──────────────────────────────────────────────────────────────────
audit_state "ROLLBACK"
fail_count_bump
if [ ! -f "${STATE_DIR}/last_good.json" ]; then
  OUTCOME="ROLLBACK_FAILED"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | FATAL health gate failed and no last_good.json exists — manual intervention required"
  exit 0
fi
TARGET_VERSION="$(jq -r '.flashVersion' "${STATE_DIR}/last_good.json")"
TARGET_APP_DIGEST="$(jq -r '.imageDigestMap."flash-app" // empty' "${STATE_DIR}/last_good.json")"
TARGET_MONGO_DIGEST="$(jq -r '.imageDigestMap."flash-mongo" // empty' "${STATE_DIR}/last_good.json")"
TARGET_STRATEGY_DIGEST="$(jq -r '.imageDigestMap."flash-strategy-runtime" // empty' "${STATE_DIR}/last_good.json")"
TARGET_STRATEGY_BUN_DIGEST="$(jq -r '.imageDigestMap."flash-strategy-runtime-bun" // empty' "${STATE_DIR}/last_good.json")"
env_write_target "${ENV_FILE}"
docker compose -f docker-compose.customer.yml up -d
if health_gate "${TARGET_VERSION}" "${APP_PORT}"; then
  OUTCOME="ROLLED_BACK"
else
  OUTCOME="ROLLBACK_FAILED"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | FATAL rollback did not become healthy — manual intervention required"
fi
exit 0
