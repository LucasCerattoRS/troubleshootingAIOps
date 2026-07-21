# PLANO — Roadmap e Retomada

## Status Atual (21/07/2026)

### Fase 1: Arquitetura ✅
- [x] README.md — visão geral
- [x] CLAUDE.md — guias de trabalho
- [x] docs/ARQUITETURA.md — 4 pilares em detalhes
- [x] docs/NIVEIS.md — progressão 1→2→3
- [x] docs/CASES.md — casos reais (RH, FinanWise, TranscritorNPU)
- [x] framework/correlator.md — template de correlação

### Fase 2: Framework Genérico (Analyzer COMPLETO)
- [x] framework/analyzer.md — design do analyzer
- [x] framework/analyzer-template.prompt — prompt genérico (contrato de saída)
- [x] framework/analyzer.sh + analyzer.ps1 — funcionais, **dry-run por padrão**
- [x] docs/ANALYZER.md — guia de uso (flags, API, extensão, verificação)
- [x] generic/health.sh + health.ps1
- [ ] Coletores genéricos restantes (metrics, logs, events) — .sh + .ps1
- [ ] framework/correlator.sh + correlator.ps1 (hoje só correlator.md)
- [ ] framework/executor.sh + executor.ps1 (executa actions, Nível 2+)

### Fase 3: Sistema RH Nível 1-2 (Analyzer + fixtures prontos)
- [x] examples/sistema-rh/analyzer.md (especializado — 5 padrões)
- [x] examples/sistema-rh/collectors/express-health.sh + express-health.ps1
- [x] examples/sistema-rh/test-incidents/ — 5 fixtures + 5 golden + README
- [ ] collectors restantes: sqlite-health, logs, metrics, tailscale-status (.sh + .ps1)
- [ ] actions/safe/ (reversíveis)
    - [ ] increase-pool.sh + .ps1
    - [ ] clear-cache.sh + .ps1

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

## Progresso 21/07/2026 (noite) — Analyzer completo

Fechado o **analyzer** como peça de preparação (nada roda até `--execute`):
prompt genérico + especializado do RH, `analyzer.sh`/`.ps1` funcionais em dry-run,
5 fixtures de incidente + 5 golden, pares `.ps1` dos coletores, `docs/ANALYZER.md`.
Decisões travadas com o Lukas: scripts em **par .sh + .ps1**; profundidade **todos**.

## Próxima Sessão — O que fazer

1. **Coletores restantes** (par .sh + .ps1): metrics, logs, events, sqlite-health, tailscale-status.
2. **correlator.sh + correlator.ps1** — hoje só existe o `correlator.md` (design). Fazer o script que junta os coletores no JSON de incidente que o analyzer consome.
3. **executor.sh + executor.ps1** (Nível 2) — actions reversíveis (increase-pool, clear-cache) com rollback.
4. **Test runner** — roda cada fixture pelo analyzer e compara campos-chave (não diff literal) contra o `.expected.json`.
5. **Rodar o dry-run** de ponta a ponta e, quando o Lukas autorizar gasto de crédito, um `--execute` de validação.

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
