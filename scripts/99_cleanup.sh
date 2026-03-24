#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR/compose"

docker compose --env-file ../.env down -v || true
docker rm -f stress-worker >/dev/null 2>&1 || true

echo "Optionally destroy MIG layout with: sudo nvidia-smi mig -dci -i 0 && sudo nvidia-smi mig -dgi -i 0"
