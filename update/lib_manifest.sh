#!/bin/bash
# Manifest library — reads releases/manifest.json for one channel into TARGET_* vars, and
# reconciles .env keys with the same sed idiom as 02_gen_env.sh (reconcile, never clobber).

# Sets: TARGET_VERSION TARGET_APP_DIGEST TARGET_MONGO_DIGEST TARGET_STRATEGY_DIGEST
#       TARGET_STRATEGY_BUN_DIGEST TARGET_MIN_COMPAT MANIFEST_HASH
manifest_read() {
  local manifestFile="$1"
  local channelName="$2"
  if [ ! -f "${manifestFile}" ]; then return 1; fi
  if ! jq -e ".channels.\"${channelName}\"" "${manifestFile}" >/dev/null 2>&1; then return 1; fi
  TARGET_VERSION="$(jq -r ".channels.\"${channelName}\".flashVersion" "${manifestFile}")"
  TARGET_APP_DIGEST="$(jq -r ".channels.\"${channelName}\".imageDigestMap.\"flash-app\" // empty" "${manifestFile}")"
  TARGET_MONGO_DIGEST="$(jq -r ".channels.\"${channelName}\".imageDigestMap.\"flash-mongo\" // empty" "${manifestFile}")"
  TARGET_STRATEGY_DIGEST="$(jq -r ".channels.\"${channelName}\".imageDigestMap.\"flash-strategy-runtime\" // empty" "${manifestFile}")"
  TARGET_STRATEGY_BUN_DIGEST="$(jq -r ".channels.\"${channelName}\".imageDigestMap.\"flash-strategy-runtime-bun\" // empty" "${manifestFile}")"
  TARGET_MIN_COMPAT="$(jq -r ".channels.\"${channelName}\".minCompatibleDataVersion // \"0.0.0\"" "${manifestFile}")"
  MANIFEST_HASH="sha256:$( (sha256sum "${manifestFile}" 2>/dev/null || shasum -a 256 "${manifestFile}") | cut -d' ' -f1)"
  if [ -z "${TARGET_VERSION}" ] || [ "${TARGET_VERSION}" = "null" ] || [ -z "${TARGET_APP_DIGEST}" ] || [ -z "${TARGET_MONGO_DIGEST}" ]; then return 1; fi
  return 0
}

env_get() {
  local envFile="$1"
  local keyName="$2"
  grep -E "^${keyName}=" "${envFile}" 2>/dev/null | head -1 | cut -d= -f2-
}

env_set() {
  local envFile="$1"
  local keyName="$2"
  local keyValue="$3"
  if grep -q "^${keyName}=" "${envFile}" 2>/dev/null; then
    sed -i.bak "s|^${keyName}=.*|${keyName}=${keyValue}|" "${envFile}" && rm -f "${envFile}.bak"
  else
    echo "${keyName}=${keyValue}" >> "${envFile}"
  fi
}

# Writes the TARGET_* digest set + version into .env (rollback calls this with last_good values
# exported into TARGET_*). Empty digests (unpublished image, e.g. bun runtime) are skipped LOUDLY.
env_write_target() {
  local envFile="$1"
  env_set "${envFile}" "FLASH_VERSION" "${TARGET_VERSION}"
  env_set "${envFile}" "FLASH_APP_DIGEST" "${TARGET_APP_DIGEST}"
  env_set "${envFile}" "FLASH_MONGO_DIGEST" "${TARGET_MONGO_DIGEST}"
  if [ -n "${TARGET_STRATEGY_DIGEST}" ]; then env_set "${envFile}" "FLASH_STRATEGY_DIGEST" "${TARGET_STRATEGY_DIGEST}"; else echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | WARN flash-strategy-runtime digest absent in manifest — keeping existing pin"; fi
  if [ -n "${TARGET_STRATEGY_BUN_DIGEST}" ]; then env_set "${envFile}" "FLASH_STRATEGY_BUN_DIGEST" "${TARGET_STRATEGY_BUN_DIGEST}"; else echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | hangar | WARN flash-strategy-runtime-bun digest absent in manifest — keeping existing pin"; fi
}

# semver_lte A B → 0 when A <= B (numeric per segment)
semver_lte() {
  local lower="$1"
  local higher="$2"
  [ "$(printf '%s\n%s\n' "${lower}" "${higher}" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "${lower}" ]
}
