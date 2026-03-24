#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
else
  echo "ERROR: .env not found at ${ROOT_DIR}/.env"
  exit 1
fi

if [[ -z "${MIG_STRESS_UUID:-}" ]]; then
  echo "ERROR: MIG_STRESS_UUID is not set in .env"
  exit 1
fi

echo "Rebuilding stress worker image..."
docker build -t mig-lab-stress-worker:local ./workloads/stress-worker

echo "Stopping old stress container if exists..."
docker rm -f stress-worker >/dev/null 2>&1 || true

echo "Starting OOM demo on MIG_STRESS_UUID=${MIG_STRESS_UUID}"

docker run -d \
  --name stress-worker \
  --restart=no \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES="${MIG_STRESS_UUID}" \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  -e STRESS_DTYPE=float16 \
  -e STRESS_STEP_MIB=128 \
  -e STRESS_SLEEP_SEC=2 \
  -e STRESS_HOLD_AFTER_OOM_SEC=15 \
  mig-lab-stress-worker:local

echo
echo "Stress worker started."
echo "Watch logs with:"
echo "  docker logs -f stress-worker"
echo
echo "Watch status with:"
echo "  docker ps -a | grep stress-worker || true"

