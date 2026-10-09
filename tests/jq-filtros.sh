#!/bin/bash
# tests/jq-filtros.sh
#
# Roda cada script .sh que usa jq com entrada de exemplo (binários externos
# trocados por stubs) e falha se o jq der erro de compilação/execução ou se a
# saída não for JSON válido. Offline, sem rede, sem crédito.
#
# Uso: tests/jq-filtros.sh        Requisitos: bash, jq, git.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# --- stubs: curl/sqlite3/tailscale/ping/getent devolvem saída fixa ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/bash
printf '%s' "${STUB_CURL:-}"
EOF
cat > "$TMP/bin/sqlite3" <<'EOF'
#!/bin/bash
case "$2" in *integrity*) echo ok ;; *journal*) echo wal ;; *) echo 1 ;; esac
EOF
cat > "$TMP/bin/tailscale" <<'EOF'
#!/bin/bash
echo '100.64.0.1  servidor  linux  -'
EOF
cat > "$TMP/bin/ping" <<'EOF'
#!/bin/bash
echo '64 bytes from 100.64.0.1: icmp_seq=1 ttl=64 time=12.3 ms'
EOF
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/getent"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

: > "$TMP/banco.sqlite"; mkdir -p "$TMP/backups"; : > "$TMP/backups/b1.sqlite"
printf '%s\n' 'INFO ok' 'ERROR falha "aspas" e \barra' 'WARN pool 9/10' > "$TMP/app.log"

# check <nome> <rc esperado> <cmd...>: stdout tem de ser JSON, stderr sem erro de jq.
check() {
  local name="$1" want="$2"; shift 2
  "$@" > "$TMP/out" 2> "$TMP/err"; local rc=$?
  if grep -qE 'jq: (error|[0-9]+ compile error)' "$TMP/err"; then
    echo "FAIL $name: jq quebrou"; sed 's/^/     /' "$TMP/err"; FAIL=$((FAIL+1))
  elif [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: rc=$rc (esperado $want)"; sed 's/^/     /' "$TMP/err"; FAIL=$((FAIL+1))
  elif [[ "${JSON:-1}" == 1 ]] && ! jq -e . "$TMP/out" >/dev/null 2>&1; then
    echo "FAIL $name: saída não é JSON"; head -5 "$TMP/out" | sed 's/^/     /'; FAIL=$((FAIL+1))
  else
    echo "ok   $name"
  fi
}

C="$REPO/examples/sistema-rh/collectors"
G="$REPO/framework/collectors/generic"
F="$REPO/framework"
HEALTH='{"status":"degraded","uptime_seconds":43200,"memory_mb":92,"requests_per_minute":210,"db":"timeout","db_latency_ms":5000,"pool_size":10,"pool_active":10,"pool_waiting":3}'

STUB_CURL="$HEALTH"            check express-health        0 bash "$C/express-health.sh"
STUB_CURL='{"status":"healthy"}' check express-health-minimo 0 bash "$C/express-health.sh"
STUB_CURL='nao e json'         check express-health-erro   1 bash "$C/express-health.sh"
STUB_CURL="$HEALTH"            check health                0 bash "$G/health.sh"
STUB_CURL='nao e json'         check health-erro           1 bash "$G/health.sh"
check sqlite-health        0 bash "$C/sqlite-health.sh" --db "$TMP/banco.sqlite" --backup-dir "$TMP/backups"
check sqlite-health-erro   1 bash "$C/sqlite-health.sh" --db "$TMP/nao-existe.sqlite"
check tailscale-status     0 bash "$C/tailscale-status.sh" --peer servidor
check tailscale-sem-peer   0 bash "$C/tailscale-status.sh"
check events               0 bash "$G/events.sh" --repo "$REPO" --since-minutes 100000000
check events-erro          1 bash "$G/events.sh" --repo "$TMP"
check logs                 0 bash "$G/logs.sh" --file "$TMP/app.log"
check logs-erro            1 bash "$G/logs.sh"
check metrics              0 bash "$G/metrics.sh" /
check correlator-mock      0 bash "$F/correlator.sh" --manifest "$REPO/examples/sistema-rh/collectors.manifest.json" \
                                 --mock-dir "$REPO/examples/sistema-rh/mock-signals"
# analyzer/executor/test-analyzer imprimem texto (prompt, relatório): só checa jq + rc.
for fx in "$REPO"/examples/sistema-rh/test-incidents/case-*.json; do
  [[ "$fx" == *.expected.json ]] && continue
  JSON=0 check "analyzer-dry-run $(basename "$fx")" 0 bash "$F/analyzer.sh" --incident-file "$fx" --dry-run
done
for act in clear-cache increase-pool; do
  JSON=0 check "executor-dry-run $act" 0 bash "$F/executor.sh" --action "$act"
done
JSON=0 check test-analyzer-offline 0 bash "$F/test-analyzer.sh"

echo
if (( FAIL > 0 )); then echo "$FAIL falha(s)."; exit 1; fi
echo "todos os filtros jq ok."
