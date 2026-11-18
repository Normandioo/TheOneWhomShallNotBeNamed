---
tags: [sistema, tecnico]
---
# Modelo de Dados

Cada entidade tem identificador estável. Campos e relações tipados convivem com atributos personalizados.

| Registro | Conteúdo |
|---|---|
| Mundo e linha histórica | Planeta, calendário, unidades, linha de origem, data de separação, referência do presente |
| Entidade e versão | Identidade, tipo, validade, propriedades, estado de existência, versão anterior |
| Geometria e relação | Pontos, linhas e áreas versionados; vínculos com tipo, atributos e período |
| Grupo populacional | Local ou área, quantidade ou estimativa, ancestralidade, cultura, idioma, religião |
| Camada e bloco | Tipo, projeção, escala, resolução, versão, origem, unidades, ativo |
| Comando e acontecimento | Alteração, autoria, data do registro, data no mundo, efeitos |
| Regras e estado salvo | Versões dos modelos, sementes, marcos, estado materializado |
| Definição personalizada | Tipos, campos, enumerações, relações permitidas, formulários, migrações |

## Formato do projeto
- SQLite para registros, com índice espacial R*Tree (seguido do teste geométrico).
- Ativos grandes em arquivos, referenciados por manifesto versionado.
- Mudanças relacionadas numa transação; o ativo novo fica pronto antes de trocar a referência.
- Caches e miniaturas sempre reconstruíveis.
- Salvamento automático, backup do banco em uso, restauração pela interface; exportação documentada e interoperável, marcando as coordenadas como de Evron.

Ver [[Tempo e Histórico]] e [[Decisões Técnicas]].
