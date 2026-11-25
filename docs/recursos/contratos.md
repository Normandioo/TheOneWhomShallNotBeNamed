# Recursos: contratos (etapa 0)

Base: `Plano_Recursos_Populacao_Economia_Evron_v1.pdf` (25/11/2026). Este documento fixa o que as etapas seguintes não podem
quebrar. "Vale agora" = implementado na etapa 1. "Reservado" = decidido, ainda sem tabela nem código.

## Identidade e mundo (vale agora)

- Tipo de recurso e ocorrência têm ID inteiro próprio, `autoincrement`: um ID excluído nunca é reusado por outro registro.
  Desfazer uma exclusão devolve o mesmo ID.
- Os dois apontam para `world(id)`.
- Só o nome é obrigatório no tipo. Na ocorrência, só o tipo e a geometria.

## Geometria (vale agora)

- Ocorrência é **ponto** (um local pequeno) ou **área pintada**. Não há contorno desenhado ponto a ponto nem disco.
- A área é pintada como os países: pincel, balde, borracha, conta-gotas e fronteira, na mesma grade (~9,8 km por pixel).
- Uma camada por recurso (`recurso:<id do tipo>`); o dono de cada pixel é o ID da ocorrência. Recursos diferentes se sobrepõem;
  duas ocorrências do mesmo recurso, não. O ID de uma área vai até 65.534.
- Ocorrência não é `place`: jazidas não entram nos menus de lugares.
- Uma ocorrência sobre várias regiões ou países é uma só. Dividir por país será participação espacial, nunca cópia.
- Percurso (linha) e "referência a uma região" ainda não existem.

## Unidades (reservado, etapa 3)

- Massa em kg, água em m³, superfície em m² (hectare com conversão explícita), alimento também em energia alimentar,
  trabalho em pessoas-dia, tempo em segundos do relógio universal.
- Converter entre dimensões diferentes é recusado no cálculo. O cadastro narrativo aceita qualquer texto como unidade.
- Não preenchido, desconhecido, não aplicável e zero são estados diferentes. Quantidade desconhecida não é estoque infinito.

## Tempo (reservado, etapa 3)

- Instantes = `int64` de segundos universais; validade `[início, fim)`.
- Catálogo e ocorrências da etapa 1 são cadastros editoriais, sem validade: mover para corrigir o mapa não é um acontecimento
  do mundo.
- O relógio é salvo em JSON, fora do SQLite. **Antes da etapa 3**, o estado de execução da simulação tem de ficar na mesma
  transação dos estoques, para uma interrupção não repetir colheita, consumo ou entrega.

## Proveniência (vale agora)

- `origin` da ocorrência: `manual`, `importada` ou `gerada`. A etapa 1 só cria `manual`.
- `state`: `narrativo` ou `simulado`. A etapa 1 só tem `narrativo`: nada é calculado, e a interface não finge calcular.
- Camada do Gleba é dado de um mundo gerado, não levantamento. Toda derivação guardará algoritmo, versão, parâmetros,
  camadas e data.

## Proteções (reservado, etapa 2)

- Ocorrência `manual` nunca é alterada nem apagada por geração.
- São dois controles separados: proteção contra geração (por ocorrência ou campo) e comportamento na simulação (por campo,
  com política explícita: suspender consumo, só apresentação ou reposição autoral).
- Remover uma sugestão gerada grava uma supressão, para a mesma sugestão não voltar.
- Geração tem prévia; aplicar é um comando só, com desfazer.

## Desfazer (vale agora)

- Cada operação do catálogo ou de ocorrência é um comando na pilha comum (`command_stack.gd`), junto com terreno e território.
- O comando (`ResourceEdit.cs`) guarda a linha inteira antes e depois. A pintura é um `TerritoryEdit`. Excluir uma área junta os
  dois num comando só. Desfazer restaura a operação completa.
- O catálogo é gravado na hora; a pintura, ~1,5 s depois, como a dos países. Desfazer também grava. A pilha não sobrevive a fechar o programa.
- Um tipo com ocorrências não pode ser excluído (exclua ou mude as ocorrências antes): nada some em cascata.
- Editar campos de domínio (países, culturas...) continua sem desfazer.

## Integração com o banco (conferida na etapa 1)

- Migração nova no fim de `Registry.Migrations`; nenhuma antiga muda. Banco de versão maior é recusado.
- Exportar e importar `.world` copiam o banco inteiro (`VACUUM INTO`), então as tabelas novas vão junto.
