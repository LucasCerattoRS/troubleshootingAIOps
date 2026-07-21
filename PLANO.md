# PLANO — Roadmap e Retomada

## Status Atual (21/07/2026)

### Fase 1: Arquitetura ✅
- [x] README.md — visão geral
- [x] CLAUDE.md — guias de trabalho
- [x] docs/ARQUITETURA.md — 4 pilares em detalhes
- [x] docs/NIVEIS.md — progressão 1→2→3
- [x] docs/CASES.md — casos reais (RH, FinanWise, TranscritorNPU)
- [x] framework/correlator.md — template de correlação

### Fase 2: Framework Genérico (Em progresso)
- [ ] Coletores genéricos (bash/ps1)
  - [ ] generic/health.sh
  - [ ] generic/metrics.sh
  - [ ] generic/logs.sh
  - [ ] generic/events.sh
- [ ] framework/analyzer.md — prompt template
- [ ] framework/analyzer.sh — executa analyzer
- [ ] framework/executor.sh — executa actions (Nível 2+)

### Fase 3: Sistema RH Nível 1-2 (Próxima)
- [ ] examples/sistema-rh/
  - [ ] collectors/
    - [ ] express-health.sh
    - [ ] sqlite-health.sh
    - [ ] logs.sh
    - [ ] metrics.sh
  - [ ] analyzer.md (especializado pra RH)
  - [ ] actions/safe/ (reversíveis)
    - [ ] increase-pool.sh
    - [ ] clear-cache.sh

### Fase 4: Integração GitHub Actions (Depois)
- [ ] .github/workflows/aiops-collect.yml
- [ ] .github/workflows/aiops-analyze.yml
- [ ] Slack integration

### Fase 5: FinanWise Nível 1 (Depois de RH funcionar)
- [ ] examples/finanwise/
- [ ] Coletores de crashes, data integrity
- [ ] Analyzer especializado

### Fase 6: Nível 3 (Depois de 3+ meses Nível 2)
- [ ] Executor com automação
- [ ] Rollback automático
- [ ] Learning loop

---

## Próxima Sessão — O que fazer

1. **Criar coletores genéricos**
   - Bash scripts simples (Linux/macOS) e PowerShell (Windows)
   - Cada um retorna JSON
   - Sem dependências externas (apenas curl, jq)

2. **Criar exemplo completo para Sistema RH**
   - Coletores específicos (express health, sqlite health)
   - Analyzer prompt especializado
   - Testar com exemplos reais de incidente

3. **Validar framework**
   - Rodar correlator + analyzer manualmente
   - Verificar JSON estrutura
   - Documentar padrões

---

## Decisões Tomadas

### Bash (não Go/Python)
- ✅ Simples, legível, reutilizável
- ✅ Já está no sistema (não precisa instalar)
- ✅ Melhor pra DevOps scripts

### JSON (não YAML)
- ✅ Estruturado, queryable via jq
- ✅ Fácil de versionr/diffo
- ✅ Analyzer (Claude) entende bem

### Claude como Analyzer
- ✅ Contexto entende nuances
- ✅ Pode raciocinar sobre correlações
- ✅ Código fica simples (framework), IA faz lógica pesada

### Progressivo (Nível 1→2→3)
- ✅ Começa observável, cresce pra automático
- ✅ Permite build confiança
- ✅ Risco baixo no início

---

## Notas de Design

### Princípio: Humano no loop
- Até Nível 3, você vê raciocínio antes de ação
- Nunca automação surpresa
- Aprendizado é feedback humano + histórico

### Princípio: Reutilizável
- Coletores genéricos servem todo sistema similar
- Analyzer prompt é template, não hardcoded
- Actions são scripts standalone

### Princípio: Reversível
- Cada ação tem rollback
- Logging de tudo
- Histórico completo pra auditoria

---

## Métricas de Sucesso

### Curto prazo (Nível 1)
- ✅ Correlator roda sem erro
- ✅ JSON bem-formado sempre
- ✅ Coletores rápidos (<10s total)

### Médio prazo (Nível 2)
- ✅ Analyzer propõe diagnóstico
- ✅ Confiança >80% em propostas
- ✅ MTTR cai de 30min para 5min

### Longo prazo (Nível 3)
- ✅ Ações safe 100% automáticas
- ✅ Zero manual intervention pra casos conhecidos
- ✅ Aprendizado melhora confiança 90%+ em 3+ meses

---

## Contatos / Documentação Externa

- Claude API: `ANTHROPIC_API_KEY` (set in .env)
- Sistema RH repo: C:\Users\LuKas\Projetos\Sistema_RH
- FinanWise repo: C:\Users\LuKas\Projetos\FINAN
- TranscritorNPU repo: C:\Users\LuKas\TranscritorNPU
