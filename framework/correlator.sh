#!/bin/bash
# framework/correlator.sh
#
# Junta as saídas dos coletores num único JSON de incidente que o analyzer consome.
# Dirigido por um manifesto (examples/<sistema>/collectors.manifest.json).
#
# Uso:
#   ./correlator.sh --manifest <path> [--mock-dir <dir>] [--output <path>]
#
#   --manifest <path>   (obrigatório) mapeia signals -> coletores
#   --mock-dir <dir>    lê saídas de coletor pré-gravadas (offline, sem rede) em vez de rodar
#   --output <path>     salva o incidente (default: stdout)
#
# A falha de um coletor NÃO derruba o resto — o slot recebe um JSON de erro e segue.
# Requisitos: jq (e os coletores/rede só no modo ao vivo).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST=""
MOCK_DIR=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?}"; shift 2 ;;
    --mock-dir) MOCK_DIR="${2:?}"; shift 2 ;;
    --output)   OUTPUT="${2:?}"; shift 2 ;;
    -h|--help)  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }
[[ -n "$MANIFEST" ]] || { echo "ERRO: --manifest é obrigatório." >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "ERRO: manifesto não encontrado: $MANIFEST" >&2; exit 1; }
jq empty "$MANIFEST" 2>/dev/null || { echo "ERRO: manifesto não é JSON válido." >&2; exit 1; }

# --- Janela e id do incidente ---
WINDOW_MIN="$(jq -r '.window_minutes // 3' "$MANIFEST")"
NOW_TS="$(date -u +%s)"
NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
WIN_START="$(date -u -d "@$(( NOW_TS - WINDOW_MIN * 60 ))" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
             || date -u -r "$(( NOW_TS - WINDOW_MIN * 60 ))" +"%Y-%m-%dT%H:%M:%SZ")"
RAND="$(head -c2 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F' | cut -c1-3)"
[[ -n "$RAND" ]] || RAND="000"
INCIDENT_ID="INC-$(date -u +%Y-%m-%d)-$RAND"

# --- Envelope base ---
INCIDENT="$(jq -n \
  --arg id "$INCIDENT_ID" --arg ts "$NOW_ISO" --arg ws "$WIN_START" --arg we "$NOW_ISO" \
  '{incident:{id:$id, timestamp:$ts, window:{start:$ws, end:$we}}, symptoms:[], signals:{}}')"

# --- Um slot de cada vez ---
error_signal() { # $1=slot $2=detalhe
  jq -n --arg source "$1" --arg detail "$2" \
    '{source:$source, status:"error", error:$detail}'
}

while IFS= read -r SLOT; do
  CONTENT=""
  if [[ -n "$MOCK_DIR" ]]; then
    MOCK_FILE="$(jq -r ".signals.\"$SLOT\".mock // empty" "$MANIFEST")"
    if [[ -n "$MOCK_FILE" && -f "$MOCK_DIR/$MOCK_FILE" ]]; then
      CONTENT="$(cat "$MOCK_DIR/$MOCK_FILE")"
    else
      CONTENT="$(error_signal "$SLOT" "mock não encontrado: $MOCK_DIR/$MOCK_FILE")"
    fi
  else
    COLLECTOR_REL="$(jq -r ".signals.\"$SLOT\".sh.collector // empty" "$MANIFEST")"
    COLLECTOR="$REPO_DIR/$COLLECTOR_REL"
    if [[ -z "$COLLECTOR_REL" || ! -x "$COLLECTOR" && ! -f "$COLLECTOR" ]]; then
      CONTENT="$(error_signal "$SLOT" "coletor ausente: $COLLECTOR_REL")"
    else
      mapfile -t ARGS < <(jq -r ".signals.\"$SLOT\".sh.args[]? // empty" "$MANIFEST")
      CONTENT="$(bash "$COLLECTOR" "${ARGS[@]}" 2>/dev/null || true)"
    fi
  fi

  # Se o conteúdo não for JSON válido, embrulha como erro (não quebra o incidente).
  if ! jq empty <<<"$CONTENT" 2>/dev/null; then
    CONTENT="$(error_signal "$SLOT" "saída do coletor não é JSON")"
  fi

  INCIDENT="$(jq --arg slot "$SLOT" --argjson content "$CONTENT" \
                '.signals[$slot] = $content' <<<"$INCIDENT")"
done < <(jq -r '.signals | keys[]' "$MANIFEST")

if [[ -n "$OUTPUT" ]]; then
  jq . <<<"$INCIDENT" > "$OUTPUT"
  echo "Incidente salvo em: $OUTPUT" >&2
else
  jq . <<<"$INCIDENT"
fi
