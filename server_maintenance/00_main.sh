#!/bin/bash
# Runs the host maintenance tasks. Each must be idempotent. `|| log`: one failing task must not block the rest.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | server-maintenance | $1"; }

log "run start"
bash "${SELF_DIR}/01_add_swap.sh" || log "FAILED 01_add_swap.sh"
log "run done"
