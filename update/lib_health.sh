#!/bin/bash
# Health gate — 3 consecutive passes (HTTP 200 + reported version == expected) or fail after 10
# probes; consecutive requirement makes flapping a failure. Fills HEALTH_PROBE_JSON for the audit.

HEALTH_PROBE_TOTAL=10
HEALTH_PROBE_INTERVAL_SECONDS=30
HEALTH_PROBE_CONSECUTIVE_REQUIRED=3

health_gate() {
  local expectedVersion="$1"
  local appPort="$2"
  local consecutivePassCount=0
  HEALTH_PROBE_JSON="[]"
  local probeNumber
  for probeNumber in $(seq 1 "${HEALTH_PROBE_TOTAL}"); do
    local httpCode reportedVersion probeResult
    httpCode="$(curl -s -o /tmp/flash_health_body.json -w '%{http_code}' --max-time 10 "http://localhost:${appPort}/health" || echo "000")"
    reportedVersion="$(jq -r '.data.version.app // empty' /tmp/flash_health_body.json 2>/dev/null || true)"
    if [ "${httpCode}" = "200" ] && [ "${reportedVersion}" = "${expectedVersion}" ]; then
      consecutivePassCount=$((consecutivePassCount + 1))
      probeResult="pass"
    else
      consecutivePassCount=0
      probeResult="fail"
    fi
    HEALTH_PROBE_JSON="$(jq -cn --argjson existing "${HEALTH_PROBE_JSON}" \
      --argjson probe "${probeNumber}" --arg http "${httpCode}" --arg appVersion "${reportedVersion}" --arg result "${probeResult}" \
      '$existing + [{probe:$probe,http:$http,appVersion:$appVersion,result:$result}]')"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | health probe ${probeNumber}/${HEALTH_PROBE_TOTAL} http=${httpCode} version=${reportedVersion:-none} → ${probeResult}"
    if [ "${consecutivePassCount}" -ge "${HEALTH_PROBE_CONSECUTIVE_REQUIRED}" ]; then return 0; fi
    if [ "${probeNumber}" -lt "${HEALTH_PROBE_TOTAL}" ]; then sleep "${HEALTH_PROBE_INTERVAL_SECONDS}"; fi
  done
  return 1
}
