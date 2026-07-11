#!/bin/bash
# Fleet heartbeat — fire-and-forget CLAIM to the registry after every hangar run. A registry
# failure must NEVER affect the update or trading: failures queue locally and flush next run.

FLEET_TIMEOUT_SECONDS=10

fleet_send_heartbeat_after_run() {
  local identityFile="${FLASH_DIR}/.flash_identity.json"
  if [ ! -f "${identityFile}" ]; then return 0; fi
  local dropletId heartbeatSecret registryUrl
  dropletId="$(jq -r '.dropletId // empty' "${identityFile}")"
  heartbeatSecret="$(jq -r '.heartbeatSecret // empty' "${identityFile}")"
  registryUrl="$(jq -r '.registryUrl // "https://flashtrade.in"' "${identityFile}")"
  if [ -z "${dropletId}" ] || [ -z "${heartbeatSecret}" ]; then return 0; fi

  local appHealthy="false"
  if curl -fsS --max-time 5 "http://localhost:${APP_PORT:-7200}/health" >/dev/null 2>&1; then appHealthy="true"; fi

  local payload
  payload="$(jq -cn \
    --arg dropletId "${dropletId}" \
    --arg sentAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg channel "${CHANNEL:-stable}" \
    --arg flashVersion "$(env_get "${ENV_FILE}" "FLASH_VERSION")" \
    --arg app "$(env_get "${ENV_FILE}" "FLASH_APP_DIGEST")" \
    --arg mongo "$(env_get "${ENV_FILE}" "FLASH_MONGO_DIGEST")" \
    --arg strategy "$(env_get "${ENV_FILE}" "FLASH_STRATEGY_DIGEST")" \
    --arg bun "$(env_get "${ENV_FILE}" "FLASH_STRATEGY_BUN_DIGEST")" \
    --arg lastUpdateId "${UPDATE_ID:-}" \
    --arg lastUpdateOutcome "${OUTCOME:-}" \
    --argjson appHealthy "${appHealthy}" \
    '{dropletId:$dropletId,sentAt:$sentAt,channel:$channel,flashVersion:$flashVersion,imageDigestMap:{"flash-app":$app,"flash-mongo":$mongo,"flash-strategy-runtime":$strategy,"flash-strategy-runtime-bun":$bun},lastUpdateId:$lastUpdateId,lastUpdateOutcome:$lastUpdateOutcome,appHealthy:$appHealthy,runningStrategyCount:null}')"

  local queueFile="${STATE_DIR}/heartbeat_queue.jsonl"
  if ! fleet_post_heartbeat "${registryUrl}" "${dropletId}" "${heartbeatSecret}" "${payload}"; then
    echo "${payload}" >> "${queueFile}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | heartbeat queued (registry unreachable)"
    return 0
  fi
  fleet_flush_heartbeat_queue "${registryUrl}" "${dropletId}" "${heartbeatSecret}" "${queueFile}"
}

fleet_post_heartbeat() {
  local registryUrl="$1"
  local dropletId="$2"
  local heartbeatSecret="$3"
  local payload="$4"
  local signature
  signature="$(printf '%s' "${payload}" | openssl dgst -sha256 -hmac "${heartbeatSecret}" -r | cut -d' ' -f1)"
  curl -fsS --max-time "${FLEET_TIMEOUT_SECONDS}" -X POST "${registryUrl}/fleet/heartbeat" \
    -H "Content-Type: application/json" -H "X-Droplet-Id: ${dropletId}" -H "X-Signature: ${signature}" \
    -d "${payload}" >/dev/null 2>&1
}

fleet_flush_heartbeat_queue() {
  local registryUrl="$1"
  local dropletId="$2"
  local heartbeatSecret="$3"
  local queueFile="$4"
  if [ ! -s "${queueFile}" ]; then return 0; fi
  local remainingFile="${queueFile}.remaining"
  : > "${remainingFile}"
  while IFS= read -r queuedPayload; do
    [ -z "${queuedPayload}" ] && continue
    if ! fleet_post_heartbeat "${registryUrl}" "${dropletId}" "${heartbeatSecret}" "${queuedPayload}"; then
      echo "${queuedPayload}" >> "${remainingFile}"
    fi
  done < "${queueFile}"
  mv "${remainingFile}" "${queueFile}"
}
