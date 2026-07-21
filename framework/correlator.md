# Correlator — Juntando Sinais em Contexto

## O que é

O Correlator **lê outputs de múltiplos coletores** e os transforma em um **JSON estruturado único** que representa o estado do sistema em um momento.

Não é apenas "aqui está log, aqui está métrica" — é uma **correlação automática** que agrupa sinais relacionados por tempo e contexto.

## Estrutura de Entrada

Cada coletor retorna JSON estruturado:

```bash
./collectors/generic/health.sh
{
  "collected_at": 1721576000,
  "source": "health-check",
  "status": "degraded",
  "details": {...}
}
```

## Estrutura de Saída

Correlator **junta tudo** em um modelo único de incidente:

```json
{
  "incident": {
    "id": "INC-2026-07-21-A7F",
    "timestamp": "2026-07-21T14:23:45Z",
    "window": {
      "start": "2026-07-21T14:20:45Z",
      "end": "2026-07-21T14:23:45Z"
    }
  },
  
  "symptoms": [
    {
      "type": "API_ERROR",
      "endpoint": "/api/dados",
      "status_code": 500,
      "error_rate": 15,
      "started_at": "2026-07-21T14:23:12Z"
    }
  ],
  
  "signals": {
    "application": { ... },      // Logs da app
    "system": { ... },           // CPU, mem, disco
    "database": { ... },         // Pool, latency, health
    "network": { ... },          // VPN, latency, connectivity
    "events": [ ... ]            // Deploys recentes
  },
  
  "correlations": [
    {
      "signals": ["db_latency=5s", "pool_active=10", "error_spike"],
      "likely_cause": "Database pool exhausted",
      "confidence": 0.95,
      "supporting_evidence": [...]
    }
  ]
}
```

## Implementação

### Passo 1: Coletar todos os sinais (em paralelo)

```bash
#!/bin/bash
# framework/correlator.sh

set -euo pipefail

INCIDENT_ID="INC-$(date +%Y-%m-%d)-$(uuidgen | cut -c1-3)"
NOW=$(date -u +%s)
WINDOW_START=$(( NOW - 180 ))  # últimos 3 minutos

# Roda coletores em paralelo (mais rápido)
logs=$(./collectors/application/logs.sh 2>&1 || echo '{}') &
metrics=$(./collectors/system/metrics.sh 2>&1 || echo '{}') &
health=$(./collectors/application/health.sh 2>&1 || echo '{}') &
events=$(./collectors/system/events.sh 2>&1 || echo '{}') &

# Aguarda todos
wait

echo "✓ Logs collected"
echo "✓ Metrics collected"
echo "✓ Health collected"
echo "✓ Events collected"
```

### Passo 2: Estruturar sinais por categoria

```bash
# Reúne sinais de mesmo tipo
app_signals=$(jq -n \
  --argjson logs "$logs" \
  --argjson health "$health" \
  '{logs: $logs, health: $health}')

system_signals=$(jq -n \
  --argjson metrics "$metrics" \
  '{metrics: $metrics}')

event_signals=$(jq -n \
  --argjson events "$events" \
  '{events: $events}')
```

### Passo 3: Correlacionar sinais

```bash
# Junta tudo + identifica padrões
jq -n \
  --arg incident_id "$INCIDENT_ID" \
  --arg timestamp "$NOW" \
  --argjson signals "{app: $app_signals, system: $system_signals, events: $event_signals}" \
  '{
    incident: {
      id: $incident_id,
      timestamp: $timestamp,
      window: {
        start: $WINDOW_START | todate,
        end: $timestamp | todate
      }
    },
    signals: $signals,
    correlations: [
      # Identifica padrões comuns
      if ($signals.app.health.status == "degraded" and 
          $signals.system.metrics.db_latency_ms > 1000) then
        {
          pattern: "database-latency-spike",
          confidence: 0.95,
          affected: "API /api/dados"
        }
      else empty end
    ]
  }'
```

## Validação

Correlator **valida** JSON antes de passar adiante:

```bash
correlator_output=$(./framework/correlator.sh)

# Verifica se é JSON válido
if ! jq empty <<< "$correlator_output"; then
  echo "ERROR: Invalid JSON from correlator"
  exit 1
fi

# Verifica campos obrigatórios
if ! jq '.incident.id' <<< "$correlator_output" > /dev/null; then
  echo "ERROR: Missing incident.id"
  exit 1
fi

echo "✓ Correlation valid"
```

## Saída para Analyzer

Correlator passa JSON pro Analyzer via stdin ou arquivo:

```bash
./framework/correlator.sh | ./framework/analyzer.sh

# ou

correlation_file="/tmp/incident-$(date +%s).json"
./framework/correlator.sh > "$correlation_file"
./framework/analyzer.sh < "$correlation_file"
```

## Template Mínimo

Nem todo correlator precisa ser complexo. Template mínimo para começar:

```bash
#!/bin/bash
# framework/correlator-simple.sh

set -euo pipefail

jq -n \
  --arg incident_id "INC-$(date +%Y%m%d-%H%M%S)" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg status "investigating" \
  '{
    incident: {
      id: $incident_id,
      timestamp: $timestamp,
      status: $status
    },
    signals: {
      collected_at: $timestamp,
      data: "to-be-filled-by-coletores"
    }
  }'
```

## Checklist de Implementação

- [ ] Cada collector retorna JSON válido
- [ ] Correlator cria `incident.id` único
- [ ] Correlator agrupa sinais por tipo
- [ ] Validação de JSON antes de output
- [ ] Logging (echo progress, não no JSON)
- [ ] Timeout pra coletores lentos
- [ ] Fallback se um coletor falha (não bloqueia tudo)

## Debug

```bash
# Ver correlator output human-readable
./framework/correlator.sh | jq '.'

# Ver um campo específico
./framework/correlator.sh | jq '.signals.system.metrics'

# Salvar pra análise depois
./framework/correlator.sh > /tmp/incident-debug.json
jq '.' /tmp/incident-debug.json
```
