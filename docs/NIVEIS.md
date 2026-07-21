# 3 Níveis de Implementação

Um framework AIOps começa **passivo** (coleta) e evolui para **automático** (ação). Não pule etapas.

## Nível 1: Observabilidade Passiva

### O que faz

- ✅ Coletores rodam periodicamente
- ✅ Correlator organiza sinais
- ✅ Você vê contexto estruturado
- ❌ Sem automação, sem ação

### Quando usar

- Primeira implementação (exploratória)
- Sistema novo em operação
- Ainda entendendo padrões de falha
- Sem SLA de tempo de resolução

### Benefício

**Contexto pronto.** Hoje você faz 5-10 SSH commands. Com Nível 1, um arquivo JSON único mostra tudo: o que quebrou, quando, por quê (provável).

Reduz *investigação manual* de 30min para 5min (você só lê em vez de garimpar).

### Implementação

```bash
# Rodar a cada 5 minutos via cron
*/5 * * * * /opt/aiops/framework/correlator.sh > /var/log/aiops/incident-$(date +\%s).json 2>&1

# Dashboard que lê os JSONs e mostra (opcional)
# Slack bot que notifica (opcional)
```

### Exemplo: Sistema RH — Nível 1

```bash
$ crontab -e
*/5 * * * * cd /path/to/sistema-rh && ./aiops-collect.sh

$ cat /var/log/aiops/latest-incident.json
{
  "incident_id": "INC-2026-07-21-A7F",
  "symptom": "API /api/dados returns 500",
  "signals": {
    "logs": [ {"level": "ERROR", "message": "Database timeout"} ],
    "metrics": { "db_latency": 5000, "pool_active": 9 },
    "health": { "status": "degraded", "db": "timeout" }
  }
}

# Você lê esse JSON → "ah, database pool está cheio"
# Sem Nível 1 você estaria fazendo:
# $ ssh empresa && tail -f logs && ps aux && sqlite3 banco.sqlite 'SELECT...'
```

### Estrutura de Pastas (Nível 1)

```
sistema-rh/
├── .aiops/
│  ├── collectors/
│  │  ├── health.sh          GET /health
│  │  ├── logs.sh            últimos 100 erros
│  │  ├── metrics.sh         cpu, mem, db_pool
│  │  └── events.sh          deployments recentes
│  │
│  └── correlator.sh         junta todos
│
└── aiops-collect.sh         alias: "./framework/correlator.sh"
```

---

## Nível 2: Recomendação Inteligente

### O que faz

- ✅ Tudo do Nível 1
- ✅ Analyzer (Claude) **propõe** diagnóstico + ações
- ✅ Você **valida** antes de executar
- ✅ Sistema **registra** resultado para aprendizado

### Quando usar

- Depois de Nível 1 consolidado
- Padrões de falha claros (viu 3-5 incidentes similares)
- Ações propostas são seguras, reversíveis
- Team confortável com CLI/dashboard

### Benefício

**Diagnóstico + Solução em 2-5 min.** Hoje: 30min (SSH + investigação). Com Nível 2: Agent lê contexto, propõe causa + ação, você clica [Aprove].

MTTR cai 80%.

### Implementação

```bash
# Analyzer roda depois do Correlator
$ ./aiops analyze sistema-rh
# Mostra JSON com diagnosis + suggested actions

# Você escolhe:
$ aiops execute --incident-id INC-2026-07-21-A7F --action 1 --confirm
# Executa ação, monitora, registra resultado
```

### Exemplo: Sistema RH — Nível 2

```bash
$ ./aiops analyze sistema-rh

{
  "diagnosis": {
    "root_cause": "Database pool exhausted",
    "confidence": 0.92,
    "reasoning": [
      "db_latency jumped 5s at 14:23:12",
      "db_pool_active = 9/10 (90% utilization)",
      "3 connections waiting in queue",
      "No changes to schema or indexing (checked git log)"
    ]
  },
  "impact": {
    "affected_percentage": 15,
    "affected_users": "~50 funcionários",
    "severity": "HIGH",
    "duration": "ongoing"
  },
  "actions": [
    {
      "priority": 1,
      "action": "Increase DB pool from 10 to 20",
      "reversible": true,
      "rollback_time": "10s",
      "expected_impact": "Resolves 80% of timeouts"
    },
    {
      "priority": 2,
      "action": "Rollback deployment 1.2.2 → 1.2.1",
      "reversible": true,
      "rollback_time": "2min",
      "expected_impact": "Return to baseline if pool resize doesn't work"
    }
  ]
}

# Você vê isso e clica:
$ aiops execute --action 1
# Aumenta pool pra 20
# Monitora por 1 minuto
# Se falhar, rollback automático
# Registra resultado
```

### Flow Nível 2 vs Nível 1

| Aspecto | Nível 1 | Nível 2 |
|---------|---------|---------|
| **Coleta** | ✅ Coletores | ✅ Coletores |
| **Análise** | ❌ Manual | ✅ Claude (90%+) |
| **Proposta** | ❌ Você deduz | ✅ Agent sugere |
| **Ação** | ❌ Manual SSH | ✅ Framework (aprovado) |
| **Tempo** | 30min | 2-5min |
| **Erro humano** | Alto | Baixo |

### Estrutura (Nível 2)

```
sistema-rh/
├── .aiops/
│  ├── collectors/         (igual Nível 1)
│  ├── correlator.sh       (igual Nível 1)
│  │
│  ├── analyzer.md         Prompt especializado pra Sistema RH
│  ├── analyzer.sh         Chama Claude
│  │
│  └── actions/
│     ├── increase-pool.sh
│     └── increase-pool.rollback.sh
│
└── aiops analyze         CLI command
```

---

## Nível 3: Automação Segura

### O que faz

- ✅ Tudo do Nível 1 + 2
- ✅ Ações **reversíveis** são automáticas (sem clique)
- ✅ Ações **destrutivas** ainda requerem confirmação
- ✅ Sistema **aprende** e melhora cada vez

### Quando usar

- Depois de 3+ meses rodando Nível 2
- Confiança >90% nas propostas
- MTTR é métrica importante
- Runbooks documentados e testados
- Rollback automático provou funcionar >95%

### Benefício

**MTTR <30s para incidentes conhecidos.** Sistema detecta, resolve e notifica antes de você perceber.

Operação **assimétrica**: problema pequeno (pool cheio) resolve em segundos. Problema grande (banco corrompido) ainda avisa com calma.

### Implementação

```bash
# Framework monitora, detecta, age automaticamente
# Você só é notificado *depois*

# Slack bot notifica 1 minuto depois da ação
# "Pool exhausted at 14:23, resized to 20, resolved at 14:23:45"

# Você checa histórico quando quiser
$ aiops history sistema-rh --last 7d
```

### Exemplo: Sistema RH — Nível 3

```
14:23:12 — API latency spike detected
           └→ Correlator runs, collects signals
           
14:23:45 — Analyzer suggests: increase pool (confidence 92%)
           └→ Framework sees: reversible + proven effective
           └→ Automatically executes (logs every step)
           
14:24:00 — API latency normalizes
           └→ Framework confirms: action worked
           
14:24:15 — Slack notification
           ┌─────────────────────────────────────────
           │ 🤖 AIOps: Incident INC-2026-07-21-A7F resolved
           │ 📊 Database pool exhausted
           │ ✅ Action: Increased to 20 (was 10)
           │ ⏱️ Time to resolve: 48 seconds
           │ 📈 Learn: This pattern has 92% success rate
           └─────────────────────────────────────────

Você see notification 1min later, crisis already over.
```

### Categorias de Ações (Nível 3)

```
Safe (automático):
  ├─ increase-pool           DB pool size (reversível em 30s)
  ├─ decrease-pool           Menos usual, mas reversível
  ├─ clear-cache             Invalida cache (rebuild automático)
  ├─ restart-worker          Mata worker e cria novo (drena conexões)
  └─ disable-slow-query      Desativa query lenta (temporário, alertar)

Unsafe (manual):
  ├─ restart-app             Mata Express (perde sessões vivas)
  ├─ rollback-deploy         Volta versão anterior (1-2min downtime)
  ├─ delete-db-cache         Apaga arquivo (irreversível pra sempre)
  └─ scale-horizontally      Levanta nova instância (complexo)
```

### Estrutura (Nível 3)

```
sistema-rh/
├── .aiops/                    (Nível 1 + 2)
│  │
│  ├── actions/
│  │  ├── safe/                Executam automaticamente
│  │  │  ├── increase-pool.sh
│  │  │  ├── clear-cache.sh
│  │  │  └── restart-worker.sh
│  │  │
│  │  └── unsafe/              Requerem confirmação
│  │     ├── restart-app.sh
│  │     └── rollback-deploy.sh
│  │
│  └── executor.sh             Despacha ações, monitora, rollback
│
└── aiops execute              Chama executor (Nível 1: manual, Nível 3: auto)
```

### Rollback Automático

Cada ação tem rollback:

```bash
# actions/safe/increase-pool.sh
OLD_SIZE=$(curl http://localhost:3000/api/health | jq '.db.pool_size')
curl -X POST http://localhost:3000/api/admin/pool-size -d "{size:20}"
sleep 1

# Verifica se funcionou
NEW_LATENCY=$(curl http://localhost:3000/api/health | jq '.db.latency_ms')

if (( NEW_LATENCY > 1000 )); then
  # Rollback automático
  echo "Action failed, rolling back..."
  ./actions/safe/increase-pool.rollback.sh "$OLD_SIZE"
  exit 1
fi
```

### Aprendizado Contínuo (Nível 3)

```json
{
  "incident_id": "INC-2026-07-21-A7F",
  "signals": { ... },
  "diagnosis": {
    "root_cause": "Pool exhausted",
    "confidence": 0.92,
    "proposed_action": "increase-pool"
  },
  "execution": {
    "action": "increase-pool",
    "time_to_execute": 45,
    "result": "SUCCESS"
  },
  "outcome": {
    "incident_resolved": true,
    "time_to_resolve": 48,
    "verification": "latency normalized"
  },
  "feedback": {
    "diagnosis_accuracy": "CORRECT",
    "was_next_action_needed": false,
    "new_pattern": "pool_active/pool_size > 0.8 AND latency > 1000ms → increase pool 2x"
  }
}
```

Com 50 incidentes similares, o analyzer treina-se:
- **Diagnóstico:** De 92% de confiança → 99%
- **Ações:** Tempo médio reduce de 48s → 15s
- **Falsos positivos:** De 10% → <1%

---

## Migração de Nível

### Nível 1 → 2

**Pré-requisito:**
- ✅ Coletores rodam 100% das vezes
- ✅ Correlator JSON bem-formado
- ✅ Viu 3-5 incidentes similares
- ✅ Entende padrões de falha

**Checklist:**
```bash
[ ] Analyzer.md escrito (prompt especializado)
[ ] Test analyzer com exemplos reais (5+ casos)
[ ] Actions escritas e testadas (não em produção)
[ ] Rollback automático funciona
[ ] CLI (aiops analyze, aiops execute) funciona
[ ] Team treinado no CLI
[ ] Slack/notification setup
```

**Deploy:**
- Cron: Analyzer roda a cada 5min
- Notificação: Slack mostra propostas
- Você: Aprova via `aiops execute`

**Primeira semana:** Manual (você testa)  
**Semana 2+:** Confiança builds

### Nível 2 → 3

**Pré-requisito:**
- ✅ Nível 2 rodou 3+ meses
- ✅ Diagnóstico accuracy >90%
- ✅ Action success rate >95%
- ✅ Rollback never failed
- ✅ MTTR < 5min é critério de sucesso

**Checklist:**
```bash
[ ] Safe actions categorizados explicitamente
[ ] Executor.sh implementado (auto vs manual)
[ ] Failsafe: se ação falha, rollback automático
[ ] Logging de cada step (auditório completo)
[ ] Team confortável com automação
[ ] Runbook/documentation up-to-date
[ ] Monitoring de actions (métricas, alertas)
```

**Deploy:**
- Ações safe mudam de `aiops execute --confirm` → automático
- Ações unsafe continuam requerendo confirmação
- Slack notifica *depois* (história post-mortem)

**Primeira semana:** Monitore com atenção  
**Semana 2+:** Confiança cresce

---

## Quadro Resumido

| Aspecto | Nível 1 | Nível 2 | Nível 3 |
|---------|---------|---------|---------|
| **Coleta** | ✅ | ✅ | ✅ |
| **Análise** | ❌ | ✅ | ✅ |
| **Ação** | ❌ | Manual | Auto (safe) |
| **Aprendizado** | ❌ | Básico | Contínuo |
| **MTTR** | 30min | 2-5min | <1min |
| **Confiança requeria** | - | >80% | >90% |
| **Tempo desenvolvimento** | 2 semanas | +2 semanas | +4 semanas |
| **Tempo deployment** | 1 dia | 1 dia | 1-2 semanas |

---

## Decisão: Qual nível começar?

**Sistema RH (produção, crítico):**
- Comece com Nível 1 (observabilidade)
- Programe Nível 2 para 4 semanas depois
- Nível 3 só depois de 3 meses rodando bem

**FinanWise (desktop, dados pessoais):**
- Comece com Nível 1 (aprendizado)
- Nível 2 é optional (não há SLA)
- Nível 3 nunca necessário

**TranscritorNPU (acadêmico):**
- Nível 1 apenas (coleta + diagnóstico manual)
- Prioridade baixa
