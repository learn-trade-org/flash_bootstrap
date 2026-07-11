#!/bin/bash
# Hangar emergency pin — runs the SAME state machine as the nightly cron, initiator=EMERGENCY.
#
#   ./hangar_pin.sh --last-good                 # rollback to hangar_state/last_good.json
#   ./hangar_pin.sh 0.2.23                      # pin to a version from manifest git history
#   ./hangar_pin.sh 0.2.23 --force-window       # bypass trading-window guard (stop strategies first)
set -euo pipefail
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${BIN_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/flash_bootstrap"
STATE_DIR="${BIN_DIR}/hangar_state"
PIN_MANIFEST="${STATE_DIR}/emergency_pin_manifest.json"

TARGET_ARG="${1:?usage: hangar_pin.sh <version>|--last-good [--force-window]}"
FORCE_WINDOW="0"
if [ "${2:-}" = "--force-window" ]; then FORCE_WINDOW="1"; fi

mkdir -p "${STATE_DIR}"
CHANNEL_NAME="$(grep -E '^FLASH_CHANNEL=' "${ROOT_DIR}/flash/.env" 2>/dev/null | cut -d= -f2)"
CHANNEL_NAME="${CHANNEL_NAME:-stable}"

if [ "${TARGET_ARG}" = "--last-good" ]; then
  if [ ! -f "${STATE_DIR}/last_good.json" ]; then
    echo "hangar_pin: no last_good.json on this box — nothing proven to roll back to" >&2
    exit 1
  fi
  jq -n --arg ch "${CHANNEL_NAME}" --slurpfile lastGood "${STATE_DIR}/last_good.json" \
    '{manifestSchemaVersion:1,author:"emergency",reason:"pin to last-known-good",publishedAt:(now|todate),channels:{($ch):{flashVersion:$lastGood[0].flashVersion,imageDigestMap:$lastGood[0].imageDigestMap,minCompatibleDataVersion:"0.0.0",promotedAt:null}}}' \
    > "${PIN_MANIFEST}"
else
  # Digests come from the audited manifest history, never from a mutable registry tag.
  FOUND_ENTRY=""
  for commitSha in $(git -C "${BOOTSTRAP_DIR}" log --format=%H -- releases/manifest.json); do
    FOUND_ENTRY="$(git -C "${BOOTSTRAP_DIR}" show "${commitSha}:releases/manifest.json" 2>/dev/null \
      | jq -c --arg v "${TARGET_ARG}" '[.channels[] | select(.flashVersion == $v)][0] // empty' 2>/dev/null || true)"
    if [ -n "${FOUND_ENTRY}" ]; then break; fi
  done
  if [ -z "${FOUND_ENTRY}" ]; then
    echo "hangar_pin: version ${TARGET_ARG} not found in releases/manifest.json git history" >&2
    exit 1
  fi
  jq -n --arg ch "${CHANNEL_NAME}" --argjson entry "${FOUND_ENTRY}" \
    '{manifestSchemaVersion:1,author:"emergency",reason:("pin to " + $entry.flashVersion),publishedAt:(now|todate),channels:{($ch):($entry + {minCompatibleDataVersion:"0.0.0"})}}' \
    > "${PIN_MANIFEST}"
fi

if [ "${FORCE_WINDOW}" = "1" ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | EMERGENCY --force-window: bypassing trading-window guard — ensure strategies are stopped"
fi

FLASH_UPDATE_INITIATOR="EMERGENCY" \
FLASH_UPDATE_MANIFEST_FILE="${PIN_MANIFEST}" \
FLASH_UPDATE_SKIP_WINDOW_GUARD="${FORCE_WINDOW}" \
bash "${BIN_DIR}/00_main.sh"
