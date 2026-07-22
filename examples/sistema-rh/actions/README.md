# Ações do Sistema RH — Pré-requisitos

Ações **seguras** (reversíveis) que o `executor` roda sob os gates de segurança.
Cada ação tem par `.sh` + `.ps1` e três modos: `--describe`, `--run`, `--rollback`.

## ⚠ Pré-requisito NÃO atendido hoje (honestidade > demo)

As duas ações abaixo dependem de endpoints administrativos que **não existem no Sistema RH
atual** (confirmado no README do repo Sistema_RH — a API pública não tem rota de admin):

| Ação | Endpoint que precisa | Existe hoje? |
|------|----------------------|--------------|
| `increase-pool` | `POST /api/admin/pool-size` | ❌ **não** |
| `clear-cache` | `POST /api/admin/cache/clear` | ❌ **não** |

Ou seja: `--describe` e o **dry-run do executor funcionam agora** (não tocam a rede). Já o
`--run` (via `executor --execute`) só vai funcionar **depois** de implementar essas rotas no
Sistema RH. Não finjo que já roda.

### O que falta no Sistema RH (repo separado)
- Uma rota `POST /api/admin/pool-size` que aceite `{size}` e ajuste o pool vivo, e exponha
  `pool_size` no `GET /health` (o `increase-pool` verifica a pós-condição por aí).
- Uma rota `POST /api/admin/cache/clear` que invalide o cache.
- Ambas atrás do mesmo Bearer token (`RH_TOKEN`) das outras rotas.

## As ações

| Ação | O quê | Reversível | Aprovação | Backup antes |
|------|-------|-----------|-----------|--------------|
| `increase-pool` | pool 10→N (`--size`) | sim (`--old`) | não | não |
| `clear-cache` | invalida cache | sim (no-op) | não | não |

## Como o executor usa

O executor lê os gates do `--describe` da própria ação e **roda em dry-run por padrão**:

```bash
# dry-run: mostra comando + rollback + gates + pré-requisito. Não toca em nada.
framework/executor.sh --action increase-pool

# execute (opt-in): roda de verdade. Só funciona quando o endpoint existir.
RH_TOKEN=... framework/executor.sh --action increase-pool --execute -- --size 20 --old 10
```

```powershell
.\framework\executor.ps1 -Action increase-pool
.\framework\executor.ps1 -Action increase-pool -Execute -ActionArgs @('-Size','20','-Old','10')
```

## Adicionar uma ação segura

1. `actions/safe/<id>.sh` + `<id>.ps1` com os 3 modos.
2. `--describe` emite JSON estático (sem jq): `{id, reversible, requires_approval, requires_backup_first, windows_admin_required, command, rollback, prerequisite?}`.
3. `--run` faz a mudança e **verifica a pós-condição**; `--rollback` desfaz.
4. Se depender de algo que não existe ainda, declare em `prerequisite` e liste aqui.

> Detalhes dos gates e do fluxo do executor em [`../../../docs/EXECUTOR.md`](../../../docs/EXECUTOR.md).
