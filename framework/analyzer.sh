#!/bin/bash
# framework/analyzer.sh
#
# Analyzer do AIOps: pega um incidente (JSON do correlator), monta o prompt
# especializado e — se autorizado — chama o Claude para diagnosticar + propor ações.
#
# SEGURO POR PADRÃO: roda em --dry-run (monta e imprime o prompt, NÃO chama a API).
# Só toca a rede com --execute explícito.
#
# Uso:
#   ./analyzer.sh --incident-file <path> [opções]
#
# Opções:
#   --incident-file <path>        (obrigatório) JSON do incidente
#   --system <nome>               default: sistema-rh  (procura examples/<nome>/analyzer.md)
#   --confidence-threshold <n>    default: 0.70  (abaixo disso, não recomenda ação)
#   --model <id>                  default: claude-opus-4-8
#   --output <path>               salva a saída (em vez de stdout)
#   --dry-run                     (PADRÃO) imprime prompt + request; não chama a API
#   --execute                     opt-in: chama a API (exige ANTHROPIC_API_KEY)
#   -h | --help
#
# Requisitos: jq, curl (só no --execute).

set -euo pipefail

# --- Resolve caminhos relativos a este script (funciona de qualquer cwd) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Defaults ---
INCIDENT_FILE=""
SYSTEM="sistema-rh"
CONFIDENCE_THRESHOLD="0.70"
MODEL="claude-opus-4-8"
OUTPUT=""
MODE="dry-run"        # dry-run | execute
MAX_TOKENS=8000

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# --- Parse de argumentos ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --incident-file) INCIDENT_FILE="${2:?}"; shift 2 ;;
    --system) SYSTEM="${2:?}"; shift 2 ;;
    --confidence-threshold) CONFIDENCE_THRESHOLD="${2:?}"; shift 2 ;;
    --model) MODEL="${2:?}"; shift 2 ;;
    --output) OUTPUT="${2:?}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --execute) MODE="execute"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; usage 1 ;;
  esac
done

# --- Validações ---
command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }
[[ -n "$INCIDENT_FILE" ]] || { echo "ERRO: --incident-file é obrigatório." >&2; usage 1; }
[[ -f "$INCIDENT_FILE" ]] || { echo "ERRO: incidente não encontrado: $INCIDENT_FILE" >&2; exit 1; }
jq empty "$INCIDENT_FILE" 2>/dev/null || { echo "ERRO: incidente não é JSON válido." >&2; exit 1; }

TEMPLATE="$REPO_DIR/framework/analyzer-template.prompt"
SPECIALIZED="$REPO_DIR/examples/$SYSTEM/analyzer.md"
[[ -f "$TEMPLATE" ]] || { echo "ERRO: template não encontrado: $TEMPLATE" >&2; exit 1; }
[[ -f "$SPECIALIZED" ]] || { echo "ERRO: prompt especializado não encontrado: $SPECIALIZED" >&2; exit 1; }

# --- Monta o prompt (template genérico + especializado + incidente) ---
PROMPT_TEXT="$(cat "$TEMPLATE")

$(cat "$SPECIALIZED")

## Parâmetros desta análise
- confidence_threshold: $CONFIDENCE_THRESHOLD  (se a confiança do diagnóstico ficar abaixo disso, retorne actions: [] e peça mais dados)

## Incidente

$(jq -c . "$INCIDENT_FILE")"

# --- Monta o corpo da requisição (Messages API) ---
# Contrato do claude-api skill: POST /v1/messages, adaptive thinking + effort high
# para tarefa de análise. Saída JSON é instruída no prompt e extraída do bloco text.
REQUEST="$(jq -n \
  --arg model "$MODEL" \
  --argjson max_tokens "$MAX_TOKENS" \
  --arg content "$PROMPT_TEXT" \
  '{
    model: $model,
    max_tokens: $max_tokens,
    thinking: { type: "adaptive" },
    output_config: { effort: "high" },
    messages: [ { role: "user", content: $content } ]
  }')"

# ============================ DRY-RUN (padrão) ============================
if [[ "$MODE" == "dry-run" ]]; then
  echo "=== DRY-RUN — nada foi enviado à API ===" >&2
  echo "--- PROMPT MONTADO ---" >&2
  printf '%s\n' "$PROMPT_TEXT"
  echo "--- REQUEST BODY (seria enviado a POST /v1/messages) ---" >&2
  printf '%s\n' "$REQUEST" | jq .
  echo "=== Para rodar de verdade: repita com --execute (exige ANTHROPIC_API_KEY) ===" >&2
  exit 0
fi

# ============================ EXECUTE (opt-in) ===========================
: "${ANTHROPIC_API_KEY:?ERRO: --execute exige ANTHROPIC_API_KEY no ambiente (Lukas rotaciona contas via /login).}"
command -v curl >/dev/null 2>&1 || { echo "ERRO: curl não encontrado." >&2; exit 1; }

RESPONSE="$(curl -s https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d "$REQUEST")"

# Erro da API vem como {"type":"error",...} com HTTP 200 em alguns casos — checa.
if [[ "$(jq -r '.type // empty' <<<"$RESPONSE")" == "error" ]]; then
  echo "ERRO da API:" >&2
  jq '.error' <<<"$RESPONSE" >&2
  exit 1
fi

# Extrai o bloco de texto (pula blocos de thinking) e valida como JSON.
DIAGNOSIS="$(jq -r '.content[] | select(.type=="text") | .text' <<<"$RESPONSE")"
if ! jq empty <<<"$DIAGNOSIS" 2>/dev/null; then
  echo "AVISO: a saída do modelo não é JSON puro. Bruto abaixo:" >&2
  printf '%s\n' "$DIAGNOSIS"
  exit 2
fi

if [[ -n "$OUTPUT" ]]; then
  jq . <<<"$DIAGNOSIS" > "$OUTPUT"
  echo "Diagnóstico salvo em: $OUTPUT" >&2
else
  jq . <<<"$DIAGNOSIS"
fi
