#!/bin/bash
# framework/collectors/generic/metrics.sh
#
# Coleta métricas de sistema: CPU, memória e disco.
# Uso: ./metrics.sh [MOUNT]        (MOUNT default: /)
# Saída: JSON no envelope padrão de coletor.
#
# Linux-first (/proc). Em SO sem /proc, os campos viram null em vez de quebrar.

set -euo pipefail

MOUNT="${1:-/}"
TS="$(date -u +%s)"
ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

# --- CPU: dois samples de /proc/stat com 0.2s de intervalo ---
cpu_percent=null
if [[ -r /proc/stat ]]; then
  read -r _ u1 n1 s1 i1 _ < /proc/stat
  t1=$(( u1 + n1 + s1 + i1 ))
  sleep 0.2
  read -r _ u2 n2 s2 i2 _ < /proc/stat
  t2=$(( u2 + n2 + s2 + i2 ))
  dt=$(( t2 - t1 )); di=$(( i2 - i1 ))
  if (( dt > 0 )); then cpu_percent=$(( (100 * (dt - di)) / dt )); fi
fi

# --- Memória: /proc/meminfo (usado = total - disponível) ---
mem_percent=null
if [[ -r /proc/meminfo ]]; then
  total="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
  avail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
  if [[ -n "${total:-}" && -n "${avail:-}" ]] && (( total > 0 )); then
    mem_percent=$(( (100 * (total - avail)) / total ))
  fi
fi

# --- Disco: df do mount pedido ---
disk_percent="$(df -P "$MOUNT" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')"
[[ -n "${disk_percent:-}" ]] || disk_percent=null

jq -n \
  --argjson collected_at "$TS" \
  --arg timestamp "$ISO" \
  --arg mount "$MOUNT" \
  --argjson cpu_percent "$cpu_percent" \
  --argjson memory_percent "$mem_percent" \
  --argjson disk_percent "$disk_percent" \
  '{
    collected_at: $collected_at,
    timestamp: $timestamp,
    source: "metrics",
    mount: $mount,
    cpu_percent: $cpu_percent,
    memory_percent: $memory_percent,
    disk_percent: $disk_percent
  }'
