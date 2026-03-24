#!/usr/bin/env bash
set -euo pipefail
docker rm -f stress-worker >/dev/null 2>&1 || true
echo "stress-worker stopped"

