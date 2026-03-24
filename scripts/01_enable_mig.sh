#!/usr/bin/env bash
set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/01_enable_mig.sh"
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi not found"
  exit 2
fi

echo "Checking current MIG mode..."
CURRENT=$(nvidia-smi -i "$GPU_INDEX" --query-gpu=mig.mode.current --format=csv,noheader | tr -d ' ')
echo "Current MIG mode: $CURRENT"

if [[ "$CURRENT" == "Enabled" ]]; then
  echo "MIG already enabled on GPU $GPU_INDEX"
  exit 0
fi

echo "Stopping any Docker containers that may hold the GPU..."
docker ps -q | xargs -r docker stop || true

echo "Enabling MIG on GPU $GPU_INDEX..."
if nvidia-smi -i "$GPU_INDEX" -mig 1; then
  echo "MIG enable command completed"
else
  echo "MIG enable command failed. A reboot may be required on this host."
  exit 3
fi

sleep 2
AFTER=$(nvidia-smi -i "$GPU_INDEX" --query-gpu=mig.mode.current --format=csv,noheader | tr -d ' ' || true)
echo "Current MIG mode after command: ${AFTER:-unknown}"

if [[ "$AFTER" != "Enabled" ]]; then
  echo "MIG mode is not enabled yet. Reboot the host and run this script again."
  exit 4
fi

echo "MIG is enabled on GPU $GPU_INDEX"
