#!/bin/bash
# [01b] Log in to GHCR so the baked flash images (private) can be pulled.
#
# Run by 00_bootstrap.sh, or standalone. Idempotent — skips if a working GHCR
# credential already exists.
#
# Provide the read-only token + username out-of-band (env vars preferred so the
# token never lands in shell history):
#   GHCR_USER=<github-username> GHCR_TOKEN=<read:packages PAT> ./01b_registry_login.sh
# If unset, falls back to an interactive prompt.

set -e

REGISTRY="ghcr.io"

# Already authenticated? (a prior login wrote into ~/.docker/config.json)
if grep -q "${REGISTRY}" "${HOME}/.docker/config.json" 2>/dev/null; then
  echo "==> [01b] ${REGISTRY} credential already present — skipping login"
  exit 0
fi

GHCR_USER="${GHCR_USER:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"

if [ -z "${GHCR_USER}" ]; then
  read -r -p "GHCR username (GitHub user): " GHCR_USER
fi
if [ -z "${GHCR_TOKEN}" ]; then
  read -r -s -p "GHCR read token (read:packages PAT): " GHCR_TOKEN
  echo
fi

echo "==> [01b] logging in to ${REGISTRY} as ${GHCR_USER}"
echo "${GHCR_TOKEN}" | docker login "${REGISTRY}" -u "${GHCR_USER}" --password-stdin

echo "==> [01b] login ok"