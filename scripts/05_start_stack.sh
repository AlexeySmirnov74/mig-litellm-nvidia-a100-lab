#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR/compose"

if [[ ! -f ../.env ]]; then
  echo "Missing ../.env. Run scripts/03_export_env.sh first."
  exit 1
fi




echo "Pulling images..."
docker compose --env-file ../.env pull

echo "Building local workload images..."
docker build -t mig-lab-stress-worker:local ../workloads/stress-worker
docker build -t mig-lab-smoke-client:local ../workloads/smoke-client


mkdir -p ../state/prometheus
chown -R 65534:65534 ../state/prometheus || true
chmod -R u+rwX,g+rwX ../state/prometheus || true

mkdir -p ../state/prometheus ../state/grafana
chown -R 65534:65534 ../state/prometheus || true
chown -R 472:472 ../state/grafana || true
chmod -R u+rwX,g+rwX ../state/prometheus ../state/grafana || true




echo "Starting stack..."
docker compose --env-file ../.env up -d

echo "Current status:"
docker compose --env-file ../.env ps

echo "Use 'docker compose --env-file ../.env logs -f <service>' to watch startup logs."
