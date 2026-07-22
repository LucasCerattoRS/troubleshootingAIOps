#!/bin/bash
# examples/sistema-rh/collectors/tailscale-status.sh
#
# Conectividade com o servidor da empresa via Tailscale: estado da VPN,
# latência de ping e resolução DNS.
#
# Uso: ./tailscale-status.sh [--peer <hostname-ou-ip>]
# Saída: JSON no envelope padrão de coletor.

set -euo pipefail

PEER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer) PEER="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

TS="$(date -u +%s)"
ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

# --- Estado do Tailscale ---
TAILSCALE="unknown"
if command -v tailscale >/dev/null 2>&1; then
  if OUT="$(tailscale status 2>&1)"; then
    if grep -qiE 'logged out|stopped' <<<"$OUT"; then
      TAILSCALE="offline"
    else
      TAILSCALE="connected"
    fi
  else
    TAILSCALE="offline"
  fi
else
  TAILSCALE="not_installed"
fi

# --- Ping e DNS do peer (só se um peer foi informado) ---
PING_MS=null
PING_RESULT=null
DNS=null

if [[ -n "$PEER" ]]; then
  if command -v ping >/dev/null 2>&1 && \
     PING_OUT="$(ping -c 1 -W 2 "$PEER" 2>/dev/null)"; then
    MS="$(sed -n 's/.*time=\([0-9.]*\).*/\1/p' <<<"$PING_OUT" | head -1)"
    if [[ -n "${MS:-}" ]]; then PING_MS="$MS"; fi
    PING_RESULT='"ok"'
  else
    PING_RESULT='"no response"'
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$PEER" >/dev/null 2>&1; then DNS='"ok"'; else DNS='"SERVFAIL"'; fi
  elif command -v nslookup >/dev/null 2>&1; then
    if nslookup "$PEER" >/dev/null 2>&1; then DNS='"ok"'; else DNS='"SERVFAIL"'; fi
  fi
fi

jq -n \
  --argjson collected_at "$TS" \
  --arg timestamp "$ISO" \
  --arg tailscale "$TAILSCALE" \
  --arg peer "$PEER" \
  --argjson ping_ms "$PING_MS" \
  --argjson ping_result "$PING_RESULT" \
  --argjson dns "$DNS" \
  '{
    collected_at: $collected_at,
    timestamp: $timestamp,
    source: "tailscale-status",
    tailscale: $tailscale,
    peer: (if $peer == "" then null else $peer end),
    ping_ms: $ping_ms,
    ping_result: $ping_result,
    dns: $dns
  }'
