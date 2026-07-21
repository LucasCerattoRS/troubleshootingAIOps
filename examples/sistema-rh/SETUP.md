# Sistema RH — Integração AIOps (Nível 1-2)

## Status

Este exemplo implementa **Nível 1 (observabilidade)** + **Nível 2 (recomendação)** para o Portal RH + EPI.

**Stack:**
- Express 5.x + Node.js 18+
- SQLite 3 (local)
- Windows desktop + Tailscale VPN
- Criticidade: 🔴 Alta

---

## Instalação

### 1. Clone os repos

```bash
# Framework AIOps
cd ~/projects
git clone https://github.com/LucasCerattoRS/troubleshootingAIOps.git

# Sistema RH (seu repo)
git clone https://github.com/LucasCerattoRS/Msul.git sistema-rh
```

### 2. Setup variáveis

```bash
# No repo Sistema RH
export SISTEMA_RH_PATH="$(pwd)/sistema-rh"
export AIOPS_PATH="$(pwd)/troubleshootingAIOps"
export RH_TOKEN="<seu-token-do-.env>"
export ANTHROPIC_API_KEY="<sua-api-key>"
```

### 3. Criar symlinks (ou copiar coletores)

```bash
cd $SISTEMA_RH_PATH

# Symlink pro framework genérico
ln -s $AIOPS_PATH/framework .aiops-framework

# Coletores específicos pro Sistema RH
mkdir -p .aiops/collectors
cp $AIOPS_PATH/examples/sistema-rh/collectors/* .aiops/collectors/
```

---

## Uso

### Coleta Manual (Nível 1)

Rodar correlator manualmente:

```bash
cd $SISTEMA_RH_PATH

# Coleta todos os sinais
./.aiops/correlator.sh | jq .

# Salva pra análise depois
./.aiops/correlator.sh > /tmp/incident-$(date +%s).json
```

Saída esperada:

```json
{
  "incident": {
    "id": "INC-2026-07-21-A7F",
    "timestamp": "2026-07-21T14:23:45Z"
  },
  "signals": {
    "app": {
      "health": { "status": "ok", ... },
      "logs": [ ... ]
    },
    "database": {
      "health": { ... },
      "latency": ...
    },
    "system": {
      "memory": ...,
      "disk": ...
    }
  }
}
```

### Análise com Claude (Nível 2)

```bash
cd $SISTEMA_RH_PATH

# DRY-RUN é o padrão: monta o prompt e mostra o request, SEM chamar a API (sem custo).
./.aiops/analyzer.sh --incident-file /tmp/incident-A7F.json

# EXECUTE (opt-in): chama a API de verdade. Exige ANTHROPIC_API_KEY.
./.aiops/analyzer.sh --incident-file /tmp/incident-A7F.json --confidence-threshold 0.80 --execute
```

> Detalhes de todas as flags e do endurecimento (structured outputs) em
> [`docs/ANALYZER.md`](../../docs/ANALYZER.md).

Saída esperada:

```json
{
  "diagnosis": {
    "root_cause": "Database pool exhausted",
    "confidence": 0.92,
    "reasoning": [...]
  },
  "impact": {
    "affected_percentage": 15,
    "severity": "HIGH"
  },
  "actions": [
    {
      "priority": 1,
      "action": "Increase DB pool from 10 to 20",
      "reversible": true,
      "rollback": "Revert to 10"
    }
  ]
}
```

### Execução de Ação (Nível 2 — Manual)

```bash
cd $SISTEMA_RH_PATH

# Lista ações disponíveis
./.aiops/actions/list

# Executa ação específica (com aprovação)
./.aiops/actions/execute \
  --action "increase-pool" \
  --from 10 \
  --to 20 \
  --confirm

# Verifica status
./.aiops/actions/status --incident-id INC-2026-07-21-A7F
```

---

## Integração com Cron (Nível 1 Automático)

Coletar a cada 5 minutos:

```bash
# Editar crontab
crontab -e

# Adicionar (example para Linux/macOS):
*/5 * * * * cd /path/to/sistema-rh && ./.aiops/correlator.sh >> /var/log/aiops/rh-collect.log 2>&1

# Windows (Agendador de Tarefas):
# Ação: python -c "import os; os.system('cd C:\\Sistema_RH && .aiops\\correlator.sh >> logs\\aiops.log')"
# Repetição: 5 minutos
```

---

## Estrutura de Coletores

Cada coletor retorna JSON e é independente:

```bash
.aiops/collectors/
├── express-health.sh       GET /health
├── sqlite-health.sh        PRAGMA integrity_check + pool info
├── logs.sh                 últimos 100 erros
├── metrics.sh              CPU, mem, I/O do processo
├── tailscale-status.sh     VPN connectivity (Windows-only)
└── events.sh               git log últimas 3h (recent changes)
```

Testar individuais:

```bash
./.aiops/collectors/express-health.sh
./.aiops/collectors/sqlite-health.sh
```

---

## Troubleshooting

### "Cannot connect to server"

```bash
# Verificar se Express está rodando
ps aux | grep node

# Verificar porta
netstat -ln | grep 3000

# Testar saúde manualmente
curl http://localhost:3000/health
```

### "jq: command not found"

```bash
# Instalar jq
apt-get install jq          # Ubuntu/Debian
brew install jq             # macOS
choco install jq            # Windows
```

### "Database connection error"

```bash
# Verificar integridade
sqlite3 banco.sqlite "PRAGMA integrity_check;"

# Check last 3 lines of error log
tail -3 ./logs/*error* 2>/dev/null || echo "No error log"
```

---

## Checklist de Setup

- [ ] Framework AIOps clonado
- [ ] ANTHROPIC_API_KEY exportado
- [ ] RH_TOKEN (do .env) exportado
- [ ] Coletores copiados em .aiops/collectors/
- [ ] Health check endpoint funciona
- [ ] jq instalado
- [ ] Primeira coleta rodou sem erro
- [ ] JSON output é válido

---

## Próximos Passos

1. **Rodar coleta manual** (5 min) — veja se tudo está ok
2. **Testar analyzer** (10 min) — veja propostas de diagnóstico
3. **Integrar cron** (15 min) — rodar a cada 5 min automaticamente
4. **Slack integration** (30 min) — notificações de incidentes

---

## Documentação Adicional

- [Arquitetura completa](../../docs/ARQUITETURA.md)
- [Níveis de implementação](../../docs/NIVEIS.md)
- [Casos e cenários](../../docs/CASES.md)
