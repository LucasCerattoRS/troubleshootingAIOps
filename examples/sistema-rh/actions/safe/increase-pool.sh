#!/bin/bash
# examples/sistema-rh/actions/safe/increase-pool.sh
#
# Ação SEGURA (reversível): aumenta o pool de conexões do Sistema RH.
# Modos: --describe (metadados p/ o executor) | --run | --rollback
#   --run:      define o pool para --size (default 20)
#   --rollback: volta o pool para --old (default 10)
#
# ⚠ PRÉ-REQUISITO: depende do endpoint POST /api/admin/pool-size, que NÃO existe
#   hoje no Sistema RH (ver actions/README.md). O --run só funciona depois de
#   implementá-lo lá. --describe e o dry-run do executor funcionam sem ele.

set -euo pipefail

MODE=""
SIZE=20
OLD=10
HOST="localhost:3000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --describe|--run|--rollback) MODE="$1"; shift ;;
    --size) SIZE="${2:?}"; shift 2 ;;
    --old)  OLD="${2:?}"; shift 2 ;;
    --host) HOST="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  --describe)
    # JSON estático — não depende de jq.
    cat <<'JSON'
{
  "id": "increase-pool",
  "reversible": true,
  "requires_approval": false,
  "requires_backup_first": false,
  "windows_admin_required": false,
  "command": "POST /api/admin/pool-size {size: N}",
  "rollback": "POST /api/admin/pool-size {size: OLD}",
  "prerequisite": "endpoint /api/admin/pool-size ainda NAO existe no Sistema RH (ver actions/README.md)"
}
JSON
    ;;
  --run)
    : "${RH_TOKEN:?ERRO: RH_TOKEN necessário para a chamada admin.}"
    command -v curl >/dev/null 2>&1 || { echo "ERRO: curl não encontrado." >&2; exit 1; }
    curl -fsS -X POST "http://$HOST/api/admin/pool-size" \
      -H "Authorization: Bearer $RH_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"size\": $SIZE}" >/dev/null
    # Verifica pós-condição pelo /health.
    CUR="$(curl -fsS "http://$HOST/health" | sed -n 's/.*"pool_size":[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
    [[ "$CUR" == "$SIZE" ]] || { echo "ERRO: pool ainda é $CUR (esperado $SIZE)." >&2; exit 1; }
    echo "pool -> $SIZE"
    ;;
  --rollback)
    : "${RH_TOKEN:?ERRO: RH_TOKEN necessário.}"
    curl -fsS -X POST "http://$HOST/api/admin/pool-size" \
      -H "Authorization: Bearer $RH_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"size\": $OLD}" >/dev/null
    echo "pool revertido -> $OLD"
    ;;
  *)
    echo "ERRO: use --describe | --run | --rollback" >&2; exit 1 ;;
esac
