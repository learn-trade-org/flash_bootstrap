#!/bin/bash
# Sandbox launcher — runs the PULLED :sandbox stack (flash-app + mongo; broker is in-process).
# Usage: ./launch_sandbox.sh {start|stop|restart|pull|logs|status}

set -e

cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.sandbox.customer.yml"

if [ ! -f .env ]; then
  echo "Missing .env — run flash_bootstrap/02_gen_env_sandbox.sh first" >&2
  exit 1
fi

APP_PORT="$(grep -E '^APP_HOST_PORT=' .env | cut -d= -f2)"
APP_PORT="${APP_PORT:-7200}"

mkdir -p db/mongo db/strategy db/strategy/.logs db/tick db/instrument

# imageForRuntime launches strategy containers by the bare local name
# flash-strategy-runtime-sandbox:latest, so retag the pulled :sandbox image to it.
retag_sandbox_runtime() {
  local sandboxImage="ghcr.io/learn-trade-org/flash-strategy-runtime-sandbox:sandbox"
  echo "==> pulling ${sandboxImage}"
  docker pull "${sandboxImage}"
  docker tag "${sandboxImage}" flash-strategy-runtime-sandbox:latest
  echo "==> retagged ${sandboxImage} -> flash-strategy-runtime-sandbox:latest"
}

ACTION="${1:-}"

case "$ACTION" in
  start)
    $COMPOSE pull
    retag_sandbox_runtime
    $COMPOSE up -d
    echo
    echo "App: http://localhost:${APP_PORT}/   (health: /health)"
    ;;
  stop)
    $COMPOSE down
    ;;
  restart)
    $COMPOSE down
    $COMPOSE pull
    retag_sandbox_runtime
    $COMPOSE up -d
    ;;
  pull)
    $COMPOSE pull
    retag_sandbox_runtime
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
