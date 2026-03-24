#!/usr/bin/env bash
set -euo pipefail

cd ./scripts


LOAD_USERS=50
LOAD_DURATION_SEC=180
LOAD_THINK_TIME_SEC=0.2
LOAD_MODEL_MODE=all


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
fi

LOAD_USERS="${LOAD_USERS:-10}"
LOAD_DURATION_SEC="${LOAD_DURATION_SEC:-120}"
LOAD_THINK_TIME_SEC="${LOAD_THINK_TIME_SEC:-0.5}"
LOAD_MODEL_MODE="${LOAD_MODEL_MODE:-all}"
LOAD_MAX_TOKENS="${LOAD_MAX_TOKENS:-64}"

echo "Rebuilding text-load image..."
docker build -t mig-lab-text-load:local ./workloads/text-load

echo "Stopping old text-load container if exists..."
docker rm -f text-load >/dev/null 2>&1 || true

echo "Starting text load test..."
echo "  users=${LOAD_USERS}"
echo "  duration=${LOAD_DURATION_SEC}s"
echo "  think_time=${LOAD_THINK_TIME_SEC}s"
echo "  model_mode=${LOAD_MODEL_MODE}"
echo "  max_tokens=${LOAD_MAX_TOKENS}"

docker run -d \
  --name text-load \
  --restart=no \
  --network compose_default \
  -e LOAD_API_BASE="http://context-guard:4010/v1" \
  -e LOAD_API_KEY="${OPENAI_API_KEY:-dummy-local-key}" \
  -e LOAD_USERS="${LOAD_USERS}" \
  -e LOAD_DURATION_SEC="${LOAD_DURATION_SEC}" \
  -e LOAD_THINK_TIME_SEC="${LOAD_THINK_TIME_SEC}" \
  -e LOAD_MODEL_MODE="${LOAD_MODEL_MODE}" \
  -e LOAD_MAX_TOKENS="${LOAD_MAX_TOKENS}" \
  mig-lab-text-load:local

echo
echo "text-load started."
echo "Watch logs with:"
echo "  docker logs -f text-load"
echo
echo "Stop with:"
echo "  ./10_stop_text_load.sh"

