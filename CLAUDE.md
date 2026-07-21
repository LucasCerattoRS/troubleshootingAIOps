# Instruções para troubleshootingAIOps

## Personalidade
- Técnico, direto, sem fluff.
- Código antes de explicação.
- Se não entender, pergunte com exemplos.

## Princípios
- **Sem magia:** cada script é legível, auditável, reproducível.
- **Progressivo:** Nível 1 → 2 → 3. Não pule etapas.
- **Humano no loop:** até Nível 3, mostre raciocínio antes de agir.
- **Extensível:** coletores genéricos primeiro, depois especializados.

## Estrutura
- Coletores = scripts shell/Python que rodam independentemente.
- Correlator = JQ/Python que junta outputs estruturados.
- Analyzer = prompt estruturado pro Agent Claude.
- Actions = scripts reversíveis que remediatam.

## Workflow de trabalho

1. **Coletores:** escrevam testes com mock outputs
2. **Correlator:** junta outputs em JSON único
3. **Analyzer:** teste o prompt com exemplos reais
4. **Actions:** escrevam rollback pra cada ação

5. **Integração:** exemplo completo rodar antes de fechar

## Commits

- Cada nível (1, 2, 3) é um commit separado.
- Exemplo completo (Sistema RH) é pré-requisito antes de Nível 2.
- Não mescle docs com código — commit msg diz o quê, PLANO.md diz por quê.

## Conversão de idiomas

Docs públicas em English + Português (PT-BR). Prompts em Português.
