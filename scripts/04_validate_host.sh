#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo ".env not found. Run scripts/03_export_env.sh first."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

for v in MIG_GENERAL_UUID MIG_FAST_UUID MIG_TINY_UUID MIG_STRESS_UUID; do
  if [[ -z "${!v:-}" ]]; then
    echo "$v is empty"
    exit 2
  fi
done

echo "Host GPU list:"
nvidia-smi -L

echo
echo "Testing Docker access to each MIG UUID..."
for uuid in "$MIG_GENERAL_UUID" "$MIG_FAST_UUID" "$MIG_TINY_UUID" "$MIG_STRESS_UUID"; do
  echo "  -> $uuid"
  docker run --rm --runtime=nvidia \
    -e NVIDIA_VISIBLE_DEVICES="$uuid" \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    nvidia/cuda:12.4.1-base-ubuntu22.04 \
    nvidia-smi -L
  echo
done

echo "Host validation finished successfully."
