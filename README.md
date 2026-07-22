# troubleshootingAIOps

Framework de **observabilidade inteligente e automação operacional** para Cloud, DevOps e SRE. Transforma troubleshooting manual em fluxo estruturado com IA.

## O Problema

```
Hoje:
problema → SSH → comandos esparsos → contexto quebrado → pede ajuda IA → 30min

Com AIOps:
problema → Agent coleta/analisa/propõe → 2-5min + aprendizado
```

Troubleshooting hoje é **investigação manual com IA como consultora**. O contexto fica espalhado em mensagens, logs e memória. Este framework torna a IA o **orquestrador automático**.

## Os 4 Pilares

| Pilar | O quê | Como |
|-------|-------|------|
| **1. Coleta** | Sinais de tudo (logs, métricas, traces, eventos, health) | Coletores bash/PowerShell/Python por tipo de sistema |
| **2. Contexto** | Organiza sinais num modelo coeso de incidente | Correlação automática + estrutura JSON |
| **3. Análise** | Agent entende causa raiz, padrões, impacto | Claude + instruções especializadas |
| **4. Ação** | Sugere/executa/aprende | Reversível (nível 2), automática (nível 3) |

## Implementação em 3 Níveis

### Nível 1: Observabilidade Passiva
- ✅ Coletores rodam periodicamente, registram estado
- ✅ Agent lê contexto organizado e sugere diagnóstico
- ❌ Sem automação

**Tempo:** 1-2 sprints. **Benefício:** contexto pronto, sem garimpagem manual.

### Nível 2: Recomendação Inteligente
- ✅ Agent propõe ações específicas com confiança
- ✅ Você valida (clica [Aprovar] ou [Ignorar])
- ✅ Sistema aprende padrões

**Tempo:** +1-2 sprints. **Benefício:** diagnóstico + solução em 5min.

### Nível 3: Automação Segura
- ✅ Ações reversíveis são automáticas
- ✅ Ações destrutivas aguardam confirmação
- ✅ Feedback loop — cada incidente melhora o modelo

**Tempo:** +2-3 sprints. **Benefício:** MTTR cai 80%. Operação assimétrica.

## Estrutura

```
troubleshootingAIOps/
├── README.md
├── CLAUDE.md                    Regras do projeto
│
├── docs/
│  ├── ARQUITETURA.md           Os 4 pilares em detalhe
│  ├── NIVEIS.md                Camadas de implementação
│  ├── CASES.md                 Casos reais: Sistema RH, FinanWise, TranscritorNPU
│  └── PADROES.md               Como estender: novo sistema, novo collector
│
├── framework/
│  ├── collectors/              Coletores de sinais (reutilizáveis)
│  │  ├── generic/              SO, processos, arquivos
│  │  ├── nodejs/               Express, logs estruturados, endpoints
│  │  ├── electron/             Crashes, memory, FPS
│  │  └── python/               Imports, threads, GPU
│  │
│  ├── correlator.md            Instruções: como juntar sinais
│  ├── analyzer.md              Prompt para o Agent AIOps
│  │
│  └── actions/                 Scripts de remediação
│     ├── safe/                 Reversíveis (auto em Nível 3)
│     └── manual/               Requerem confirmação
│
├── examples/
│  ├── sistema-rh/              Integração pronta — Nível 2
│  │  ├── .claude/              Agent config específico
│  │  ├── collectors/           Queries SQL, checks de saúde
│  │  ├── actions/              restart_db_pool, invalidate_cache
│  │  └── SETUP.md
│  │
│  ├── finanwise/               Exemplo em desenvolvimento
│  │
│  └── transcritor-npu/         Placeholder
│
└── PLANO.md                    Diário de bordo + retomada rápida
```

## Começar

### 1. Leia a documentação

```bash
# Visão: os 4 pilares
cat docs/ARQUITETURA.md

# Como implementar progressivamente
cat docs/NIVEIS.md

# Casos reais
cat docs/CASES.md
```

### 2. Explore o exemplo Sistema RH

```bash
cd examples/sistema-rh/
cat SETUP.md
```

Este exemplo já tem:
- ✅ Coletores de saúde do Express + SQLite
- ✅ Correlator que junta sintomas
- ✅ Analyzer que propõe diagnóstico
- ✅ Actions seguras (reinicia pool, invalida cache)

### 3. Estenda para seu sistema

Ver `docs/PADROES.md` — template pra adicionar novo sistema em 10 min.

## Filosofia

- **Sem magia:** cada collector é um script simples, entendível
- **Reutilizável:** coletores genéricos valem pra qualquer app similar
- **Progressivo:** começa sem automação, cresce conforme aprende
- **Transparente:** Agent propõe, você vê raciocínio, aprova
- **Humano no loop:** até Nível 3, você sempre sabe o que vai rodar

## Status

| Componente | Status | Notas |
|------------|--------|-------|
| Arquitetura | ✅ Documentada | 4 pilares + 3 níveis |
| Framework genérico | ✅ Completo | analyzer · correlator · executor · test runner (par .sh/.ps1, dry-run por padrão) |
| Sistema RH (ex.) | ✅ Pipeline pronto | coletores + manifesto + 5 fixtures/golden + ações seguras (offline; `--execute` precisa dos endpoints admin) |
| FinanWise (ex.) | ⏳ Planejado | Nível 1 |
| TranscritorNPU (ex.) | ⏳ Planejado | Nível 1 |

> **Preparação, não produção:** todo script que toca rede ou muda estado nasce em **dry-run**;
> `--execute` é opt-in e ainda não foi rodado (não gasta crédito por acidente). A cadeia inteira
> é demonstrável offline — ver `docs/CORRELATOR.md`, `docs/ANALYZER.md`, `docs/EXECUTOR.md`.

---

**Objetivo final:** framework reutilizável que qualquer dev de operações possa integrar aos seus repos em meia hora.
