#!/bin/bash
# framework/collectors/generic/events.sh
#
# Mudanças recentes num repositório git (commits/deploys na janela).
# Uso: ./events.sh --repo <path> [--since-minutes 180]
# Saída: JSON no envelope padrão, com events[] = [{type, sha, timestamp, message}]

set -euo pipefail

REPO="."
SINCE_MIN=180

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           REPO="${2:?}"; shift 2 ;;
    --since-minutes)  SINCE_MIN="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

TS="$(date -u +%s)"
ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

emit_error() {
  jq -n --argjson collected_at "$TS" --arg timestamp "$ISO" \
        --arg error "$1" --arg repo "$REPO" \
    '{collected_at:$collected_at, timestamp:$timestamp, source:"events",
      status:"error", error:$error, repo:$repo}'
  exit 1
}

command -v git >/dev/null 2>&1 || emit_error "git não encontrado"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || emit_error "não é um repositório git: $REPO"

# Um commit por linha, campos separados por "|". Nada de separador invisível
# (byte de controle no fonte é fácil de destruir sem perceber num editor).
# A mensagem pode conter "|": o regex abaixo captura sha e data primeiro e
# joga todo o resto da linha em message.
RAW="$(git -C "$REPO" log --since="${SINCE_MIN} minutes ago" \
        --pretty=format:'%H|%cI|%s' 2>/dev/null || true)"

EVENTS="$(printf '%s' "$RAW" | jq -R -s '
  split("\n")
  | map(select(length > 0))
  | map(select(test("^[0-9a-fA-F]+\\|")))
  | map(capture("^(?<sha>[0-9a-fA-F]+)\\|(?<timestamp>[^|]+)\\|(?<message>.*)$"))
  | map({
      type: "COMMIT",
      sha: .sha[0:8],
      timestamp: .timestamp,
      message: .message
    })')"

jq -n \
  --argjson collected_at "$TS" \
  --arg timestamp "$ISO" \
  --arg repo "$REPO" \
  --argjson since_minutes "$SINCE_MIN" \
  --argjson events "$EVENTS" \
  '{
    collected_at: $collected_at,
    timestamp: $timestamp,
    source: "events",
    repo: $repo,
    since_minutes: $since_minutes,
    count: ($events | length),
    events: $events
  }'
