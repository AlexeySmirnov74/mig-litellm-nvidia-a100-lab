#!/usr/bin/env bash
set -euo pipefail

GPU_ID="${GPU_ID:-0}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1"
    exit 1
  }
}

need_cmd nvidia-smi
need_cmd docker
need_cmd awk
need_cmd grep
need_cmd sed

echo "Stopping Docker containers before MIG reconfiguration..."
docker ps -q | xargs -r docker stop >/dev/null 2>&1 || true

echo "Checking MIG mode..."
MIG_MODE="$(nvidia-smi -i "${GPU_ID}" --query-gpu=mig.mode.current --format=csv,noheader | tr -d '[:space:]')"
echo "Current MIG mode: ${MIG_MODE}"

if [[ "${MIG_MODE}" != "Enabled" ]]; then
  echo "ERROR: MIG mode is not enabled on GPU ${GPU_ID}."
  echo "Run ./01_enable_mig.sh first."
  exit 1
fi

echo "Destroying existing compute instances on GPU ${GPU_ID}..."
nvidia-smi mig -i "${GPU_ID}" -dci >/dev/null 2>&1 || true

echo "Destroying existing GPU instances on GPU ${GPU_ID}..."
nvidia-smi mig -i "${GPU_ID}" -dgi >/dev/null 2>&1 || true

echo "Reading available MIG GPU instance profiles..."
PROFILE_TABLE="$(nvidia-smi mig -lgip)"

echo "${PROFILE_TABLE}"

extract_profile_id() {
  local profile_name="$1"
  echo "${PROFILE_TABLE}" | awk -v target="MIG ${profile_name}" '
    index($0, target) {
      for (i = 1; i <= NF; i++) {
        if ($i == target || ($i == "MIG" && $(i+1) == substr(target, 5))) {
          for (j = i; j <= NF; j++) {
            if ($(j) == "ID") {
              print $(j+1)
              exit
            }
          }
        }
      }
    }
  '
}

# More robust fallback parser for typical nvidia-smi table rows:
extract_profile_id_fallback() {
  local profile_name="$1"
  echo "${PROFILE_TABLE}" | awk -v target="${profile_name}" '
    $0 ~ target {
      # Typical row example:
      # |   0  MIG 3g.20gb          9     2/2 ...
      for (i = 1; i <= NF; i++) {
        if ($i == "MIG" && $(i+1) == target) {
          print $(i+2)
          exit
        }
      }
    }
  '
}

PROFILE_3G="$(extract_profile_id "3g.20gb" || true)"
PROFILE_2G="$(extract_profile_id "2g.10gb" || true)"
PROFILE_1G="$(extract_profile_id "1g.5gb"  || true)"

if [[ -z "${PROFILE_3G}" ]]; then
  PROFILE_3G="$(extract_profile_id_fallback "3g.20gb" || true)"
fi
if [[ -z "${PROFILE_2G}" ]]; then
  PROFILE_2G="$(extract_profile_id_fallback "2g.10gb" || true)"
fi
if [[ -z "${PROFILE_1G}" ]]; then
  PROFILE_1G="$(extract_profile_id_fallback "1g.5gb" || true)"
fi

# Safe defaults for NVIDIA A100 40GB
PROFILE_3G="${PROFILE_3G:-9}"
PROFILE_2G="${PROFILE_2G:-14}"
PROFILE_1G="${PROFILE_1G:-19}"

echo
echo "Resolved profile IDs:"
echo "  3g.20gb -> ${PROFILE_3G}"
echo "  2g.10gb -> ${PROFILE_2G}"
echo "  1g.5gb  -> ${PROFILE_1G}"
echo

if ! [[ "${PROFILE_3G}" =~ ^[0-9]+$ && "${PROFILE_2G}" =~ ^[0-9]+$ && "${PROFILE_1G}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: failed to resolve one or more MIG profile IDs."
  exit 1
fi

LAYOUT="${PROFILE_3G},${PROFILE_2G},${PROFILE_1G},${PROFILE_1G}"

echo "Creating MIG layout on GPU ${GPU_ID}: 3g.20gb + 2g.10gb + 1g.5gb + 1g.5gb"
echo "Using profile IDs: ${LAYOUT}"

nvidia-smi mig -i "${GPU_ID}" -cgi "${LAYOUT}" -C

echo
echo "Created GPU instances:"
nvidia-smi mig -i "${GPU_ID}" -lgi

echo
echo "Created compute instances:"
nvidia-smi mig -i "${GPU_ID}" -lci

echo
echo "Done."
echo "Next step: run ./03_export_env.sh"
