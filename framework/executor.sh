#!/bin/bash
# framework/executor.sh
#
# Executa uma AÇÃO SEGURA proposta pelo analyzer, com os gates de segurança lidos
# da própria ação (--describe). SEGURO POR PADRÃO: roda em dry-run.
#
# Uso:
#   ./executor.sh --action <id> [--system sistema-rh] [--execute] [--confirm]
#                 [--skip-backup] [-- <args da ação>]
#
#   --action <id>    (obrigatório) script em examples/<system>/actions/safe/<id>.sh
#   --system <nome>  default: sistema-rh
#   --dry-run        (PADRÃO) mostra o que rodaria + o rollback + os gates; não executa
#   --execute        opt-in: roda a ação de verdade
#   --confirm        libera ações com requires_approval:true
#   --skip-backup    libera ações com requires_backup_first:true (assumindo backup feito)
#   -- <args>        tudo depois de -- é repassado à ação (ex.: --size 20 --old 10)
#
# O analyzer PROPÕE; um humano escolhe a ação e roda isto. É o humano no loop.
# Requisitos: jq. curl só quando a própria ação chamar a API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SYSTEM="sistema-rh"
ACTION=""
MODE="dry-run"
CONFIRM=0
SKIP_BACKUP=0
FWD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="${2:?}"; shift 2 ;;
    --system) SYSTEM="${2:?}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --execute) MODE="execute"; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --skip-backup) SKIP_BACKUP=1; shift ;;
    --) shift; FWD=("$@"); break ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }
[[ -n "$ACTION" ]] || { echo "ERRO: --action é obrigatório." >&2; exit 1; }

SCRIPT="$REPO_DIR/examples/$SYSTEM/actions/safe/$ACTION.sh"
[[ -f "$SCRIPT" ]] || { echo "ERRO: ação não encontrada: $SCRIPT" >&2; exit 1; }

DESC="$(bash "$SCRIPT" --describe 2>/dev/null || true)"
jq empty <<<"$DESC" 2>/dev/null || { echo "ERRO: --describe da ação não retornou JSON." >&2; exit 1; }

get() { jq -r "$1 // empty" <<<"$DESC"; }
REVERSIBLE="$(get .reversible)"
REQ_APPROVAL="$(get .requires_approval)"
REQ_BACKUP="$(get .requires_backup_first)"
WIN_ADMIN="$(get .windows_admin_required)"
COMMAND="$(get .command)"
ROLLBACK="$(get .rollback)"
PREREQ="$(get .prerequisite)"

AUDIT_LOG="${AIOPS_LOG:-aiops.log}"
NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
audit() { # $1=result $2=rc
  jq -n -c --arg at "$NOW_ISO" --arg action "$ACTION" --arg result "$1" --argjson rc "${2:-0}" \
    '{at:$at, action:$action, mode:"execute", result:$result, rc:$rc}' >> "$AUDIT_LOG"
}

# ============================ DRY-RUN (padrão) ============================
if [[ "$MODE" == "dry-run" ]]; then
  echo "=== DRY-RUN — nada foi executado ===" >&2
  cat <<EOF
Ação:                 $ACTION
Reversível:           $REVERSIBLE
Requer aprovação:     $REQ_APPROVAL   (--confirm)
Requer backup antes:  $REQ_BACKUP     (--skip-backup)
Requer admin Windows: $WIN_ADMIN
Comando que rodaria:  $COMMAND
Rollback:             $ROLLBACK
EOF
  [[ -n "$PREREQ" ]] && echo "⚠ Pré-requisito:      $PREREQ"
  echo "Para rodar: repita com --execute (+ --confirm/--skip-backup se exigidos)." >&2
  exit 0
fi

# ============================ EXECUTE (opt-in) ===========================
# Gate: aprovação
if [[ "$REQ_APPROVAL" == "true" && "$CONFIRM" -eq 0 ]]; then
  echo "RECUSADO: ação exige aprovação. Rode de novo com --confirm." >&2; exit 3
fi
# Gate: backup
if [[ "$REQ_BACKUP" == "true" && "$SKIP_BACKUP" -eq 0 ]]; then
  echo "RECUSADO: ação exige backup antes. Faça o backup e use --skip-backup." >&2; exit 3
fi
# Gate: admin (no bash só avisamos; a elevação real é assunto do .ps1 no Windows)
if [[ "$WIN_ADMIN" == "true" ]]; then
  echo "AVISO: esta ação espera privilégio de admin no Windows." >&2
fi

echo "Executando: $ACTION ..." >&2
if bash "$SCRIPT" --run "${FWD[@]}"; then
  audit "success" 0
  echo "OK: $ACTION concluída." >&2
else
  RC=$?
  echo "FALHOU (rc=$RC). Tentando rollback..." >&2
  if bash "$SCRIPT" --rollback "${FWD[@]}"; then
    audit "rolled-back" "$RC"
    echo "Rollback OK." >&2
  else
    audit "rollback-failed" "$RC"
    echo "ROLLBACK FALHOU — intervenção manual necessária." >&2
    exit 1
  fi
fi
