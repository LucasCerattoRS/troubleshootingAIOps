# Test Incidents — Fixtures Golden do Sistema RH

Pares de **entrada** (`case-*.json`) e **saída esperada** (`case-*.expected.json`) que
exercitam cada padrão documentado em [`../analyzer.md`](../analyzer.md).

## Os 5 casos

| Fixture | Padrão | Confiança esperada | Ação #1 esperada |
|---------|--------|--------------------|------------------|
| `case-pool-exhausted` | Pool exhausted | 0.95 | Aumentar pool 10→20 (reversível) |
| `case-vpn-down` | VPN disconnected | 0.99 | Reconectar Tailscale |
| `case-db-corrupt` | DB corrupted | 0.99 | Restaurar do último backup |
| `case-memory-leak` | Memory leak | 0.80 | Reiniciar Express |
| `case-slow-query` | Slow query | 0.75 | Adicionar índice |

Os 3 primeiros são citados diretamente na doc do analyzer; os 2 últimos completam a
tabela de padrões.

## Formato

- **Entrada** (`case-*.json`) segue o schema de incidente do
  [`framework/correlator.md`](../../../framework/correlator.md):
  `{ incident, symptoms[], signals{application,database,system,network,events} }`.
  Os blocos de `signals.application` / `signals.database` espelham a saída dos coletores
  (`../collectors/express-health.sh`).
- **Saída esperada** (`case-*.expected.json`) segue o contrato de saída do
  [`framework/analyzer-template.prompt`](../../../framework/analyzer-template.prompt):
  `{ diagnosis, impact, actions[], metadata }` + as especializações do RH
  (`requires_backup_first`, `windows_admin_required`, `estimated_data_loss`).

## Como usar (quando for rodar — não roda agora)

O `analyzer.sh` roda em **`--dry-run` por padrão** (monta o prompt, não chama a API):

```bash
# Ver o prompt que SERIA enviado (sem rede, sem chave, sem custo)
../../../framework/analyzer.sh --incident-file case-pool-exhausted.json --dry-run

# Rodar de verdade (opt-in explícito; exige ANTHROPIC_API_KEY)
../../../framework/analyzer.sh --incident-file case-pool-exhausted.json --execute \
  > /tmp/out.json

# Comparar com o golden
diff <(jq -S . case-pool-exhausted.expected.json) <(jq -S . /tmp/out.json)
```

> **Sobre os golden:** foram escritos à mão como referência do comportamento *correto*.
> A saída real do modelo não será idêntica byte a byte (linguagem natural varia) — o valor
> está em `diagnosis.root_cause`, `confidence` na faixa certa, e a **ação #1** bater.
> Os `similar_incidents` são ilustrativos: ainda **não há store de histórico** de incidentes.

## Futuro (fora de escopo agora)

Um test runner que rode cada fixture pelo analyzer e compare campos-chave contra o
`.expected.json` (não diff literal) — está no roadmap do [`../../../PLANO.md`](../../../PLANO.md).
