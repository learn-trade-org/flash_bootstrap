#!/bin/bash
# [04] Run host/OS maintenance — delegates to server_maintenance/00_main.sh (which runs each task).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${SCRIPT_DIR}/server_maintenance/00_main.sh"
