#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
EXAMPLE_FILE="$ROOT_DIR/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
fi

mapfile -t MIG_LINES < <(nvidia-smi -L | grep '^  MIG ' || true)
if [[ ${#MIG_LINES[@]} -lt 4 ]]; then
  echo "Expected at least 4 MIG devices, found ${#MIG_LINES[@]}"
  nvidia-smi -L
  exit 1
fi

pick_uuid() {
  local pattern="$1"
  local skip="${2:-0}"
  printf '%s\n' "${MIG_LINES[@]}" | grep "$pattern" | sed -n "$((skip+1))p" | sed -E 's/.*UUID: (MIG-[^)]+)\).*/\1/'
}

GENERAL_UUID=$(pick_uuid '3g\.20gb')
FAST_UUID=$(pick_uuid '2g\.10gb')
TINY_UUID=$(pick_uuid '1g\.5gb' 0)
STRESS_UUID=$(pick_uuid '1g\.5gb' 1)

for var in GENERAL_UUID FAST_UUID TINY_UUID STRESS_UUID; do
  if [[ -z "${!var}" ]]; then
    echo "Failed to detect $var from nvidia-smi -L"
    nvidia-smi -L
    exit 2
  fi
done

update_or_append() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i -E "s#^${key}=.*#${key}=${value}#" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

update_or_append MIG_GENERAL_UUID "$GENERAL_UUID"
update_or_append MIG_FAST_UUID "$FAST_UUID"
update_or_append MIG_TINY_UUID "$TINY_UUID"
update_or_append MIG_STRESS_UUID "$STRESS_UUID"

echo "Updated $ENV_FILE with detected MIG UUIDs:"
grep '^MIG_' "$ENV_FILE"
