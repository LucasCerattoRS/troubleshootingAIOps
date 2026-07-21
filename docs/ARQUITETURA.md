# Arquitetura — Os 4 Pilares do AIOps

## Visão Geral

Um fluxo AIOps é uma cadeia de processamento que *coleta* sinais, *organiza* contexto, *analisa* com IA e *executa* ações. Cada pilar é independente mas conectado.

```
[1. Coletores] → [2. Correlator] → [3. Analyzer (Claude)] → [4. Actions]
    ↓                  ↓                   ↓                    ↓
logs, métricas   contexto JSON      diagnóstico          remediação
eventos, traces  estruturado        proposta              + feedback
health checks    correlado          confiança
```

## 1. Coleta de Sinais

### O que é

Sinais são **evidências objetivas** do estado atual do sistema. Não são opiniões — são dados brutos.

### Categorias

#### Logs
- Stdout/stderr da app
- Arquivos de log estruturados (JSON, syslog)
- Exemplo: `[ERROR] Database connection timeout at 2026-07-21T14:23:12Z`

#### Métricas
- CPU, memória, disco
- Latência de requisições
- Taxa de erro, throughput
- Exemplo: `db_pool_size=10 active_connections=9 waiting=3`

#### Traces
- Rastreamento de requisição ponta-a-ponta
- Latência de cada etapa (middleware, query, render)
- Exemplo: `GET /api/dados: middleware(2ms) → auth(1ms) → query(150ms) → json(5ms)`

#### Eventos
- Deploys, mudanças de config
- Alertas de terceiros
- Mudanças de estado (app start, crash, restart)
- Exemplo: `DEPLOYED version=1.2.3 at 2026-07-21T14:20:00Z`

#### Health Checks
- Endpoint `/health` que responde status
- Verificações periódicas (banco, cache, rede)
- Exemplo: `{status: "partial", db: "ok", cache: "down", api: "ok"}`

### Coletores no Framework

Cada collector é um **script isolado** que:
1. Coleta um tipo de sinal
2. **Valida** (nenhum garbage)
3. Retorna **JSON estruturado** ou falha explicitamente

#### Exemplo: Collector de Health Check (Express)

```bash
#!/bin/bash
# collectors/nodejs/express-health.sh

set -euo pipefail

HOST=${1:-localhost:3000}
TIMEOUT=${2:-5}

# Faz request com timeout
response=$(curl -s -m $TIMEOUT "http://$HOST/health" 2>&1 || echo '{"error":"TIMEOUT"}')

# Valida que é JSON
if ! jq . <<< "$response" > /dev/null 2>&1; then
  echo '{"error":"INVALID_JSON","response":"'"$response"'"}'
  exit 1
fi

# Enriquece com timestamp
jq ". + {collected_at: $(date +%s), source: \"express-health\"}" <<< "$response"
```

Execução:
```bash
$ ./collectors/nodejs/express-health.sh
{
  "status": "healthy",
  "db": "ok",
  "cache": "ok",
  "collected_at": 1721576000,
  "source": "express-health"
}
```

## 2. Organização de Contexto (Correlator)

### O que é

O Correlator **junta múltiplos sinais** num modelo único, estruturado. Não é apenas "aqui está o log, aqui a métrica" — é "essas 3 coisas aconteceram juntas, nesta janela de tempo, com causa provável".

### Estrutura de Incidente

```json
{
  "incident_id": "INC-2026-07-21-001",
  "timestamp": "2026-07-21T14:23:45Z",
  "window_start": "2026-07-21T14:22:00Z",
  "window_end": "2026-07-21T14:25:00Z",
  
  "symptom": {
    "description": "API /api/dados retorna 500",
    "affected_users": "15%",
    "started_at": "2026-07-21T14:23:12Z"
  },
  
  "signals": {
    "logs": [
      {
        "level": "ERROR",
        "message": "Database connection timeout",
        "timestamp": "2026-07-21T14:23:12Z",
        "context": {"pool_size": 10, "active": 9}
      }
    ],
    "metrics": {
      "db_latency_ms": 5000,
      "db_pool_active": 9,
      "db_pool_waiting": 3,
      "memory_percent": 85,
      "cpu_percent": 92
    },
    "events": [
      {
        "type": "DEPLOY",
        "version": "1.2.2",
        "timestamp": "2026-07-21T14:20:00Z"
      }
    ],
    "health": {
      "status": "degraded",
      "db": "timeout",
      "cache": "ok"
    }
  },
  
  "hypotheses": [
    {
      "cause": "Database pool exhausted (9/10 active, 3 waiting)",
      "confidence": 0.95,
      "supporting_signals": ["db_pool_active=9", "latency=5000ms"]
    },
    {
      "cause": "Long-running query introduced in 1.2.2",
      "confidence": 0.70,
      "supporting_signals": ["deployed 3min ago", "db_latency spike"]
    }
  ],
  
  "suggested_actions": [
    {
      "priority": 1,
      "action": "Increase DB pool size from 10 to 20",
      "reversible": true,
      "estimated_impact": "Resolve 80% of timeout errors",
      "rollback": "Revert to pool_size=10"
    },
    {
      "priority": 2,
      "action": "Rollback deployment to 1.2.1",
      "reversible": true,
      "estimated_impact": "Return to baseline",
      "rollback": "Re-deploy 1.2.2"
    }
  ]
}
```

### Implementação do Correlator

O Correlator é um **pipeline JQ + pequeno script**:

```bash
#!/bin/bash
# framework/correlator.sh

set -euo pipefail

INCIDENT_ID="INC-$(date +%Y-%m-%d)-$(uuidgen | cut -c1-3)"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WINDOW_START=$(date -u -d '3 minutes ago' +"%Y-%m-%dT%H:%M:%SZ")

# Coleta todos os sinais (exemplos)
logs=$(./collectors/nodejs/logs.sh last-3m)
metrics=$(./collectors/generic/metrics.sh)
events=$(./collectors/generic/events.sh last-3m)
health=$(./collectors/nodejs/express-health.sh)

# Junta tudo num JSON estruturado
jq -n \
  --arg incident_id "$INCIDENT_ID" \
  --arg timestamp "$NOW" \
  --arg window_start "$WINDOW_START" \
  --arg window_end "$NOW" \
  --argjson logs "$logs" \
  --argjson metrics "$metrics" \
  --argjson events "$events" \
  --argjson health "$health" \
  '{
    incident_id: $incident_id,
    timestamp: $timestamp,
    window_start: $window_start,
    window_end: $window_end,
    signals: {
      logs: $logs,
      metrics: $metrics,
      events: $events,
      health: $health
    }
  }'
```

Saída:
```bash
$ ./framework/correlator.sh | jq .
{
  "incident_id": "INC-2026-07-21-A7F",
  "timestamp": "2026-07-21T14:23:45Z",
  "window_start": "2026-07-21T14:20:45Z",
  "window_end": "2026-07-21T14:23:45Z",
  "signals": { ... }
}
```

## 3. Análise com IA (Analyzer)

### O que é

O Analyzer **entende** o contexto estruturado. Ele roda o Correlator, pega o JSON, e usa Claude pra:
1. **Correlacionar:** "esses 3 sinais aparecem juntos — provável causa"
2. **Entender padrões:** "vi algo parecido em 2024-03, foi X"
3. **Estimar impacto:** "afeta Y% das requisições"
4. **Sugerir ações:** "faça A, depois B, senão tente C"
5. **Argumentar confiança:** "tenho 95% de certeza porque..."

### Prompt Estruturado

O prompt é **templates + contexto dinâmico**. Vive em `framework/analyzer.md`:

```markdown
# Analyzer do AIOps — Sistema RH

Você é um especialista em operações de Node.js + SQLite. Analise o incidente abaixo.

## Contexto do Sistema

- Stack: Express 5.x + SQLite 3 (local, sem cloud)
- Operação: Portal RH + EPIs na fábrica MSUL
- Crítica: dados de funcionários, estoque em tempo real
- Dependências: Tailscale VPN, ffmpeg (não crítico)

## Seu Trabalho

Dado o JSON estruturado do incidente:

1. **Identifique a causa raiz**
   - Correlacione sinais (lembre que 3 coisas simultâneas raramente são coincidência)
   - Use o histórico (mudanças recentes, deploys)
   - Descartem causas improváveis (ex: Tailscale se health/db é ok)

2. **Estime o impacto**
   - % de requisições afetadas
   - Usuários impactados
   - Duração provável

3. **Sugira ações em ordem de prioridade**
   - Curto prazo (reversível, <5min): estabilizar agora
   - Médio prazo (reversível, <30min): resolver a causa
   - Longo prazo (pode ser destrutivo): prevenir

4. **Argumente confiança**
   - 95%+ → quase certo
   - 70-94% → provável, mas confirme
   - 50-69% → possível, considere alternativas
   - <50% → especule, mas não aja

5. **Inclua rollback**
   - Cada ação deve ter reversão clara
   - Tempo estimado para rollback

## Seu Output

Responda em JSON:

\`\`\`json
{
  "diagnosis": {
    "root_cause": "...",
    "confidence": 0.95,
    "reasoning": [
      "Sinal 1 aponta para X",
      "Sinal 2 reforça X",
      "Timeline coincide com Y"
    ]
  },
  "impact": {
    "affected_percentage": 15,
    "affected_count": "~50 users",
    "severity": "HIGH",
    "duration_estimate": "ongoing"
  },
  "actions": [
    {
      "priority": 1,
      "action": "...",
      "reversible": true,
      "rollback": "...",
      "time_estimate_min": 2,
      "expected_impact": "..."
    }
  ],
  "notes": "..."
}
\`\`\`
```

### Como o Analyzer Roda

```bash
#!/bin/bash
# framework/analyzer.sh

set -euo pipefail

# 1. Coleta contexto
incident=$(./framework/correlator.sh)

# 2. Lê o prompt do analyzer
analyzer_prompt=$(cat framework/analyzer.md)

# 3. Chama Claude com contexto + prompt
claude_response=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d @- <<EOF
{
  "model": "claude-opus-4-8",
  "max_tokens": 2000,
  "messages": [
    {
      "role": "user",
      "content": "$analyzer_prompt\n\n## Incidente\n\n$(echo $incident | jq -c .)"
    }
  ]
}
EOF
)

# 4. Extrai resposta JSON
echo "$claude_response" | jq '.content[0].text' | jq '.'
```

Saída:
```json
{
  "diagnosis": {
    "root_cause": "Database pool exhausted by slow query",
    "confidence": 0.92,
    "reasoning": [...]
  },
  "impact": {
    "affected_percentage": 15,
    "severity": "HIGH"
  },
  "actions": [...]
}
```

## 4. Execução de Ações (Actions)

### Níveis de Segurança

**Nível 1 (Observação):** Nenhuma ação automática. Apenas diagnóstico.

**Nível 2 (Recomendação):** Agent propõe. Você aprova via UI/CLI antes de executar.

```bash
$ aiops analyze sistema-rh
# Mostra JSON do analyzer
# Oferece: [Approve] [Review] [Reject] [Save for later]

$ aiops execute --incident-id INC-2026-07-21-A7F --action 1
# Confirma permissões
# Executa ação
# Monitora rollback se falhar
# Registra em histórico
```

**Nível 3 (Automação Segura):** Ações reversíveis (resized pool, invalidate cache) são automáticas. Ações destrutivas ainda requerem confirmação.

### Categorias de Ações

#### Safe (Reversível em <30s)
```bash
actions/safe/nodejs/
  ├── increase-pool-size.sh       Aumenta DB pool
  ├── decrease-pool-size.sh       Reduz DB pool
  ├── clear-cache.sh              Invalida cache
  └── restart-worker.sh           Reinicia worker (sem perder conexões)
```

Executam em Nível 3 automaticamente.

#### Manual (Requer confirmação)
```bash
actions/manual/nodejs/
  ├── restart-app.sh              Reinicia Express (perde conexões vivas)
  ├── rollback-deploy.sh          Volta pra versão anterior
  └── scale-horizontally.sh       Sobe nova instância
```

Requerem `aiops execute --confirm` em qualquer nível.

### Implementação de Uma Ação

```bash
#!/bin/bash
# actions/safe/nodejs/increase-pool-size.sh

set -euo pipefail

NEW_SIZE=${1:-20}
DB_PATH=${2:-banco.sqlite}

# Validação
if [[ ! -f "$DB_PATH" ]]; then
  echo "ERROR: Database not found at $DB_PATH"
  exit 1
fi

if [[ $NEW_SIZE -lt 5 || $NEW_SIZE -gt 100 ]]; then
  echo "ERROR: Pool size must be 5-100"
  exit 1
fi

# Log para auditoria
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Increasing pool from ? to $NEW_SIZE" >> aiops.log

# Update config (exemplo: via API endpoint)
curl -s -X POST http://localhost:3000/api/admin/pool-size \
  -H "Authorization: Bearer $RH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"size\": $NEW_SIZE}" > /dev/null

# Verifica se funcionou
sleep 1
current_size=$(curl -s http://localhost:3000/api/health | jq '.db.pool_size')

if [[ "$current_size" == "$NEW_SIZE" ]]; then
  echo "SUCCESS: Pool resized to $NEW_SIZE"
  exit 0
else
  echo "FAILED: Pool is still $current_size"
  exit 1
fi
```

### Rollback Automático

Se uma ação falha, o framework tenta rollback:

```bash
# actions/safe/nodejs/increase-pool-size.rollback.sh

set -euo pipefail

ORIGINAL_SIZE=${1:-10}  # salvo quando ação foi executada
DB_PATH=${2:-banco.sqlite}

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Rolling back pool to $ORIGINAL_SIZE" >> aiops.log

curl -s -X POST http://localhost:3000/api/admin/pool-size \
  -H "Authorization: Bearer $RH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"size\": $ORIGINAL_SIZE}"

sleep 1
current_size=$(curl -s http://localhost:3000/api/health | jq '.db.pool_size')

if [[ "$current_size" == "$ORIGINAL_SIZE" ]]; then
  echo "ROLLBACK SUCCESS"
  exit 0
else
  echo "ROLLBACK FAILED — manual intervention required"
  exit 1
fi
```

---

## Fluxo Completo (Nível 2)

```
1. Incidente detectado (alerta, app crasha, métrica pula)
   ↓
2. Cron/webhook chama ./aiops analyze
   ↓
3. Coletores rodam em paralelo (logs, métricas, health)
   ↓
4. Correlator junta tudo num JSON estruturado
   ↓
5. Analyzer (Claude) lê JSON + prompt especializado
   ↓
6. Claude propõe diagnóstico + ações em ordem de prioridade
   ↓
7. Notificação (Slack, email, dashboard)
   ↓
8. Você clica [Approve] ou [Review]
   ↓
9. Framework executa ação, monitora resultado
   ↓
10. Registra em histórico pra aprendizado futuro
```

---

## Aprendizado Contínuo

Cada incidente **treina o modelo**:

```json
{
  "incident_id": "INC-2026-07-21-A7F",
  "diagnosis": { "root_cause": "...", "confidence": 0.92 },
  "actual_cause": "Pool exhausted — confirmed pós-ação",
  "actions_taken": [
    { "action": "Increased pool", "result": "SUCCESS", "time_ms": 45 }
  ],
  "feedback": {
    "diagnosis_accuracy": "CORRECT",
    "action_effectiveness": "RESOLVED",
    "learning": "Quando db_latency > 2000ms E pool_active/pool_size > 0.8, sempre é pool. Confiança: 99%"
  }
}
```

Com histórico, o analyzer melhora:
- **Diagnósticos mais precisos** (viu 50 pools exhausted, agora tem padrão)
- **Ações mais rápidas** (tempo médio de resolução cai)
- **Menos falsos positivos** (aprendeu o que NÃO é incidente)
