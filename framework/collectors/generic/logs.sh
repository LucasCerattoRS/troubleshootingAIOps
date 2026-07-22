#!/bin/bash
# framework/collectors/generic/logs.sh
#
# Extrai as linhas de ERROR/WARN das últimas N linhas de um arquivo de log.
# Uso: ./logs.sh --file <path> [--lines 100] [--pattern 'ERROR|WARN']
# Saída: JSON no envelope padrão, com logs[] = [{level, message, timestamp}]
#
# Escapamento é feito por jq (-R -s): mensagens podem conter aspas e barras
# sem quebrar o JSON.

set -euo pipefail

FILE=""
LINES=100
PATTERN='ERROR|WARN'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)    FILE="${2:?}"; shift 2 ;;
    --lines)   LINES="${2:?}"; shift 2 ;;
    --pattern) PATTERN="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

TS="$(date -u +%s)"
ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

emit_error() {
  jq -n --argjson collected_at "$TS" --arg timestamp "$ISO" \
        --arg error "$1" --arg file "$FILE" \
    '{collected_at:$collected_at, timestamp:$timestamp, source:"logs",
      status:"error", error:$error, file:$file}'
  exit 1
}

[[ -n "$FILE" ]] || emit_error "--file é obrigatório"
[[ -f "$FILE" ]] || emit_error "arquivo de log não encontrado: $FILE"

# tail + filtro; `|| true` porque grep sai 1 quando não casa nada (log limpo).
RAW="$(tail -n "$LINES" "$FILE" 2>/dev/null | grep -E "$PATTERN" || true)"

LOGS="$(printf '%s' "$RAW" | jq -R -s '
  split("\n")
  | map(select(length > 0))
  | map({
      level: (if test("ERROR") then "ERROR" elif test("WARN") then "WARN" else "INFO" end),
      message: .,
      timestamp: null
    })')"

jq -n \
  --argjson collected_at "$TS" \
  --arg timestamp "$ISO" \
  --arg file "$FILE" \
  --argjson lines_scanned "$LINES" \
  --argjson logs "$LOGS" \
  '{
    collected_at: $collected_at,
    timestamp: $timestamp,
    source: "logs",
    file: $file,
    lines_scanned: $lines_scanned,
    matched: ($logs | length),
    logs: $logs
  }'
