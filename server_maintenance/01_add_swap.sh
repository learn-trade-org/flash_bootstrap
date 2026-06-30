#!/bin/bash
# Add a 4 GB swapfile on low-RAM droplets so memory-heavy ops (instrument refresh loads ~170k rows
# ×3) don't OOM. Idempotent: skips if swap is already active or the box already has >= ~2 GB RAM.
set -euo pipefail

SWAPFILE="/swapfile"
SWAP_SIZE_GB=4

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "==> [swap] already active — skipping"
  exit 0
fi

echo "==> [swap] adding ${SWAP_SIZE_GB} GB swapfile at ${SWAPFILE}"
$SUDO fallocate -l "${SWAP_SIZE_GB}G" "${SWAPFILE}" 2>/dev/null || $SUDO dd if=/dev/zero of="${SWAPFILE}" bs=1M count=$((SWAP_SIZE_GB*1024)) status=none
$SUDO chmod 600 "${SWAPFILE}"
$SUDO mkswap "${SWAPFILE}" >/dev/null
$SUDO swapon "${SWAPFILE}"

# Persist across reboot.
if ! grep -q "^${SWAPFILE} " /etc/fstab 2>/dev/null; then
  echo "${SWAPFILE} none swap sw 0 0" | $SUDO tee -a /etc/fstab >/dev/null
fi

# Prefer RAM; use swap only as a safety net.
$SUDO sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
if ! grep -q "^vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
  echo "vm.swappiness=10" | $SUDO tee -a /etc/sysctl.conf >/dev/null
fi

echo "==> [swap] ${SWAP_SIZE_GB} GB swap active + persisted"
