#!/bin/bash
# Audit library — every updater run appends exactly ONE line to hangar_history.jsonl, no matter
# how it exits (trap in 00_main.sh calls audit_finish). Append-only: no line is ever rewritten.

audit_init() {
  STATE_DIR="$1"
  mkdir -p "${STATE_DIR}"
  UPDATE_ID="upd_$(date -u +%Y%m%dT%H%M%SZ)_${RANDOM}"
  UPDATE_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  UPDATE_STARTED_EPOCH="$(date +%s)"
  STATES_WALKED=""
  HEALTH_PROBE_JSON="[]"
  OUTCOME="ABORTED"
  FROM_VERSION=""
  TO_VERSION=""
  MANIFEST_HASH=""
  CHANNEL=""
}

audit_state() {
  local stateName="$1"
  if [ -z "${STATES_WALKED}" ]; then STATES_WALKED="\"${stateName}\""; else STATES_WALKED="${STATES_WALKED},\"${stateName}\""; fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | ${UPDATE_ID} | state=${stateName}"
}

audit_finish() {
  local durationMs=$(( ($(date +%s) - UPDATE_STARTED_EPOCH) * 1000 ))
  jq -cn \
    --arg updateId "${UPDATE_ID}" \
    --arg channel "${CHANNEL}" \
    --arg initiator "${INITIATOR}" \
    --arg fromVersion "${FROM_VERSION}" \
    --arg toVersion "${TO_VERSION}" \
    --arg manifestHash "${MANIFEST_HASH}" \
    --arg outcome "${OUTCOME}" \
    --arg startedAt "${UPDATE_STARTED_AT}" \
    --argjson statesWalked "[${STATES_WALKED}]" \
    --argjson healthProbeArray "${HEALTH_PROBE_JSON}" \
    --argjson durationMs "${durationMs}" \
    '{updateId:$updateId,channel:$channel,initiator:$initiator,fromVersion:$fromVersion,toVersion:$toVersion,manifestHash:$manifestHash,statesWalked:$statesWalked,healthProbeArray:$healthProbeArray,outcome:$outcome,durationMs:$durationMs,startedAt:$startedAt}' \
    >> "${STATE_DIR}/hangar_history.jsonl"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | ${UPDATE_ID} | outcome=${OUTCOME} durationMs=${durationMs}"
}
