# EXECUTOR — Guia de Uso

O pilar **ação** (Nível 2): roda ações seguras propostas pelo analyzer, sob gates de
segurança, com rollback automático e auditoria.

> **TL;DR:** `executor.sh`/`.ps1` recebe `--action <id>`, lê os gates da própria ação
> (`--describe`) e **roda em dry-run por padrão** (mostra o que faria + o rollback, sem tocar
> em nada). `--execute` é opt-in e ainda passa pelos gates.

## Humano no loop (o princípio)

O **analyzer PROPÕE** ("ação 1: aumentar pool 10→20"). Um **humano escolhe** e roda o
executor com a ação segura correspondente. Não há ponte automática diagnóstico→execução: o
texto da proposta do modelo não é um id estável, e — mais importante — ações que mudam estado
merecem um humano decidindo. Isso é intencional, não uma limitação.

## Como uma ação se descreve

Cada ação (`examples/<system>/actions/safe/<id>.sh` + `.ps1`) responde a 3 modos:

| Modo | O quê |
|------|-------|
| `--describe` / `-Describe` | Emite JSON **estático** (sem jq) com os gates + o rollback |
| `--run` / `-Run` | Faz a mudança e **verifica a pós-condição** |
| `--rollback` / `-Rollback` | Desfaz |

O `--describe` carrega: `id`, `reversible`, `requires_approval`, `requires_backup_first`,
`windows_admin_required`, `command`, `rollback` e um `prerequisite` opcional.

## Os gates de segurança

Ao rodar com `--execute`, o executor recusa se um gate não for satisfeito:

| Gate (no describe) | Exige | Se faltar |
|--------------------|-------|-----------|
| `requires_approval: true` | `--confirm` / `-Confirm` | recusa (exit 3) |
| `requires_backup_first: true` | `--skip-backup` / `-SkipBackup` (backup feito) | recusa (exit 3) |
| `windows_admin_required: true` | PowerShell elevado | recusa no `.ps1`; aviso no `.sh` |

Se o `--run` falhar (rc≠0), o executor **chama o `--rollback` automaticamente** e registra.

## Auditoria

Cada tentativa de `--execute` vira **uma linha JSONL** em `aiops.log` (ou `$AIOPS_LOG`):

```json
{"at":"2026-07-22T01:10:00Z","action":"increase-pool","mode":"execute","result":"success","rc":0}
```

`result` ∈ `success` · `rolled-back` · `rollback-failed`. Dry-run não registra (nada aconteceu).

## Rodar

```bash
# dry-run (padrão): mostra comando + rollback + gates + pré-requisito. Nada roda.
framework/executor.sh --action increase-pool

# execute (opt-in): roda de verdade, passando args pra ação depois do --
RH_TOKEN=... framework/executor.sh --action increase-pool --execute -- --size 20 --old 10
```

```powershell
.\framework\executor.ps1 -Action increase-pool
.\framework\executor.ps1 -Action increase-pool -Execute -ActionArgs @('-Size','20','-Old','10')
```

## Pré-requisito honesto

As ações do RH (`increase-pool`, `clear-cache`) dependem de endpoints admin que **ainda não
existem no Sistema RH** — ver [`examples/sistema-rh/actions/README.md`](../examples/sistema-rh/actions/README.md).
Por isso o `--execute` dessas ações só vai funcionar depois de implementar as rotas lá. O
**dry-run e o `--describe` funcionam agora** e não tocam a rede.

## Verificação estática (sem rodar / sem API)

```bash
bash -n framework/executor.sh
bash -n examples/sistema-rh/actions/safe/increase-pool.sh
# PowerShell: executor -Action increase-pool (dry-run) imprime gates + rollback,
#             e recusa --execute quando um gate não é satisfeito. Nada é executado.
```
