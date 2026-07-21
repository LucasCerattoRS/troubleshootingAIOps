#!/bin/bash
# examples/sistema-rh/collectors/express-health.sh
#
# Coleta saúde do Express RH: endpoint /health
# Retorna status do servidor, pool de DB, memória, uptime
#
# Uso: ./express-health.sh [HOST:PORT]
# Saída: JSON

set -euo pipefail

HOST="${1:-localhost:3000}"
TIMEOUT=5
TIMESTAMP=$(date -u +%s)
TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Health check — deve ser rapidinho
response=$(curl -s -m "$TIMEOUT" "http://$HOST/health" 2>&1)

# Se não foi JSON válido
if ! jq empty <<< "$response" 2>/dev/null; then
  jq -n \
    --arg timestamp "$TIMESTAMP_ISO" \
    --arg error "$response" \
    '{
      collected_at: '$TIMESTAMP',
      timestamp: $timestamp,
      source: "express-health",
      status: "error",
      error: "Health endpoint unreachable or invalid JSON",
      details: { raw: $error }
    }'
  exit 1
fi

# Normaliza response
jq \
  --arg collected_at "$TIMESTAMP" \
  --arg timestamp "$TIMESTAMP_ISO" \
  --arg host "$HOST" \
  '{
    collected_at: ($collected_at | tonumber),
    timestamp: $timestamp,
    source: "express-health",
    host: $host,
    status: (
      if .status == "healthy" then "ok"
      elif .status == "degraded" then "degraded"
      else "unknown"
      end
    ),
    uptime_seconds: .uptime_seconds,
    memory_mb: .memory_mb,
    requests_per_minute: .requests_per_minute,
    db: {
      status: .db,
      latency_ms: .db_latency_ms,
      pool: {
        size: .pool_size,
        active: .pool_active,
        waiting: (.pool_active - .pool_size // 0)  // safe calc
      }
    }
  }' <<< "$response"

exit 0
