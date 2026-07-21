# Casos Reais: Sistema RH, FinanWise, TranscritorNPU

## Sistema RH (Express + SQLite)

### Stack
- **Backend:** Express 5.x + Node.js 18+
- **Banco:** SQLite 3 (local, `banco.sqlite`)
- **Frontend:** HTML + JS vanilla (no build)
- **Operação:** Windows desktop + Tailscale VPN (empresa)
- **Criticidade:** 🔴 Alta (dados reais de funcionários, EPIs, estoque)

### Sinais Críticos a Coletar

#### 1. Health Check (Express)
```bash
# GET /health endpoint (pública, sem auth)
# Responde com status operacional

curl http://localhost:3000/health | jq .
{
  "status": "healthy|degraded|down",
  "timestamp": "2026-07-21T14:23:45Z",
  "db": "ok|timeout|error",
  "db_latency_ms": 12,
  "pool_size": 10,
  "pool_active": 3,
  "uptime_seconds": 3600,
  "memory_mb": 85,
  "requests_per_minute": 120
}
```

#### 2. Logs (Express)
```bash
# Últimas 100 linhas de erro
tail -100 /path/to/servidor.log | grep ERROR | jq .

[2026-07-21T14:23:12Z] ERROR: Database connection timeout
[2026-07-21T14:23:13Z] ERROR: SQLSTATE[HY000]: General error: ...
```

#### 3. Banco de Dados
```bash
# Integridade
sqlite3 banco.sqlite "PRAGMA integrity_check;"
ok

# Tamanho e locks
stat banco.sqlite | grep Size
ls -lh banco.sqlite

# Connections
ps aux | grep "banco.sqlite"
```

#### 4. VPN (Tailscale)
```bash
# Status de conectividade
tailscale status | grep -i connection
# Latência
ping -c 3 empresa-machine
```

### Cenários de Falha (Nível 1)

#### Cenário 1: Database Pool Exhausted

**Sintoma:** API /api/dados retorna 500, latência > 1s

**Sinais correlacionados:**
```json
{
  "symptom": "/api/dados returns 500",
  "logs": [
    {"level": "ERROR", "message": "SQLITE_BUSY", "timestamp": "14:23:12"}
  ],
  "metrics": {
    "db_latency_ms": 5000,
    "pool_active": 10,  // maxed out
    "pool_waiting": 3,
    "requests_per_minute": 200  // spike
  },
  "hypothesis": "Pool exhausted by spike in requests"
}
```

**Causa raiz provável:**
1. Spike de requisições (15% de usuários simultaneamente)
2. Pool size (10) é pequeno
3. Queries lentas (não indexadas ou N+1)
4. Conexão VPN lenta (Tailscale lag)

**Ações sugeridas (Nível 2):**
1. Increase pool size 10 → 20 (reversível, 30s)
2. Check slow query logs (diagnóstico)
3. Add index se necessário (permanente, 5min)

#### Cenário 2: Banco Corrompido

**Sintoma:** Qualquer query retorna "database disk image is malformed"

**Sinais:**
```json
{
  "logs": [
    {"error": "SQLITE_CORRUPT", "message": "database disk image is malformed"}
  ],
  "integrity_check": "FAILED: integrity constraint violation",
  "last_backup": "2026-07-21 08:00:00"
}
```

**Causa raiz provável:**
1. Queda de energia (Windows crash)
2. Disco cheio durante write
3. Arquivo `banco.sqlite` foi movido/deletado
4. Antivírus travou acesso

**Ações (Nível 2):**
1. Restore from last backup (reversível, 30s)
2. Check disk space (diagnóstico)
3. PRAGMA integrity_check no backup (verificação)
4. Add scheduled backups to cron (preventivo)

#### Cenário 3: VPN Desconectada

**Sintoma:** API works locally mas não consegue conectar ao servidor quando de fora

**Sinais:**
```json
{
  "tailscale_status": "disconnected|offline",
  "ping_response": "no response",
  "logs": [
    {"error": "ECONNREFUSED", "message": "connect to 192.168.x.x:3000"}
  ]
}
```

**Causa raiz provável:**
1. Tailscale não inicializou na boot
2. VPN token expirou
3. Firewall Windows bloqueando
4. Tailscale process crashed

**Ações (Nível 2):**
1. Reconnect Tailscale (manual CLI)
2. Restart Tailscale service
3. Check firewall rules (diagnóstico)

---

## FinanWise (Electron + JSON)

### Stack
- **Frontend:** HTML + CSS + JS vanilla
- **Backend:** Electron (desktop bridge)
- **Dados:** JSON local (`dados.json`) portátil
- **Plataformas:** Windows + Linux (cross-platform)
- **Criticidade:** 🟡 Média (dados pessoais, sem SLA produção)

### Sinais Críticos a Coletar

#### 1. App Health
```bash
# Check se Electron process está rodando
ps aux | grep "Finan" | grep -v grep

# Collect recent crashes (Electron renderer/main)
tail -50 ~/.local/share/Finan/logs/crash.log

# Memory usage
ps aux | grep Finan | awk '{print $6}'  # RSS in KB
```

#### 2. Dados Integrity
```bash
# Validar dados.json é valid JSON
jq empty dados.json

# Check schema version
jq '.schemaVersion' dados.json

# Checksuma (detecta corrupção)
md5sum dados.json > dados.json.md5
```

#### 3. Performance
```bash
# Startup time
time electron main.js

# Query time (exemplo: sum all transactions)
time jq '[.transactions[] | .value] | add' dados.json

# File size (growth detect)
du -sh dados.json
```

### Cenários de Falha (Nível 1)

#### Cenário 1: App não abre

**Sintoma:** Double-click no .exe, nada acontece ou crash

**Sinais:**
```json
{
  "symptoms": "App crashes on launch",
  "logs": [
    {"error": "ENOENT", "message": "dados.json not found"}
  ],
  "data_integrity": {
    "file_exists": false,
    "last_modified": "N/A",
    "backups_available": ["2026-07-20.backup.json"]
  }
}
```

**Causa raiz provável:**
1. `dados.json` deletado/movido
2. Disco cheio
3. Electron renderer crashed
4. Permissão de arquivo negada

**Ações (Nível 2):**
1. Restore from backup (reversível, 10s)
2. Check disk space
3. Check file permissions

#### Cenário 2: Importação de CSV falha

**Sintoma:** "Importar" seleciona arquivo mas falha categorização

**Sinais:**
```json
{
  "error": "CSV parsing error",
  "file": "Extrato_BTG_Jul2026.csv",
  "encoding": "UTF-16",  // esperava UTF-8
  "categorization_success_rate": 0.60,
  "manual_review_queue": 15
}
```

**Causa raiz provável:**
1. Encoding mismatch (BTG é UTF-16, app espera UTF-8)
2. Regras de categorização incompletas
3. Formato CSV diferente do esperado

**Ações (Nível 2):**
1. Re-encode CSV to UTF-8
2. Add new categorization rule (permanente)
3. Re-import com regras atualizadas

#### Cenário 3: Parcelas não fecham

**Sintoma:** Soma das parcelas ≠ valor original (erro de arredondamento)

**Sinais:**
```json
{
  "error": "Parcel sum mismatch",
  "purchase": {
    "value": 150.00,
    "installments": 3,
    "parcel_values": [50.00, 50.00, 49.99],  // soma = 149.99
    "difference": -0.01
  }
}
```

**Causa raiz provável:**
1. Arredondamento na divisão (150 / 3 = 50.00, deixa 0.01)
2. Lógica de resíduo quebrada (deveria ir na última)

**Ações (Nível 2):**
1. Audit parcel logic (código)
2. Fix residue handling (permanente)
3. Recalculate existing parcels

---

## TranscritorNPU (Python + Gradio)

### Stack
- **Frontend:** Gradio (browser UI)
- **Backend:** Python 3.13 + OpenVINO GenAI
- **Acelerador:** Intel NPU (Meteor Lake+) ou GPU/CPU fallback
- **Entrada:** Audio/video files (qualquer formato via ffmpeg)
- **Saída:** `.txt` + `.srt` (com timestamps)
- **Criticidade:** 🟢 Baixa (acadêmico, sem produção)

### Sinais Críticos a Coletar

#### 1. App Health
```bash
# Check se Gradio está respondendo
curl -s http://localhost:7860/health | jq .

# Python process
ps aux | grep "python.*app.py"

# Port availability
netstat -ln | grep 7860
```

#### 2. GPU/NPU Status
```bash
# Intel Arc/NPU info
lsmod | grep -i gpu
# ou Windows Device Manager

# Current load
nvidia-smi  # se houver NVIDIA GPU
rocm-smi    # se houver AMD

# Memory
free -h
```

#### 3. Transcrição Performance
```bash
# Latência por dispositivo (logs da app)
grep "Transcription time" app.log

# Fila de jobs
curl http://localhost:7860/api/queue | jq .

# Modelo carregado?
ps aux | grep "whisper-large"
```

### Cenários de Falha (Nível 1)

#### Cenário 1: Transcrição muito lenta

**Sintoma:** Áudio 1min leva 10min pra transcrever

**Sinais:**
```json
{
  "symptom": "Transcription latency spike",
  "metrics": {
    "device": "NPU",
    "processing_time": 600000,  // 10min em ms
    "audio_duration": 60000,     // 1min
    "ratio": 10.0,
    "expected_ratio": 0.5  // NPU é 2x real-time
  },
  "logs": [
    {"info": "NPU cache warming (first call after reboot)"}
  ]
}
```

**Causa raiz provável:**
1. NPU warm-up (primeira chamada é lenta, cache rebuild)
2. GPU saturada (outro processo usando)
3. Modelo carregando do disco (deveria estar em VRAM)
4. Formato de audio não-suportado (conversão lenta)

**Ações (Nível 1 — diagnóstico):**
1. Check device selection (user pode ter escolhido CPU)
2. Monitor GPU memory
3. Suggest: "Se NPU, segunda transcrição será rápida"

#### Cenário 2: CUDA Out of Memory

**Sintoma:** "RuntimeError: CUDA out of memory"

**Sinais:**
```json
{
  "error": "CUDA out of memory",
  "gpu_memory_total": 2048,  // 2GB
  "gpu_memory_used": 2048,
  "available": 0,
  "model_size": 1500,  // 1.5GB
  "batch_size": 2
}
```

**Causa raiz provável:**
1. Batch size muito grande pra GPU
2. Múltiplas transcrições simultâneas
3. Modelo grande carregado + dados

**Ações (Nível 1):**
1. Reduce batch size (user-facing option)
2. Clear GPU cache
3. Suggest: "Use CPU or NPU se GPU small"

#### Cenário 3: ffmpeg não encontrado

**Sintoma:** "ffmpeg: command not found"

**Sinais:**
```json
{
  "error": "ffmpeg not in PATH",
  "paths_checked": ["/usr/bin", "/usr/local/bin", "~/.local/bin"],
  "found_in_none": true,
  "os": "Linux|Windows"
}
```

**Causa raiz provável:**
1. ffmpeg não instalado
2. ffmpeg instalado mas não no PATH

**Ações (Nível 1):**
1. Provide install command (apt, brew, choco)
2. Suggest: "Restart terminal after install"

---

## Tabela Comparativa

| Sistema | Stack | Criticidade | Nível Inicial | Sinais-Chave | Ação mais comum |
|---------|-------|-------------|---------------|--------------|-----------------|
| **RH** | Node + SQLite | 🔴 Alta | 2 | Pool/DB/VPN | Resize pool |
| **FinanWise** | Electron + JSON | 🟡 Média | 1 | Crashes/Data | Restore backup |
| **TranscritorNPU** | Python + Gradio | 🟢 Baixa | 1 | Latency/GPU | Diagnose |

---

## Qual começar?

### Semana 1-2: Sistema RH Nível 1
- Coletores básicos (health, logs, metrics)
- Correlator JSON
- Vê como funciona

### Semana 3-4: Sistema RH Nível 2
- Analyzer com Claude
- Actions (pool resize, etc)
- Team valida

### Semana 5-6: FinanWise Nível 1
- Coletores (crash, data integrity)
- Reutiliza framework genérico

### Semana 7+: TranscritorNPU Nível 1 (opcional)
- Monitoring passivo
- Baixa prioridade

---

## Roadmap Integrado

```
Semana 1-2   Nível 1
├─ RH: health + logs + pool metrics
├─ Correlator: junta tudo
└─ Diagnóstico manual

Semana 3-4   Nível 2
├─ RH: Analyzer + Claude
├─ Actions: pool resize (reversível)
└─ Team valida propostas

Semana 5-6   FinanWise Nível 1
├─ Crashes + data integrity
├─ Reutiliza coletores genéricos
└─ Diagnóstico automático

Semana 7-8   RH Nível 3 (se time pronto)
├─ Safe actions automáticas
├─ Executor + rollback
└─ Aprendizado contínuo

Futuro       TranscritorNPU (baixa prioridade)
└─ Monitoring + diagnóstico
```
