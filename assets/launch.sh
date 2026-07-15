#!/bin/bash
# Customer launcher — runs the PULLED (baked) flash stack. Lives inside the
# generated flash/ runtime dir (copied here by 00_bootstrap.sh). Unlike the
# flash repo's own launch.sh (which builds locally), this one only PULLS images
# from GHCR and runs them — no source, no build.
#
# Usage:
#   ./launch.sh start      pull images + start in background
#   ./launch.sh stop       stop and remove containers (keeps db/ data)
#   ./launch.sh restart    stop then start
#   ./launch.sh pull       pull latest images for the pinned FLASH_VERSION
#   ./launch.sh logs       follow combined logs
#   ./launch.sh status     show container summary

set -e

cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.customer.yml"

if [ ! -f .env ]; then
  echo "Missing .env — run flash_bootstrap/02_gen_env.sh first" >&2
  exit 1
fi

APP_PORT="$(grep -E '^APP_HOST_PORT=' .env | cut -d= -f2)"
APP_PORT="${APP_PORT:-7200}"

# Pre-create bind sources so the docker daemon doesn't auto-create them
# root-owned (else uid-1000 app/mongo hit EACCES writing db/*).
mkdir -p db/mongo db/strategy db/strategy/.logs db/tick db/instrument updater_state

# The backend launches strategy containers by the FIXED local name
# `flash-strategy-runtime:latest` (container_high_level.ts). The pulled image is
# tagged with the GHCR path, so retag it to the name the backend expects.
#
# Pulled BY DIGEST (FLASH_STRATEGY_DIGEST/_BUN_DIGEST from .env), same rule as
# app/mongo in the compose file — a mutable :tag here would defeat digest-pinning
# for the one pair of images that don't go through compose at all.
retag_strategy_runtime() {
  local strategyDigest bunDigest

  strategyDigest="$(grep -E '^FLASH_STRATEGY_DIGEST=' .env | cut -d= -f2)"
  bunDigest="$(grep -E '^FLASH_STRATEGY_BUN_DIGEST=' .env | cut -d= -f2)"

  if [ -n "${strategyDigest}" ]; then
    local pythonSrc="ghcr.io/learn-trade-org/flash-strategy-runtime@${strategyDigest}"
    echo "==> pulling ${pythonSrc}"
    docker pull "${pythonSrc}"
    docker tag "${pythonSrc}" flash-strategy-runtime:latest
    echo "==> retagged ${pythonSrc} -> flash-strategy-runtime:latest"
  else
    echo "==> WARN FLASH_STRATEGY_DIGEST unset — python strategies will not run"
  fi

  # Bun runtime is best-effort: a box pinned to a version that predates the bun image must still
  # start (python strategies keep working) — only bun strategies wait until it is published.
  if [ -n "${bunDigest}" ]; then
    local bunSrc="ghcr.io/learn-trade-org/flash-strategy-runtime-bun@${bunDigest}"
    echo "==> pulling ${bunSrc}"
    if docker pull "${bunSrc}"; then
      docker tag "${bunSrc}" flash-strategy-runtime-bun:latest
      echo "==> retagged ${bunSrc} -> flash-strategy-runtime-bun:latest"
    else
      echo "==> WARN ${bunSrc} unavailable — bun strategies will not run until it is published"
    fi
  else
    echo "==> WARN FLASH_STRATEGY_BUN_DIGEST unset — bun strategies will not run"
  fi
}

ACTION="${1:-}"

case "$ACTION" in
  start)
    echo "==> Pulling flash images..."
    $COMPOSE pull
    retag_strategy_runtime
    echo "==> Starting flash..."
    $COMPOSE up -d
    echo
    echo "App: http://localhost:${APP_PORT}/   (health: /health)"
    ;;
  stop)
    echo "==> Stopping flash..."
    $COMPOSE down
    ;;
  restart)
    $COMPOSE down
    $COMPOSE pull
    retag_strategy_runtime
    $COMPOSE up -d
    ;;
  pull)
    $COMPOSE pull
    retag_strategy_runtime
    ;;
  logs)
    $COMPOSE logs -f --tail=100
    ;;
  status)
    $COMPOSE ps
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|pull|logs|status}" >&2
    exit 1
    ;;
esac