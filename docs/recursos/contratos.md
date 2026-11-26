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

## Catálogo, unidades e ocorrências (vale agora; migração 21)

- Categorias: Minerais, Vegetação, Animal, Manufatura (ou nenhuma). Manufatura são os produtos fabricados; as outras, recursos naturais.
- Cada bem tem uma unidade, de uma lista com dimensão (massa: kg, t; volume: m³, L; área: ha, km²; contagem: unidade, cabeça;
  energia: kcal) ou "outra" (texto). Não há conversão: receitas, estoques e reservas usam só a unidade do próprio bem.
- Trabalho em pessoas-dia; o mês tem a duração real (28 a 31 dias).
- Ocorrência: teor (%), profundidade (m), acesso, renovação por ano, política da reserva (normal, reposta pelo autor, bloqueada) e
  validade no tempo (existe de/até). Mudar a validade é uma mudança no mundo com data; mover no mapa é correção editorial.
- Quem conhece (cadastro, período, estimativa própria) e direitos (controle, acesso, exploração, com período) são registros à parte,
  sem desfazer, sem efeito automático na produção.
- A divisão de uma área entre países é uma consulta pelo território pintado: a ocorrência e a reserva continuam uma só.
- Não preenchido, desconhecido e zero são estados diferentes. Quantidade desconhecida não é estoque infinito.

## Tempo e produção (vale agora, etapa 3, primeira cadeia)

- Instantes = `int64` de segundos universais. A produção é um módulo do relógio: na meia-noite do dia 1 de cada mês, processa o
  mês que terminou. Consultar o passado não processa nada.
- O mês processado fica em `production_run`, na mesma transação dos estoques. O relógio é salvo em outro arquivo: se ele voltar a
  um mês já feito, o mês não se repete (o banco pode ficar à frente do relógio, nunca atrás).
- Estoque = soma de `stock_movement` (produção, consumo, intervenção), nunca negativo. Reserva restante = quantidade do autor menos
  o extraído (as movimentações com `occurrence_id`).
- O que sai num mês só pode ser usado no mês seguinte. Dentro do povoado, a ordem das atividades decide quem fica com os
  trabalhadores e os insumos. Entre povoados, só a reserva é disputada: se pedirem mais que ela, cada um leva a parte
  proporcional ao que pediu.
- Não há desfazer na configuração da produção nem nas intervenções: elas são histórico. Corrige-se com outra intervenção.
- Capacidade: a receita pode exigir que o povoado saiba algo; a prática (1 a 100%) multiplica o rendimento do trabalho.
- Instalações e ferramentas: bens do estoque que a receita exige e não gasta; cada unidade permite N vezes por mês.
- Insumos alternativos: o primeiro é gasto e, se faltar, o seguinte cobre.
- Renovação: a reserva volta (por ano × dias ÷ 365) até a quantidade dada; fica em `occurrence_state`, fora do desfazer.
- Estoque numa data = a soma das movimentações até ela. Totais por país = soma dos povoados no território (consulta).
- Ainda não existe: cultivo sazonal (etapa 6), transporte, consumo pela população, perdas no armazenamento, difusão de capacidades.

## Proteções e geração (valem agora, etapa 2)

- A geração só substitui ocorrências **geradas e não fixadas**. Manuais e fixadas nunca são alteradas nem apagadas.
- Editar uma gerada (pintar, mover, renomear, anotar, pegar com o conta-gotas) a **fixa**. "Fixada" pode ser ligada e desligada.
- Excluir uma gerada, ou tirá-la na prévia, grava uma **supressão**: sugestões com centro a até o raio dela (no máximo 200 km) ficam
  de fora. "Liberar sugestões removidas" apaga as supressões do recurso.
- Fixar e suprimir não mudam as outras sugestões: os centros são escolhidos antes de aplicar as proteções. A área do autor, porém,
  recorta as manchas vizinhas.
- Mesma regra, semente, mapas e relevo dão o mesmo resultado. Cada geração grava versão do algoritmo, regra, camadas e data.
- Prévia antes; aplicar é um comando só, com desfazer. Se o mundo mudou desde a prévia, aplicar é recusado.
- Limite: proteção é da ocorrência inteira; fixar um campo só não existe.
- Reservado (etapa 3): comportamento na simulação (suspender consumo, só apresentação ou reposição autoral), separado da proteção
  contra geração.

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
