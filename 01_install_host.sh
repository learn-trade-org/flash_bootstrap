#!/bin/bash
# [01] Install host prereqs + docker on a bare Ubuntu/Debian droplet.
#
# Run by 00_bootstrap.sh, or standalone. Uses sudo only when not already root
# (DO droplets log in as root; sudo is a no-op there).
#
# get.docker.com installs the docker engine AND the compose v2 plugin
# (`docker compose`), so no separate compose install is needed.

set -e

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

echo "==> [01] installing host prereqs"
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends ca-certificates curl

echo "==> [01] installing docker"
if command -v docker >/dev/null 2>&1; then
  echo "    docker already present — skipping"
else
  curl -fsSL https://get.docker.com | $SUDO sh
fi

echo "==> [01] done ($(docker --version))"