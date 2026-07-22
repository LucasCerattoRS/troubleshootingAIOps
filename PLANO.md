# PLANO — Roadmap e Retomada

## Status Atual (21/07/2026)

### Fase 1: Arquitetura ✅
- [x] README.md — visão geral
- [x] CLAUDE.md — guias de trabalho
- [x] docs/ARQUITETURA.md — 4 pilares em detalhes
- [x] docs/NIVEIS.md — progressão 1→2→3
- [x] docs/CASES.md — casos reais (RH, FinanWise, TranscritorNPU)
- [x] framework/correlator.md — template de correlação

### Fase 2: Framework Genérico ✅ (pipeline inteiro em par .sh/.ps1)
- [x] framework/analyzer.md + analyzer-template.prompt — design + prompt genérico
- [x] framework/analyzer.sh + analyzer.ps1 — funcionais, **dry-run por padrão**
- [x] Coletores genéricos: health, metrics, logs, events (.sh + .ps1)
- [x] framework/correlator.sh + correlator.ps1 — dirigido por manifesto, --mock-dir
- [x] framework/executor.sh + executor.ps1 — gates + rollback + auditoria JSONL
- [x] framework/test-analyzer.sh + .ps1 — runner offline (dry-run) + --execute
- [x] docs/ANALYZER.md, CORRELATOR.md, EXECUTOR.md

### Fase 3: Sistema RH Nível 1-2 ✅
- [x] analyzer.md especializado (5 padrões)
- [x] Coletores: express-health, sqlite-health, tailscale-status (.sh + .ps1)
- [x] collectors.manifest.json + mock-signals/ (5 arquivos)
- [x] test-incidents/ — 5 fixtures + 5 golden + README
- [x] actions/safe/ — increase-pool + clear-cache (.sh + .ps1, 3 modos) + README
      ⚠ pré-req: endpoints /api/admin/* NÃO existem no Sistema RH ainda

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

## Progresso 21/07/2026 (noite) — Pipeline inteiro fechado (preparação)

Roadmap "tudo" concluído em 4 commits (A coletores, B correlator, C executor, D test runner).
A cadeia **coletores → correlator → analyzer → executor** existe de ponta a ponta e roda
**offline** (dry-run/mock), nada toca a API. Provado nesta sessão em PowerShell (sem jq no
ambiente): correlator --mock-dir bate o shape das fixtures; cadeia coletores(mock)→correlator→
analyzer(dry-run) monta o prompt; executor dry-run mostra gates + rollback; test-analyzer
offline 5/5 PASS.

## Próxima Sessão — O que fazer

1. **Validação com crédito** (decisão do Lukas): `analyzer.sh --execute` e `test-analyzer.sh --execute` numa fixture, pra ver o diagnóstico real do modelo vs golden.
2. **Sistema RH — endpoints admin**: implementar `POST /api/admin/pool-size` e `/api/admin/cache/clear` no repo Sistema_RH pra destravar o `executor --execute` (ver actions/README.md).
3. **Correlator ao vivo na empresa**: rodar `correlator.sh` sem `--mock-dir` na máquina do RH (precisa banco + Tailscale).
4. **Opcional**: derivar `symptoms` por regra no correlator; GitHub Actions (Fase 4); exemplo FinanWise (Fase 5).

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
