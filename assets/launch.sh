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
mkdir -p db/mongo db/strategy db/strategy/.logs db/tick db/instrument

# The backend launches strategy containers by the FIXED local name
# `flash-strategy-runtime:latest` (container_high_level.ts). The pulled image is
# tagged with the GHCR path, so retag it to the name the backend expects.
retag_strategy_runtime() {
  local ver
  ver="$(grep -E '^FLASH_VERSION=' .env | cut -d= -f2)"
  ver="${ver:-latest}"

  # Both runtimes are launched ad-hoc by the backend via the docker socket, so they are NOT
  # compose services and `compose pull` never fetches them — pull + retag them here.
  local python_src="ghcr.io/learn-trade-org/flash-strategy-runtime:${ver}"
  echo "==> pulling ${python_src}"
  docker pull "${python_src}"
  docker tag "${python_src}" flash-strategy-runtime:latest
  echo "==> retagged ${python_src} -> flash-strategy-runtime:latest"

  # Bun runtime is best-effort: a box pinned to a version that predates the bun image must still
  # start (python strategies keep working) — only bun strategies wait until it is published.
  local bun_src="ghcr.io/learn-trade-org/flash-strategy-runtime-bun:${ver}"
  echo "==> pulling ${bun_src}"
  if docker pull "${bun_src}"; then
    docker tag "${bun_src}" flash-strategy-runtime-bun:latest
    echo "==> retagged ${bun_src} -> flash-strategy-runtime-bun:latest"
  else
    echo "==> WARN ${bun_src} unavailable — bun strategies will not run until it is published"
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