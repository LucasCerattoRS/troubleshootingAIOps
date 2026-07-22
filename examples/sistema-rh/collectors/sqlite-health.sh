#!/bin/bash
# examples/sistema-rh/collectors/sqlite-health.sh
#
# Saúde do banco.sqlite do Sistema RH: integridade, journal mode, tamanho,
# latência de uma query trivial e idade do último backup.
#
# Uso: ./sqlite-health.sh [--db banco.sqlite] [--backup-dir backups]
# Saída: JSON no envelope padrão de coletor.

set -euo pipefail

DB="banco.sqlite"
BACKUP_DIR="backups"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)         DB="${2:?}"; shift 2 ;;
    --backup-dir) BACKUP_DIR="${2:?}"; shift 2 ;;
    *) echo "ERRO: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

TS="$(date -u +%s)"
ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado." >&2; exit 1; }

emit_error() {
  jq -n --argjson collected_at "$TS" --arg timestamp "$ISO" \
        --arg error "$1" --arg db "$DB" \
    '{collected_at:$collected_at, timestamp:$timestamp, source:"sqlite-health",
      status:"error", error:$error, db:$db}'
  exit 1
}

command -v sqlite3 >/dev/null 2>&1 || emit_error "sqlite3 não encontrado (instale o CLI do SQLite)"
[[ -f "$DB" ]] || emit_error "banco não encontrado: $DB"

# --- Integridade e journal mode ---
INTEGRITY="$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>&1 | head -1 || echo "unknown")"
JOURNAL="$(sqlite3 "$DB" "PRAGMA journal_mode;" 2>&1 | head -1 || echo "unknown")"

# --- Tamanho do arquivo (GNU stat, com fallback BSD) ---
BYTES="$(stat -c %s "$DB" 2>/dev/null || stat -f %z "$DB" 2>/dev/null || echo 0)"
SIZE_MB=$(( BYTES / 1048576 ))

# --- Latência de uma query trivial ---
LATENCY_MS=null
if command -v date >/dev/null 2>&1; then
  T0="$(date +%s%3N 2>/dev/null || echo "")"
  sqlite3 "$DB" "SELECT 1;" >/dev/null 2>&1 || true
  T1="$(date +%s%3N 2>/dev/null || echo "")"
  if [[ -n "$T0" && -n "$T1" && "$T0" != *N* && "$T1" != *N* ]]; then
    LATENCY_MS=$(( T1 - T0 ))
  fi
fi

# --- Último backup ---
LAST_BACKUP_AT=null
LAST_BACKUP_AGE_H=null
if [[ -d "$BACKUP_DIR" ]]; then
  NEWEST="$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -1 || true)"
  if [[ -n "${NEWEST:-}" ]]; then
    BPATH="$BACKUP_DIR/$NEWEST"
    BEPOCH="$(stat -c %Y "$BPATH" 2>/dev/null || stat -f %m "$BPATH" 2>/dev/null || echo "")"
    if [[ -n "${BEPOCH:-}" ]]; then
      LAST_BACKUP_AT="\"$(date -u -d "@$BEPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
                          || date -u -r "$BEPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)\""
      LAST_BACKUP_AGE_H=$(( (TS - BEPOCH) / 3600 ))
    fi
  fi
fi

jq -n \
  --argjson collected_at "$TS" \
  --arg timestamp "$ISO" \
  --arg integrity_check "$INTEGRITY" \
  --arg journal_mode "$JOURNAL" \
  --argjson file_size_mb "$SIZE_MB" \
  --argjson latency_ms "$LATENCY_MS" \
  --argjson last_backup_at "$LAST_BACKUP_AT" \
  --argjson last_backup_age_hours "$LAST_BACKUP_AGE_H" \
  '{
    collected_at: $collected_at,
    timestamp: $timestamp,
    source: "sqlite-health",
    integrity_check: $integrity_check,
    journal_mode: $journal_mode,
    file_size_mb: $file_size_mb,
    latency_ms: $latency_ms,
    last_backup_at: $last_backup_at,
    last_backup_age_hours: $last_backup_age_hours
  }'
