#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${BASE_URL:-http://localhost:4000/v1}
KEY=${OPENAI_API_KEY:-dummy-local-key}

for model in general-chat fast-chat tiny-chat; do
  echo "Testing $model"
  curl -fsS "$BASE_URL/chat/completions" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}],\"max_tokens\":64}" | jq -r '.choices[0].message.content'
done
