#!/bin/bash
# Hangar promotion — the one human gate that ships canary to customers (copies canary → stable).
#
#   ./hangar_promote.sh --reason "0.2.25 — watchdog + candle parity"
#   ./hangar_promote.sh --reason "hotfix" --force        # override the 24h canary bake window
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/releases/manifest.json"

REASON=""
FORCE="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) REASON="${2:?--reason needs a value}"; shift 2 ;;
    --force)  FORCE="1"; shift ;;
    *) echo "hangar_promote: unknown arg $1" >&2; exit 1 ;;
  esac
done
if [ -z "${REASON}" ]; then echo "hangar_promote: --reason is mandatory (it becomes the audit trail)" >&2; exit 1; fi

AUTHOR="$(git -C "${SCRIPT_DIR}" config user.name 2>/dev/null || whoami)"
CANARY_VERSION="$(jq -r '.channels.canary.flashVersion' "${MANIFEST_FILE}")"
STABLE_VERSION="$(jq -r '.channels.stable.flashVersion' "${MANIFEST_FILE}")"
if [ "${CANARY_VERSION}" = "${STABLE_VERSION}" ]; then
  echo "hangar_promote: canary (${CANARY_VERSION}) already equals stable — nothing to promote"
  exit 0
fi

# 24h bake window: canary must have soaked at least one full nightly cycle before customers get it.
PUBLISHED_AT="$(jq -r '.publishedAt' "${MANIFEST_FILE}")"
publishedEpoch="$(date -u -d "${PUBLISHED_AT}" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "${PUBLISHED_AT}" +%s)"
ageHours=$(( ($(date -u +%s) - publishedEpoch) / 3600 ))
if [ "${ageHours}" -lt 24 ] && [ "${FORCE}" != "1" ]; then
  echo "hangar_promote: canary ${CANARY_VERSION} is only ${ageHours}h old (< 24h bake). Use --force to override — the override is recorded in the commit." >&2
  exit 1
fi

FORCE_NOTE=""
if [ "${FORCE}" = "1" ] && [ "${ageHours}" -lt 24 ]; then FORCE_NOTE=" [FORCED at ${ageHours}h bake]"; fi

jq --arg author "${AUTHOR}" --arg reason "${REASON}${FORCE_NOTE}" \
  '.channels.stable = (.channels.canary + {promotedAt:(now|todate)}) | .author = $author | .reason = $reason | .publishedAt = (now|todate)' \
  "${MANIFEST_FILE}" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "${MANIFEST_FILE}"

git -C "${SCRIPT_DIR}" add releases/manifest.json
git -C "${SCRIPT_DIR}" commit -m "release(stable): ${CANARY_VERSION} — ${REASON}${FORCE_NOTE}"
git -C "${SCRIPT_DIR}" push origin master
echo "hangar_promote: stable → ${CANARY_VERSION} (fleet converges on the next nightly hangar run)"
