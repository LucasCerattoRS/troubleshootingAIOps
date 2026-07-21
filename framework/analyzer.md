# Analyzer — Inteligência com Claude

## O que é

O Analyzer **interpreta correlations JSON** e usa Claude pra:
1. **Diagnosticar** — qual é a causa raiz provável
2. **Estimar impacto** — quantos usuários, qual severidade
3. **Propor ações** — o que fazer, em que ordem
4. **Raciocinar** — por que essa causa, que confiança tem

Não substitui humano, **augmenta**: propõe, você valida.

---

## Arquitetura

```
[correlator output] (JSON)
        ↓
[analyzer.md] (prompt template)
        ↓
[Claude API] (chamada com contexto)
        ↓
[diagnosis JSON] (estruturado)
        ↓
[executor] (você aprova antes de agir)
```

---

## Componentes

### 1. Prompt Template (`framework/analyzer-template.prompt`)

Template genérico que especializa por sistema. Tem seções:

```markdown
# Analyzer AIOps

Você é especialista em troubleshooting de [SISTEMA].

## Contexto do Sistema
- Stack: [STACK]
- Criticidade: [CRITICIDADE]
- Operação: [COMO RODA]
- SLA: [TEMPO MÁXIMO DE DOWNTIME]

## Seu Trabalho

Dado o JSON do incidente:

1. **Diagnóstico**
   - Correlacione sinais (3+ coisas simultâneas raramente são coincidência)
   - Consulte histórico (mudanças recentes)
   - Descarte causas improváveis

2. **Impacto**
   - % de requisições/funcionalidade afetada
   - Usuários impactados
   - Duração provável

3. **Ações em Ordem**
   - Curto prazo (reversível, <5min): estabilizar agora
   - Médio prazo (reversível, <30min): resolver causa
   - Longo prazo (pode ser destrutivo): prevenir

4. **Confiança**
   - 95%+: quase certo, aja
   - 70-94%: provável, mas confirme
   - <70%: especule, não aja

## Output

JSON estruturado:
\`\`\`json
{
  "diagnosis": {...},
  "impact": {...},
  "actions": [...]
}
\`\`\`
```

### 2. Prompt Especializado (por Sistema)

Exemplo: `examples/sistema-rh/analyzer.md`

```markdown
# Analyzer — Sistema RH

Especializado em Express + SQLite, operação crítica em fábrica.

## Sinais Críticos do RH

- **DB Pool**: pool_active / pool_size (se >90%, exausted)
- **Latência**: db_latency_ms (>1000ms = problema)
- **VPN**: Tailscale status (se offline, ninguém acessa)
- **Backup**: último backup (se >24h, risco)
- **Integridade**: PRAGMA integrity_check

## Padrões Conhecidos

1. **Pool Exhausted** (90% confiança)
   - Sinais: db_latency spike + pool_active/pool_size > 0.8
   - Causa: spike de requisições + pool pequeno
   - Ação: increase pool 2x (reversível em 30s)

2. **DB Corrupted** (85% confiança)
   - Sinais: SQLITE_CORRUPT error + integrity_check FAIL
   - Causa: queda de energia ou disco cheio
   - Ação: restore from last backup

3. **VPN Disconnected** (99% confiança)
   - Sinais: ECONNREFUSED + tailscale_status=offline
   - Causa: VPN não iniciou ou token expirou
   - Ação: reconnect via CLI

## Instruções Adicionais

- RH opera em Windows, use PowerShell pra ações
- Dados reais de funcionários → backup é mandatório
- Empresa conta comigo pra estar online 24/7
```

### 3. Integração com Claude API

Chamada estruturada (pseudocódigo):

```bash
#!/bin/bash
# analyzer.sh (não implementado ainda, apenas template)

# 1. Lê template genérico
GENERIC_PROMPT=$(cat framework/analyzer-template.prompt)

# 2. Lê prompt especializado
SPECIALIZED_PROMPT=$(cat examples/sistema-rh/analyzer.md)

# 3. Lê JSON do correlator
INCIDENT=$(cat /tmp/incident.json)

# 4. Monta mensagem pro Claude
FULL_PROMPT="$GENERIC_PROMPT\n\n$SPECIALIZED_PROMPT\n\n## Incidente\n\n$INCIDENT"

# 5. Chama Claude
RESPONSE=$(curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "{
    \"model\": \"claude-opus-4-8\",
    \"max_tokens\": 2000,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": \"$FULL_PROMPT\"
    }]
  }")

# 6. Extrai JSON da resposta
echo "$RESPONSE" | jq '.content[0].text' | jq '.'
```

### 4. Estrutura de Output

Analyzer retorna JSON com 3 seções:

#### `diagnosis`
```json
{
  "root_cause": "Database pool exhausted",
  "confidence": 0.92,
  "reasoning": [
    "db_latency jumped 5s at 14:23:12",
    "pool_active = 9/10 (90% utilization)",
    "3 connections waiting in queue",
    "No recent changes (git log clean)"
  ],
  "similar_incidents": [
    {
      "id": "INC-2026-07-19-X2K",
      "when": "2 days ago",
      "root_cause": "Same: pool exhausted",
      "resolution_time": 45,
      "action_taken": "Increased pool to 20"
    }
  ]
}
```

#### `impact`
```json
{
  "affected_percentage": 15,
  "affected_users": "~50 funcionários",
  "affected_features": ["GET /api/dados", "PUT /api/epis"],
  "severity": "HIGH",
  "duration_estimate": "ongoing",
  "business_impact": "Gestão de funcionários/EPIs parada"
}
```

#### `actions`
```json
[
  {
    "priority": 1,
    "action": "Increase DB pool from 10 to 20",
    "reversible": true,
    "reversible_time_seconds": 30,
    "rollback": "Revert to pool_size=10",
    "estimated_impact": "Resolves 80% of timeouts",
    "time_to_execute_seconds": 45,
    "risks": "None if rollback is quick",
    "requires_approval": false,
    "implementation": "POST /api/admin/pool-size {size: 20}"
  },
  {
    "priority": 2,
    "action": "Rollback deployment 1.2.2 → 1.2.1",
    "reversible": true,
    "reversible_time_seconds": 120,
    "rollback": "Re-deploy 1.2.2",
    "estimated_impact": "Return to baseline",
    "time_to_execute_seconds": 120,
    "risks": "2min downtime during redeploy",
    "requires_approval": true,
    "implementation": "git revert HEAD && npm run deploy"
  }
]
```

---

## Fluxo de Operação (Nível 2)

```
1. Correlator roda
   └→ Gera /tmp/incident-INC-2026-07-21-A7F.json

2. Analyzer lê JSON
   └→ Chama Claude com contexto + prompt especializado

3. Claude retorna diagnóstico estruturado
   └→ 3 seções: diagnosis, impact, actions

4. Sistema mostra pra você
   ┌─────────────────────────────────
   │ 🔍 Diagnosis
   │ Root Cause: Database pool exhausted
   │ Confidence: 92%
   │ Reasoning: [...]
   │
   │ 📊 Impact
   │ 15% of users affected, ~50 funcionários
   │ Severity: HIGH
   │
   │ ⚡ Suggested Actions
   │ 1. [SAFE] Increase pool 10→20 (45s)
   │    └→ Expected to resolve 80% of errors
   │ 2. [NEEDS APPROVAL] Rollback 1.2.2→1.2.1 (2min)
   │    └→ Return to baseline
   └─────────────────────────────────

5. Você escolhe
   $ aiops execute --action 1 --confirm
   
6. Framework executa + monitora + registra

7. Feedback loop (histórico melhora diagnósticos futuros)
```

---

## Desafios Antecipados

### Challenge 1: Hallucinations (Claude propõe algo errado)

**Mitigação:**
- Prompt include "Se não tiver certeza, diga"
- Confidence <70% → force approval manual
- Histórico de ações: "última vez que sugeriu X, resultado foi Y"

### Challenge 2: Contexto não é suficiente

**Mitigação:**
- Correlator coleta sinais errados/incompletos
- Solução: adicionar mais coletores (custom by system)
- Analyzer pede: "faltou dados de X, execute collector/X.sh"

### Challenge 3: Ação proposta não funciona

**Mitigação:**
- Cada ação tem rollback automático
- Se falha, executa rollback e propõe next action
- Registra em histórico: "ação A falhou, tente B"

### Challenge 4: Demora pra chamar Claude API

**Mitigação:**
- Cache de respostas (mesma correlação = mesma ação)
- Timeout: se Claude demora >10s, use last known action
- Fallback: modo sem-IA (diagnostic manual)

---

## Variações por Sistema

### Sistema RH (Nível 2)
```
✅ Diagnosis detalhado (expertise DB + Express)
✅ Confiança alta (3+ meses histórico)
✅ Ações reversíveis (pool, cache)
❌ Sem automação (você aprova tudo)
```

### FinanWise (Futuro Nível 1)
```
✅ Diagnosis básico (crashes, data integrity)
⚠️ Confiança média (novo, poucos exemplos)
⚠️ Poucas ações (mostly restore backup)
❌ Sem automação
```

### TranscritorNPU (Futuro Nível 1)
```
✅ Diagnosis: latency, GPU saturation
⚠️ Confiança média (device-dependent)
⚠️ Ações: reduz batch, suggests device
❌ Sem automação
```

---

## Implementação Futura

Quando implementar analyzer.sh:

```bash
1. Parse command line args
   --incident-file: JSON path
   --system: rh|finanwise|npu (default: auto-detect)
   --confidence-threshold: 0.70 (default)
   --cache: use cache ou force fresh (default: use)

2. Validar JSON entrada
   - Tem incident.id?
   - Tem signals?
   - Timestamps válidos?

3. Carregar prompts
   - framework/analyzer-template.prompt
   - examples/$SYSTEM/analyzer.md

4. Chamar Claude (com timeout, retry, cache)
   - Montar full prompt
   - POST /v1/messages
   - Parse response

5. Validar output
   - É JSON válido?
   - Tem diagnosis.confidence?
   - Tem actions[]?

6. Retornar ou salvar
   - Stdout: JSON puro
   - File: $INCIDENT_ID.diagnosis.json
   - Slack: notificação com resumo
```

---

## Checklist de Preparação

- [x] Documentação de prompts (framework/analyzer.md)
- [x] Template genérico (framework/analyzer-template.prompt)
- [x] Prompt especializado RH (examples/sistema-rh/analyzer.md)
- [x] Exemplos de incidentes (examples/sistema-rh/test-incidents/ — 5 fixtures)
- [x] Estrutura de output validada (5 golden .expected.json)
- [x] Casos de teste (5 casos cobrindo os 5 padrões do RH)
- [x] Script analyzer.sh + analyzer.ps1 (funcionais, dry-run por padrão)
- [x] Guia de uso do analyzer (docs/ANALYZER.md)

**Status:** 8/8 — analyzer completo como preparação. Nada roda até `--execute`.
Próximo (fora de escopo): coletores restantes, correlator.sh/.ps1, executor, test runner.
