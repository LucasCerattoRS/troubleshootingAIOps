#!/bin/bash
# examples/sistema-rh/actions/safe/clear-cache.sh
#
# Ação SEGURA (reversível): invalida o cache da aplicação. O cache se reconstrói
# sob demanda, então o "rollback" é no-op.
# Modos: --describe | --run | --rollback
#
# ⚠ PRÉ-REQUISITO: depende do endpoint POST /api/admin/cache/clear, que NÃO existe
#   hoje no Sistema RH (ver actions/README.md).

set -euo pipefail

MODE=""
HOST="localhost:3000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --describe|--run|--rollback) MODE="$1"; shift ;;
    --host) HOST="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  --describe)
    cat <<'JSON'
{
  "id": "clear-cache",
  "reversible": true,
  "requires_approval": false,
  "requires_backup_first": false,
  "windows_admin_required": false,
  "command": "POST /api/admin/cache/clear",
  "rollback": "no-op (o cache se reconstroi sob demanda)",
  "prerequisite": "endpoint /api/admin/cache/clear ainda NAO existe no Sistema RH (ver actions/README.md)"
}
JSON
    ;;
  --run)
    : "${RH_TOKEN:?ERRO: RH_TOKEN necessário.}"
    command -v curl >/dev/null 2>&1 || { echo "ERRO: curl não encontrado." >&2; exit 1; }
    curl -fsS -X POST "http://$HOST/api/admin/cache/clear" \
      -H "Authorization: Bearer $RH_TOKEN" >/dev/null
    echo "cache invalidado"
    ;;
  --rollback)
    echo "rollback no-op (cache reconstrói sob demanda)"
    ;;
  *)
    echo "ERRO: use --describe | --run | --rollback" >&2; exit 1 ;;
esac
