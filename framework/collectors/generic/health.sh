#!/bin/bash
# framework/collectors/generic/health.sh
#
# Coleta saúde geral do sistema via endpoints de health check
# Uso: ./health.sh [HOST:PORT] [TIMEOUT]
# Saída: JSON estruturado

set -euo pipefail

HOST="${1:-localhost:3000}"
TIMEOUT="${2:-5}"
TIMESTAMP=$(date -u +%s)
TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Health check endpoint (assume GET /health sem auth)
response=$(curl -s -m "$TIMEOUT" "http://$HOST/health" 2>&1 || echo '{"error":"TIMEOUT","message":"No response from endpoint"}')

# Valida JSON
if ! jq . <<< "$response" > /dev/null 2>&1; then
  jq -n \
    --arg host "$HOST" \
    --arg error "INVALID_JSON" \
    --arg response "$response" \
    --arg timestamp "$TIMESTAMP_ISO" \
    '{
      collected_at: '$TIMESTAMP',
      timestamp: $timestamp,
      source: "health-check",
      status: "error",
      error: $error,
      host: $host,
      raw_response: $response
    }'
  exit 1
fi

# Enriquece com timestamp + metadata
jq \
  --arg host "$HOST" \
  --arg timestamp "$TIMESTAMP_ISO" \
  --arg collected_at "$TIMESTAMP" \
  '{
    collected_at: ($collected_at | tonumber),
    timestamp: $timestamp,
    source: "health-check",
    host: $host,
    status: (
      if .status == "healthy" then "ok"
      elif .status == "degraded" then "degraded"
      elif .status == "down" then "down"
      else "unknown"
      end
    ),
    details: .
  }' <<< "$response"

exit 0
