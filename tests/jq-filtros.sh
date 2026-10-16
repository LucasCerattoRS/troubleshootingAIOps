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
printf "%s" "${STUB_CURL:-}"; exit "${STUB_CURL_RC:-0}"
EOF
cat > "$TMP/bin/sqlite3" <<'EOF'
#!/bin/bash
case "$2" in
  *integrity*) echo "${STUB_SQLITE_INTEGRITY:-ok}" ;;
  *journal*)   echo "${STUB_SQLITE_JOURNAL:-wal}" ;;
  *)           echo 1 ;;
esac
EOF
cat > "$TMP/bin/tailscale" <<'EOF'
#!/bin/bash
echo "${STUB_TS_OUT:-100.64.0.1  servidor  linux  -}"; exit "${STUB_TS_RC:-0}"
EOF
cat > "$TMP/bin/ping" <<'EOF'
#!/bin/bash
[[ "${STUB_PING_RC:-0}" == 0 ]] || exit "$STUB_PING_RC"
echo '64 bytes from 100.64.0.1: icmp_seq=1 ttl=64 time=12.3 ms'
EOF
printf '#!/bin/bash\nexit "${STUB_GETENT_RC:-0}"\n' > "$TMP/bin/getent"
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

# expect <nome> <rc> <esperado.json> <cmd...>: confere VALORES, não só sintaxe.
# Após tirar collected_at/timestamp (validados à parte: número e ISO-8601) e os
# campos de $DEL (paths jq, ex. '.latency_ms'), a saída tem de ser IGUAL ao
# esperado. $CHK = expressão jq extra (jq -e) sobre a saída completa, p/ campos
# voláteis (latência, métricas do host).
expect() {
  local name="$1" want="$2" exp="$3"; shift 3
  "$@" > "$TMP/out" 2> "$TMP/err"; local rc=$?
  local del=""; [[ -n "${DEL:-}" ]] && del=",$DEL"
  local got wantj
  got="$(jq -S "del(.collected_at,.timestamp$del)" "$TMP/out" 2>/dev/null)"
  wantj="$(jq -S . <<<"$exp")"
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: rc=$rc (esperado $want)"; sed 's/^/     /' "$TMP/err"; FAIL=$((FAIL+1))
  elif ! jq -e '(.collected_at|type)=="number" and (.timestamp|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$TMP/out" >/dev/null 2>&1; then
    echo "FAIL $name: collected_at/timestamp fora do formato"; FAIL=$((FAIL+1))
  elif [[ "$got" != "$wantj" ]]; then
    echo "FAIL $name: valores diferentes"; diff <(echo "$wantj") <(echo "$got") | sed 's/^/     /'; FAIL=$((FAIL+1))
  elif [[ -n "${CHK:-}" ]] && ! jq -e "$CHK" "$TMP/out" >/dev/null 2>&1; then
    echo "FAIL $name: checagem '$CHK' falhou"; head -c 400 "$TMP/out" | sed 's/^/     /'; FAIL=$((FAIL+1))
  else
    echo "ok   $name (valores)"
  fi
}

C="$REPO/examples/sistema-rh/collectors"
G="$REPO/framework/collectors/generic"
F="$REPO/framework"
HEALTH='{"status":"degraded","uptime_seconds":43200,"memory_mb":92,"requests_per_minute":210,"db":"timeout","db_latency_ms":5000,"pool_size":10,"pool_active":10,"pool_waiting":3}'

STUB_CURL="$HEALTH"            check express-health        0 bash "$C/express-health.sh"
STUB_CURL='{"status":"healthy"}' check express-health-minimo 0 bash "$C/express-health.sh"
STUB_CURL='nao e json'         check express-health-erro   1 bash "$C/express-health.sh"
STUB_CURL_RC=7                 check express-health-offline 1 bash "$C/express-health.sh"
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

# ===================== asserções de VALOR (regressão, não só sintaxe) =====================
FX="$REPO/tests/fixtures"
HDEG="$(cat "$FX/health-degraded.json")"

STUB_CURL="$HDEG" expect v-express-degraded 0 '{
  "source":"express-health","host":"localhost:3000","status":"degraded",
  "uptime_seconds":43200,"memory_mb":92,"requests_per_minute":210,
  "db":{"status":"timeout","latency_ms":5000,"pool":{"size":10,"active":10,"waiting":3}}}' \
  bash "$C/express-health.sh"
# pool_waiting ausente => 0; "healthy" => "ok"; host vem do argumento
STUB_CURL="$(cat "$FX/health-healthy-minimo.json")" expect v-express-minimo 0 '{
  "source":"express-health","host":"app:8080","status":"ok",
  "uptime_seconds":60,"memory_mb":40,"requests_per_minute":5,
  "db":{"status":"ok","latency_ms":3,"pool":{"size":10,"active":1,"waiting":0}}}' \
  bash "$C/express-health.sh" app:8080
STUB_CURL='{"status":"banana"}' DEL='.db,.uptime_seconds,.memory_mb,.requests_per_minute' \
  expect v-express-unknown 0 '{"source":"express-health","host":"localhost:3000","status":"unknown"}' \
  bash "$C/express-health.sh"
STUB_CURL='nao e json' expect v-express-erro 1 '{
  "source":"express-health","status":"error",
  "error":"Health endpoint unreachable or invalid JSON","details":{"raw":"nao e json"}}' \
  bash "$C/express-health.sh"

STUB_CURL="$HDEG" expect v-health-degraded 0 "{
  \"source\":\"health-check\",\"host\":\"localhost:3000\",\"status\":\"degraded\",\"details\":$HDEG}" \
  bash "$G/health.sh"
STUB_CURL='{"status":"down"}' expect v-health-down 0 '{
  "source":"health-check","host":"h:1","status":"down","details":{"status":"down"}}' \
  bash "$G/health.sh" h:1
STUB_CURL='{"status":"x"}' DEL='.details' expect v-health-unknown 0 \
  '{"source":"health-check","host":"localhost:3000","status":"unknown"}' bash "$G/health.sh"
STUB_CURL='lixo' expect v-health-invalido 1 '{
  "source":"health-check","status":"error","error":"INVALID_JSON",
  "host":"localhost:3000","raw_response":"lixo"}' bash "$G/health.sh"

# sqlite-health: banco de 3 MB, backup mais novo com 5h
truncate -s 3M "$TMP/banco3.sqlite"; mkdir -p "$TMP/bk"
: > "$TMP/bk/velho.sqlite"; touch -d '3 days ago' "$TMP/bk/velho.sqlite"
: > "$TMP/bk/novo.sqlite";  touch -d '5 hours ago' "$TMP/bk/novo.sqlite"
DEL='.latency_ms,.last_backup_at' CHK='(.latency_ms|type)=="number" and (.last_backup_at|test("^[0-9]{4}-.*Z$"))' \
  expect v-sqlite-ok 0 '{
  "source":"sqlite-health","integrity_check":"ok","journal_mode":"wal",
  "file_size_mb":3,"last_backup_age_hours":5}' \
  bash "$C/sqlite-health.sh" --db "$TMP/banco3.sqlite" --backup-dir "$TMP/bk"
STUB_SQLITE_INTEGRITY='database disk image is malformed' STUB_SQLITE_JOURNAL=delete \
  DEL='.latency_ms,.last_backup_at' expect v-sqlite-corrompido 0 '{
  "source":"sqlite-health","integrity_check":"database disk image is malformed",
  "journal_mode":"delete","file_size_mb":3,"last_backup_age_hours":5}' \
  bash "$C/sqlite-health.sh" --db "$TMP/banco3.sqlite" --backup-dir "$TMP/bk"
DEL='.latency_ms' expect v-sqlite-sem-backup 0 '{
  "source":"sqlite-health","integrity_check":"ok","journal_mode":"wal","file_size_mb":3,
  "last_backup_at":null,"last_backup_age_hours":null}' \
  bash "$C/sqlite-health.sh" --db "$TMP/banco3.sqlite" --backup-dir "$TMP/nao-existe"
expect v-sqlite-erro 1 "{\"source\":\"sqlite-health\",\"status\":\"error\",
  \"error\":\"banco não encontrado: $TMP/x.sqlite\",\"db\":\"$TMP/x.sqlite\"}" \
  bash "$C/sqlite-health.sh" --db "$TMP/x.sqlite"

# tailscale-status
expect v-tailscale-ok 0 '{"source":"tailscale-status","tailscale":"connected","peer":"servidor",
  "ping_ms":12.3,"ping_result":"ok","dns":"ok"}' bash "$C/tailscale-status.sh" --peer servidor
STUB_TS_OUT='Logged out.' STUB_TS_RC=1 expect v-tailscale-offline 0 '{"source":"tailscale-status",
  "tailscale":"offline","peer":null,"ping_ms":null,"ping_result":null,"dns":null}' \
  bash "$C/tailscale-status.sh"
STUB_TS_OUT='Tailscale is stopped.' expect v-tailscale-stopped 0 '{"source":"tailscale-status",
  "tailscale":"offline","peer":null,"ping_ms":null,"ping_result":null,"dns":null}' \
  bash "$C/tailscale-status.sh"
STUB_PING_RC=1 STUB_GETENT_RC=2 expect v-tailscale-peer-caido 0 '{"source":"tailscale-status",
  "tailscale":"connected","peer":"servidor","ping_ms":null,"ping_result":"no response","dns":"SERVFAIL"}' \
  bash "$C/tailscale-status.sh" --peer servidor

# events: repo temporário com commits conhecidos (mensagem com "|" e aspas)
GR="$TMP/repo"; mkdir -p "$GR"; git -C "$GR" init -q
gc() { git -C "$GR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "$1"; }
gc 'deploy 1.2.1'; gc 'fix: a | b "c"'
SHA1="$(git -C "$GR" rev-parse HEAD~1 | cut -c1-8)"; SHA2="$(git -C "$GR" rev-parse HEAD | cut -c1-8)"
DEL='.events[].timestamp' expect v-events 0 "{
  \"source\":\"events\",\"repo\":\"$GR\",\"since_minutes\":60,\"count\":2,
  \"events\":[{\"type\":\"COMMIT\",\"sha\":\"$SHA2\",\"message\":\"fix: a | b \\\"c\\\"\"},
              {\"type\":\"COMMIT\",\"sha\":\"$SHA1\",\"message\":\"deploy 1.2.1\"}]}" \
  bash "$G/events.sh" --repo "$GR" --since-minutes 60
expect v-events-erro 1 "{\"source\":\"events\",\"status\":\"error\",
  \"error\":\"não é um repositório git: $TMP/naorepo\",\"repo\":\"$TMP/naorepo\"}" \
  bash "$G/events.sh" --repo "$TMP/naorepo"

# logs: só ERROR/WARN entram; --lines corta pelo fim; --pattern troca o filtro
printf '%s\n' 'INFO ok' 'ERROR falha "aspas" e \barra' 'WARN pool 9/10' 'INFO fim' > "$TMP/l.log"
expect v-logs 0 "{\"source\":\"logs\",\"file\":\"$TMP/l.log\",\"lines_scanned\":100,\"matched\":2,
  \"logs\":[{\"level\":\"ERROR\",\"message\":\"ERROR falha \\\"aspas\\\" e \\\\barra\",\"timestamp\":null},
            {\"level\":\"WARN\",\"message\":\"WARN pool 9/10\",\"timestamp\":null}]}" \
  bash "$G/logs.sh" --file "$TMP/l.log"
expect v-logs-lines 0 "{\"source\":\"logs\",\"file\":\"$TMP/l.log\",\"lines_scanned\":2,\"matched\":1,
  \"logs\":[{\"level\":\"WARN\",\"message\":\"WARN pool 9/10\",\"timestamp\":null}]}" \
  bash "$G/logs.sh" --file "$TMP/l.log" --lines 2
expect v-logs-pattern 0 "{\"source\":\"logs\",\"file\":\"$TMP/l.log\",\"lines_scanned\":100,\"matched\":2,
  \"logs\":[{\"level\":\"INFO\",\"message\":\"INFO ok\",\"timestamp\":null},
            {\"level\":\"INFO\",\"message\":\"INFO fim\",\"timestamp\":null}]}" \
  bash "$G/logs.sh" --file "$TMP/l.log" --pattern INFO
printf 'INFO tudo certo\n' > "$TMP/limpo.log"
expect v-logs-limpo 0 "{\"source\":\"logs\",\"file\":\"$TMP/limpo.log\",\"lines_scanned\":100,\"matched\":0,\"logs\":[]}" \
  bash "$G/logs.sh" --file "$TMP/limpo.log"
expect v-logs-erro 1 '{"source":"logs","status":"error","error":"--file é obrigatório","file":""}' \
  bash "$G/logs.sh"

# metrics: valores do host variam; confere tipo e faixa 0..100
CHK='all(.cpu_percent,.memory_percent,.disk_percent; type=="number" and .>=0 and .<=100)' \
  DEL='.cpu_percent,.memory_percent,.disk_percent' expect v-metrics 0 '{"source":"metrics","mount":"/"}' \
  bash "$G/metrics.sh" /

# correlator (mock): cada slot do incidente tem de ser exatamente o JSON do mock correspondente
MD="$REPO/examples/sistema-rh/mock-signals"
corr() { bash "$F/correlator.sh" --manifest "$REPO/examples/sistema-rh/collectors.manifest.json" --mock-dir "$1"; }
corr "$MD" > "$TMP/inc.json" 2>/dev/null
for pair in application:express-health database:sqlite-health events:events network:tailscale-status system:metrics; do
  slot="${pair%%:*}"; mock="${pair##*:}"
  if jq -e --slurpfile m "$MD/$mock.json" --arg s "$slot" '.signals[$s] == $m[0]' "$TMP/inc.json" >/dev/null 2>&1; then
    echo "ok   v-correlator slot $slot == $mock.json"
  else
    echo "FAIL v-correlator slot $slot difere de $mock.json"; FAIL=$((FAIL+1))
  fi
done
if jq -e '(.incident.id|test("^INC-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9A-F]{3}$")) and (.symptoms==[]) and ((.signals|keys)==["application","database","events","network","system"])' "$TMP/inc.json" >/dev/null 2>&1; then
  echo "ok   v-correlator envelope"; else echo "FAIL v-correlator envelope"; FAIL=$((FAIL+1)); fi
# coletor ausente não derruba o resto: o slot vira erro e os outros seguem
cp -r "$MD" "$TMP/mock2"; rm "$TMP/mock2/metrics.json"
corr "$TMP/mock2" > "$TMP/inc2.json" 2>/dev/null
if jq -e '.signals.system.status=="error" and .signals.application.source=="express-health"' "$TMP/inc2.json" >/dev/null 2>&1; then
  echo "ok   v-correlator slot ausente vira erro"; else echo "FAIL v-correlator slot ausente"; FAIL=$((FAIL+1)); fi

echo
if (( FAIL > 0 )); then echo "$FAIL falha(s)."; exit 1; fi
echo "todos os filtros jq ok."
