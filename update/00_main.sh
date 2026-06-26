#!/bin/bash
# Cron entry point — runs nightly from the stable sibling bin/ (outside the git repo, so a pull
# never rewrites the running script). Thin orchestrator: fetch (01) then apply (02).
set -euo pipefail
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | flash-update | $1"; }

log "run start"
bash "${BIN_DIR}/01_image_pull.sh"
bash "${BIN_DIR}/02_redeploy.sh"
log "run done"
