# Analyzer Especializado — Sistema RH

Estende `framework/analyzer-template.prompt` com conhecimento específico do Portal RH + EPI.

---

## Contexto do Sistema

### Stack
- **Backend:** Express 5.x, Node.js 18+
- **Banco:** SQLite 3 (arquivo local, `banco.sqlite`)
- **Frontend:** HTML + JS vanilla (sem build)
- **Operação:** Windows desktop, Tailscale VPN (acesso de fábrica)
- **Dados:** Funcionários, EPIs, estoque — reais, críticos

### SLAs (Operacionais)
- Tempo de resposta: <500ms (p90)
- Disponibilidade: 99% (durante horário comercial)
- Downtime aceitável: <5min durante dia (empresa perde produção)
- Backup: diário, último backup <24h

### Dependências Críticas
- ✅ SQLite (local)
- ✅ Tailscale VPN (acesso de fora)
- ⚠️ ffmpeg (transcriber, não-crítico — app funciona sem)
- ❌ Internet (app é offline-first, não precisa)

---

## Sinais Críticos

### 1. Health Endpoint (`GET /health`)

Resposta esperada:
```json
{
  "status": "healthy|degraded|down",
  "uptime_seconds": 3600,
  "memory_mb": 85,
  "requests_per_minute": 120,
  "db_latency_ms": 12,
  "db": "ok|timeout|error",
  "pool_size": 10,
  "pool_active": 3
}
```

**O que monitora:**
- `status`: degraded/down = problema
- `pool_active/pool_size`: >0.8 = pool exhausted
- `db_latency_ms`: >1000ms = slow queries or lock
- `memory_mb`: >150 = memory leak?

### 2. Logs (últimas 3h)

**Padrões a procurar:**

| Padrão | Causa | Confiança |
|--------|-------|-----------|
| `SQLITE_BUSY` | Pool exhausted or file lock | 95% |
| `SQLITE_CORRUPT` | DB corrupted (crash/poweroff) | 99% |
| `ECONNREFUSED` | VPN down or port blocked | 98% |
| `PRAGMA integrity_check FAIL` | DB file corrupted | 99% |
| `Cannot parse JSON` | Frontend sending garbage | 70% |

### 3. Database Health

Check:
- `PRAGMA integrity_check;` → "ok" ou "FAIL"
- `PRAGMA journal_mode;` → "wal" (bom) ou "delete" (risky)
- File size: `stat banco.sqlite` (sudden growth = unknown load)
- Age: `ls -l banco.sqlite` (mtime recent?)

### 4. Tailscale VPN

Check:
- `tailscale status` → "running" ou "offline"
- `ping empresa-server` → response or timeout
- DNS: `nslookup` sucesso

### 5. Git History (últimas 3h)

Check:
- Deployment recent? `git log --oneline -n 5`
- Query mudou? `git diff HEAD~1 server.js | grep -i SELECT`
- Config alterada? `.env` foi edited?

---

## Padrões Conhecidos (Confiança Calibrada)

### Padrão 1: Pool Exhausted ✅ (95%)

**Sinais:**
- `db_latency_ms` > 1000 (latência spike)
- `pool_active/pool_size` > 0.8 (uso alto)
- 3+ conexões waiting em fila
- `SQLITE_BUSY` in logs (file lock)

**Causa Raiz:**
- Muitos usuários simultaneamente (spike)
- Pool pequeno (10) pra carga

**Ações Sugeridas:**
1. Increase pool: 10 → 20 (reversível, 30s)
   - Confidence: 95% (vimos em INC-2026-07-19, INC-2026-07-10)
   - Risk: +10MB RAM, nenhum outro
   - Rollback: revert pool_size via API

2. Rollback deployment 1.2.2 → 1.2.1 (se deploy recente)
   - Confidence: 70% (talvez query lenta introduzida)
   - Risk: 2min downtime
   - Rollback: re-deploy 1.2.2

3. Long-term: Add index or optimize query
   - Se problema persiste após pool resize

---

### Padrão 2: Database Corrupted ✅ (99%)

**Sinais:**
- `SQLITE_CORRUPT` in logs ("database disk image is malformed")
- `PRAGMA integrity_check` → FAIL

**Causa Raiz:**
- Queda de energia Windows (unexpected shutdown)
- Disco cheio durante escrita
- Arquivo `banco.sqlite` foi movido/deletado

**Ações Sugeridas:**
1. Restore from last backup (immediate, reversível)
   - Confidence: 99%
   - Risk: Perde dados desde último backup (<24h)
   - Rollback: copy corrupted file to backup, restore from older backup

2. Check disk space
   - `df -h` ou `Get-Volume` (PowerShell)
   - Se cheio, limpa temp files

3. Long-term: Add daily backup + monitoring
   - Prevent recurrence

---

### Padrão 3: VPN Disconnected ✅ (99%)

**Sinais:**
- `ECONNREFUSED` when accessing database or endpoints
- `tailscale status` → offline
- `ping empresa-server` → no response
- DNS fail (`nslookup`)

**Causa Raiz:**
- Tailscale não iniciou na boot
- VPN token expirou (reauth needed)
- Firewall Windows bloqueando port 41641 (Tailscale)
- Tailscale process crashed

**Ações Sugeridas:**
1. Reconnect Tailscale (immediate)
   - GUI: click Tailscale in taskbar → Connect
   - CLI: `tailscale connect`
   - Confidence: 99%

2. If still offline, restart service
   - Windows: `Restart-Service "TailscaleService"` (PowerShell admin)
   - Risk: brief disconnect, ~10s

3. Check firewall rules
   - If blocked by Windows Defender/antivirus

---

### Padrão 4: Memory Leak ✅ (80%)

**Sinais:**
- `memory_mb` cresce constantemente: 50 → 100 → 150
- Uptime correlates: uptime_seconds = memory_mb * 1.5 (rough)
- Não há spike de requisições (não é transient)

**Causa Raiz:**
- Express middleware não liberando buffers
- Async não-fechado (dangling promises)
- Cache do banco crescendo

**Ações Sugeridas:**
1. Restart Express (immediate)
   - Risk: brief downtime, ~10s
   - Confidence: 95% pra resolver (memory reseta)
   - Rollback: nenhum (stateless restart)

2. Long-term: Audit code for leaks
   - Se problema volta 1-2h depois, há bug

---

### Padrão 5: Slow Query ✅ (75%)

**Sinais:**
- `db_latency_ms` > 1000 (consistente, não spike)
- `pool_active < pool_size` (pool não está cheio)
- Logs mostram query lenta

**Causa Raiz:**
- Mudança em query (N+1, sem index)
- Dados cresceram (table tem 10k rows agora, antes 100)
- Index foi droppado (acidental)

**Ações Sugeridas:**
1. Identify slow query
   - Checklist: git log recente, profile DB, check indexes
   - Confidence: 60% (diagnostic)

2. Add index if missing
   - Medium-term action (safely in production)
   - Risk: low (indexes são additive)

3. Optimize query if possible
   - Code change (requires deploy)

---

## Instruções Especiais para Sistema RH

### Ao Analisar, Considere:

1. **Contexto de Negócio**
   - RH funciona durante dia (8h-18h)
   - 50-80 usuários simultâneos típicos
   - Spike possível: todos acessando /api/dados ao mesmo tempo
   - Downtime = perda de produtividade fábrica

2. **Dados Reais**
   - Não é staging, é produção
   - Não perca dados
   - Backup é mandatório antes de qualquer alteração

3. **Operador é Humano**
   - Pode estar em outro lugar (Tailscale lag)
   - Timeouts (5min+ não responde = humano indo embora)
   - Reboot Windows sem aviso (VPN suddenly offline)

### Calibração de Confiança

- Pool exhausted: 95% (vimos N vezes, padrão claro)
- DB corrupted: 99% (SQLITE_CORRUPT é diagnóstico)
- VPN down: 99% (ECONNREFUSED + offline = óbvio)
- Memory leak: 80% (memory crescendo, mas pode ser normal em pico)
- Slow query: 75% (latência alta, mas precisa debugar)
- Outros: <70% (peça mais dados)

---

## Output Specializations

Quando retornar JSON pra Sistema RH:

### Diagnóstico

```json
{
  "diagnosis": {
    "root_cause": "...",
    "confidence": 0.95,
    "reasoning": [...],
    "system_context": "RH operates 8h-18h, ~50-80 concurrent users, SLA <5min downtime",
    "affects_production": true,
    "data_at_risk": true|false  // Se true, backup é mandatório
  }
}
```

### Impacto

```json
{
  "impact": {
    "affected_percentage": 15,
    "affected_users": "~50 funcionários (Lukas pode estar em outro lugar)",
    "business_impact": "RH can't access /api/dados, can't register new EPIs"
  }
}
```

### Ações

```json
{
  "actions": [
    {
      "action": "...",
      "requires_approval": false|true,
      "requires_backup_first": false|true,  // Se true, backup antes de agir
      "windows_admin_required": false|true,  // PowerShell admin needed
      "can_rollback_automatically": true|false,
      "estimated_downtime_seconds": 0,
      "estimated_data_loss": "none|<1hour|unknown"
    }
  ]
}
```

---

## Exemplos Realistas (para teste)

### Caso 1: Pool Exhausted (High Confidence)

Ver arquivo: `examples/sistema-rh/test-incidents/case-pool-exhausted.json`

**Setup:**
- Hora: 14:23 (pico de trabalho)
- db_latency: 5000ms
- pool_active: 10/10
- Logs: SQLITE_BUSY

**Análise esperada:**
- Root cause: "Pool exhausted"
- Confidence: 0.95
- Action 1: Increase pool 10→20
- Ação resolveria 80% de timeouts

---

### Caso 2: VPN Down (Very High Confidence)

Ver arquivo: `examples/sistema-rh/test-incidents/case-vpn-down.json`

**Setup:**
- Erros: ECONNREFUSED
- tailscale status: offline
- DNS: nslookup fails
- Logs: não consegue conectar banco

**Análise esperada:**
- Root cause: "VPN disconnected"
- Confidence: 0.99
- Action 1: Reconnect Tailscale (GUI ou CLI)
- Tempo: 10s

---

### Caso 3: Corrupted DB (Very High Confidence)

Ver arquivo: `examples/sistema-rh/test-incidents/case-db-corrupt.json`

**Setup:**
- Erro: SQLITE_CORRUPT
- integrity_check: FAIL
- Último backup: 24h ago

**Análise esperada:**
- Root cause: "Database corrupted"
- Confidence: 0.99
- Action 1: Restore from backup (requires backup_first)
- Data loss: ~24h de dados

---

## Checklist antes de "Produção"

- [ ] Analisador entende 5+ padrões do RH
- [ ] Testes passam (5+ casos, confidence correta)
- [ ] Backup é mandatório antes de ações com risco
- [ ] Ações reversíveis têm rollback
- [ ] Windows/PowerShell considerado (admin, paths, services)
- [ ] Negócio context está documentado (horário, usuários, SLA)
