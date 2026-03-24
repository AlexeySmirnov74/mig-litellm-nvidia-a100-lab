#!/usr/bin/env bash
set -euo pipefail
docker rm -f text-load >/dev/null 2>&1 || true
echo "text-load stopped"

