# CORRELATOR — Guia de Uso

Como o correlator junta os coletores no JSON de incidente que o analyzer consome.

> **TL;DR:** `correlator.sh`/`.ps1` roda os coletores listados num **manifesto** e monta
> `{incident, symptoms, signals{...}}`. Com `--mock-dir` ele lê saídas pré-gravadas — prova o
> shape **offline, sem rede, sem API, sem crédito**.

## Onde ele fica na cadeia

```
coletores  →  CORRELATOR  →  analyzer  →  executor
 (sinais)     (contexto)     (análise)    (ação)
```

O correlator é a peça que **produz a entrada do analyzer**. Antes dele, o analyzer só tinha
as fixtures escritas à mão em `test-incidents/`.

## Manifesto (o que rodar)

Cada sistema tem um `examples/<sistema>/collectors.manifest.json` que mapeia cada slot de
`signals` para um coletor. Como Bash e PowerShell chamam os coletores com convenções
diferentes, cada slot carrega os dois:

```json
{
  "system": "sistema-rh",
  "window_minutes": 3,
  "signals": {
    "application": {
      "mock": "express-health.json",
      "sh":  { "collector": "examples/sistema-rh/collectors/express-health.sh",  "args": [] },
      "ps1": { "collector": "examples/sistema-rh/collectors/express-health.ps1", "args": [] }
    }
    // ... database, system, network, events
  }
}
```

O correlator `.sh` lê `.sh`; o `.ps1` lê `.ps1`. Em `--mock-dir`, ambos leem `.mock`.

## Rodar

### Modo mock (offline — o que dá pra provar sem nada rodar de verdade)

```bash
# Bash
framework/correlator.sh \
  --manifest examples/sistema-rh/collectors.manifest.json \
  --mock-dir examples/sistema-rh/mock-signals
```

```powershell
# PowerShell
.\framework\correlator.ps1 `
  -Manifest .\examples\sistema-rh\collectors.manifest.json `
  -MockDir  .\examples\sistema-rh\mock-signals
```

Lê os 5 arquivos de `mock-signals/` (um snapshot pool-exhausted de exemplo) e emite o
incidente. **Não abre socket, não roda coletor, não chama a API.**

### Modo ao vivo (na máquina do sistema)

```bash
framework/correlator.sh --manifest examples/sistema-rh/collectors.manifest.json --output /tmp/incident.json
```

Roda os coletores de verdade. No RH, isso só faz sentido **na empresa** (banco + Tailscale).

## Cadeia completa (coletores → correlator → analyzer)

```bash
framework/correlator.sh --manifest examples/sistema-rh/collectors.manifest.json \
  --mock-dir examples/sistema-rh/mock-signals --output /tmp/incident.json
framework/analyzer.sh --incident-file /tmp/incident.json          # dry-run (padrão)
```

Provado nesta sessão em PowerShell (ambiente sem jq): mock → correlator → arquivo →
analyzer dry-run monta o prompt com o incidente embutido, **sem tocar a API**.

## Garantia de shape (o critério que importa)

A saída do correlator casa, no **nível de envelope e slots**, com as fixtures
`examples/sistema-rh/test-incidents/case-*.json`:

- top-level: `incident` · `symptoms` · `signals`
- `signals`: `application` · `database` · `system` · `network` · `events`

Os **campos dentro de cada slot** vêm dos coletores e podem ser mais ricos que as fixtures
ilustrativas — o analyzer lê os sinais de forma flexível (ex.: `db.pool.active`,
`application.logs`, `database.integrity_check`).

> **Nota sobre `symptoms`:** o correlator emite `symptoms: []`. Sintomas são inferência —
> hoje ficam a cargo do analyzer a partir dos `signals`. Um passo futuro pode derivar
> `symptoms` por regra no correlator.

## Resiliência

Se um coletor falha (não instalado, host fora, saída inválida), **o slot recebe um JSON de
erro e o incidente continua** — um sinal quebrado não derruba o diagnóstico inteiro.

## Verificação estática (sem rodar / sem API)

```bash
bash -n framework/correlator.sh
# PowerShell: [PSParser]::Tokenize sobre correlator.ps1
# Prova de shape (offline): correlator.ps1 -MockDir ... e comparar os slots com uma fixture
```
