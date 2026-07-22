#!/bin/bash
# framework/test-analyzer.sh
#
# Test runner do analyzer. Par do test-analyzer.ps1.
#
#   Offline (padrão, sem crédito): valida cada fixture + golden como JSON e roda o
#     analyzer em dry-run, conferindo que o prompt monta.
#   --execute (gasta crédito, opt-in): roda o analyzer de verdade e compara a saída
#     com o golden POR CAMPO (não diff literal).
#
# Uso: ./test-analyzer.sh [--system sistema-rh] [--execute] [--threshold 0.15]
# Requisitos: jq. (curl só no --execute, via analyzer.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SYSTEM="sistema-rh"
EXECUTE=0
THRESHOLD="0.15"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)    SYSTEM="${2:?}"; shift 2 ;;
    --execute)   EXECUTE=1; shift ;;
    --threshold) THRESHOLD="${2:?}"; shift 2 ;;
    -h|--help)   sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

ANALYZER="$REPO_DIR/framework/analyzer.sh"
DIR="$REPO_DIR/examples/$SYSTEM/test-incidents"
[[ -d "$DIR" ]] || { echo "ERRO: sem test-incidents: $DIR" >&2; exit 1; }

PASS=0; FAIL=0
if [[ "$EXECUTE" -eq 1 ]]; then echo "== test-analyzer :: EXECUTE (gasta crédito) =="; else echo "== test-analyzer :: OFFLINE (dry-run, sem crédito) =="; fi

for FX in "$DIR"/case-*.json; do
  [[ "$FX" == *.expected.json ]] && continue
  NAME="$(basename "$FX" .json)"
  GOLDEN="$DIR/$NAME.expected.json"
  CHECKS=()

  jq empty "$FX" 2>/dev/null && CHECKS+=("fixture-json") || CHECKS+=("FAIL:fixture-json")
  if [[ -f "$GOLDEN" ]] && jq empty "$GOLDEN" 2>/dev/null; then CHECKS+=("golden-json"); else CHECKS+=("FAIL:golden"); fi

  if [[ "$EXECUTE" -eq 0 ]]; then
    DRY="$(bash "$ANALYZER" --incident-file "$FX" 2>/dev/null || true)"
    if grep -q '## Incidente' <<<"$DRY" && grep -q '"model"' <<<"$DRY"; then
      CHECKS+=("dry-run-builds"); else CHECKS+=("FAIL:dry-run-builds"); fi
  else
    OUT="$(bash "$ANALYZER" --incident-file "$FX" --execute 2>/dev/null || true)"
    if jq empty <<<"$OUT" 2>/dev/null; then
      RC="$(jq -r '.diagnosis.root_cause // empty' <<<"$OUT")"
      [[ -n "$RC" ]] && CHECKS+=("root_cause") || CHECKS+=("FAIL:root_cause")
      OC="$(jq -r '.diagnosis.confidence' <<<"$OUT")"
      GC="$(jq -r '.diagnosis.confidence' "$GOLDEN")"
      if awk -v a="$OC" -v b="$GC" -v t="$THRESHOLD" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}'; then
        CHECKS+=("confidence"); else CHECKS+=("FAIL:confidence"); fi
      OCAT="$(jq -r '.actions[0].category // empty' <<<"$OUT")"
      GCAT="$(jq -r '.actions[0].category // empty' "$GOLDEN")"
      [[ -n "$OCAT" && "$OCAT" == "$GCAT" ]] && CHECKS+=("action1-category") || CHECKS+=("FAIL:action1-category")
      jq -e '.diagnosis and .impact and .actions' <<<"$OUT" >/dev/null 2>&1 && CHECKS+=("shape") || CHECKS+=("FAIL:shape")
    else
      CHECKS+=("FAIL:execute-json")
    fi
  fi

  if printf '%s\n' "${CHECKS[@]}" | grep -q '^FAIL:'; then
    FAIL=$((FAIL+1)); echo "FAIL  $NAME   [$(printf '%s\n' "${CHECKS[@]}" | grep '^FAIL:' | paste -sd, -)]"
  else
    PASS=$((PASS+1)); echo "PASS  $NAME   [$(IFS=,; echo "${CHECKS[*]}")]"
  fi
done

echo "== resultado: $PASS PASS / $FAIL FAIL =="
[[ "$FAIL" -eq 0 ]]
