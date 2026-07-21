# ANALYZER — Guia de Uso

Como rodar o analyzer, o que cada flag faz, e como estender.

> **TL;DR:** `analyzer.sh`/`.ps1` pega o JSON de um incidente, monta o prompt
> especializado do sistema, e (só com `--execute`) chama o Claude para diagnosticar +
> propor ações. **Roda em `--dry-run` por padrão** — não toca a rede, não gasta crédito.

## Peças

| Arquivo | Papel |
|---------|-------|
| [`framework/analyzer.md`](../framework/analyzer.md) | Design: o que o analyzer faz, desafios, output |
| [`framework/analyzer-template.prompt`](../framework/analyzer-template.prompt) | Prompt **genérico** (contrato de diagnóstico/impacto/ações) |
| [`examples/<sistema>/analyzer.md`](../examples/sistema-rh/analyzer.md) | Prompt **especializado** por sistema (padrões conhecidos) |
| `framework/analyzer.sh` / `analyzer.ps1` | O script que monta tudo e chama a API |
| [`examples/sistema-rh/test-incidents/`](../examples/sistema-rh/test-incidents/) | Fixtures de entrada + saídas golden |

O prompt final = **template genérico** + **especializado do sistema** + **JSON do incidente**.

## Rodar (Linux/macOS — Bash)

```bash
# DRY-RUN (padrão): monta e imprime o prompt + o request. Sem rede, sem chave, sem custo.
framework/analyzer.sh --incident-file examples/sistema-rh/test-incidents/case-pool-exhausted.json

# EXECUTE (opt-in explícito): chama a API. Exige ANTHROPIC_API_KEY.
framework/analyzer.sh \
  --incident-file examples/sistema-rh/test-incidents/case-pool-exhausted.json \
  --execute --output /tmp/diag.json
```

## Rodar (Windows — PowerShell)

```powershell
# DRY-RUN (padrao)
.\framework\analyzer.ps1 -IncidentFile .\examples\sistema-rh\test-incidents\case-pool-exhausted.json

# EXECUTE (opt-in)
$env:ANTHROPIC_API_KEY = "<sua-chave>"
.\framework\analyzer.ps1 -IncidentFile .\examples\sistema-rh\test-incidents\case-pool-exhausted.json -Execute -Output diag.json
```

## Flags

| Bash | PowerShell | Default | O quê |
|------|-----------|---------|-------|
| `--incident-file` | `-IncidentFile` | (obrigatório) | JSON do incidente (saída do correlator ou uma fixture) |
| `--system` | `-System` | `sistema-rh` | Procura `examples/<system>/analyzer.md` |
| `--confidence-threshold` | `-ConfidenceThreshold` | `0.70` | Abaixo disso, o modelo deve retornar `actions: []` e pedir mais dados |
| `--model` | `-Model` | `claude-opus-4-8` | Model ID da Messages API |
| `--output` | `-Output` | stdout | Salva o diagnóstico num arquivo |
| `--dry-run` | *(padrão)* | ✅ ligado | Monta e imprime; **não** chama a API |
| `--execute` | `-Execute` | desligado | Chama a API (exige `ANTHROPIC_API_KEY`) |

## Como a chamada à API é montada

Baseado na skill `claude-api` (projeto shell → raw HTTP):

- **Endpoint:** `POST https://api.anthropic.com/v1/messages`
- **Headers:** `x-api-key: $ANTHROPIC_API_KEY`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- **Body:** `model` (`claude-opus-4-8`), `max_tokens: 8000`, `thinking: {type:"adaptive"}`, `output_config: {effort:"high"}`, e uma mensagem `user` com o prompt montado.
- **Saída:** o diagnóstico JSON vem no bloco `text` da resposta (blocos de `thinking` são pulados) e é validado com `jq` / `ConvertFrom-Json`.

> **Autenticação:** o script lê `ANTHROPIC_API_KEY` do ambiente. O Lukas rotaciona
> contas via `/login` para renovar o teto de crédito — exporte a chave da conta ativa
> antes de `--execute`. (Alternativa OAuth via `ant auth`: ver a skill `claude-api`.)

## Garantir JSON válido (endurecimento opcional)

Hoje o contrato JSON é **instruído no prompt** e validado depois da resposta. Para
*garantia* de JSON no nível da API, dá pra adicionar `output_config.format` com um
`json_schema` no corpo da requisição (structured outputs, suportado no Opus 4.8). Ficou
fora por enquanto pra manter o script legível — é o próximo passo natural de robustez.

## Adicionar um novo padrão

1. Documente o padrão em `examples/<sistema>/analyzer.md` (sinais, causa, confiança, ações).
2. Crie uma fixture `examples/<sistema>/test-incidents/case-<nome>.json` que dispare esses sinais.
3. Crie o golden `case-<nome>.expected.json` com o diagnóstico correto.
4. Rode `--dry-run` e confira que o incidente entra no prompt como esperado.

## Adicionar um novo sistema

1. `examples/<novo-sistema>/analyzer.md` — especialização (copie o do RH como molde).
2. `examples/<novo-sistema>/collectors/` — coletores que produzem os `signals`.
3. Rode com `--system <novo-sistema>`.

## Verificação estática (sem rodar / sem API)

```bash
# JSON das fixtures e golden é válido?
for f in examples/sistema-rh/test-incidents/*.json; do jq empty "$f" && echo "ok: $f"; done

# Sintaxe do Bash (não executa)
bash -n framework/analyzer.sh

# Sintaxe do PowerShell (não executa)
powershell -NoProfile -Command "[void][ScriptBlock]::Create((Get-Content -Raw .\framework\analyzer.ps1))"
```
