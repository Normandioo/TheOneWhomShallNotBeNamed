# Arquitetura do projeto

Gerenciador do mundo de Evron (proposta: `docs/Proposta_Projeto_Evron_RPG.pdf`, se presente). Godot 4.7 **.NET**: GDScript em quase tudo e C# no
núcleo de edição do terreno (os laços pixel a pixel), onde o GDScript era 10 a 17× mais lento.
Base copiada do Projeto Marte: a arquitetura, a câmera, o globo e os testes; o que era de Marte e do sistema solar saiu.

A regra que separa as camadas: **o mundo não conhece a tela**. Ele avisa por sinais, e quem mostra (vista e
interface) escuta. Assim dá para testar o mundo sem nenhum nó, e trocar a interface sem mexer nas regras.

```
scripts/
  main.gd          raiz de composição: cria os módulos, liga os sinais, roda o quadro. Sem regra do mundo.
  data/            o planeta e os mapas. Só funções estáticas.
    evron_geo.gd     raio (6.371 km, a Terra), lat/lon <-> direção <-> pixel, distância pela superfície
    EvronGeo.cs      a mesma convenção para o núcleo em C#
    evron_maps.gd    lê data/evron/: a altitude calibrada (float32) e as camadas PNG
    WorldDb.cs       (C#) SQLite do mundo: abrir, migrar por `user_version`, consultas com parâmetros, transação
  world/           o estado do mundo, sem tela.
    Terrain.cs       a altitude em memória (float[]) e os rios (byte[]); disco do pincel na esfera; vizinhos D8;
                     entrega as imagens para a GPU copiando só as linhas mexidas
    Registry.cs      (C#) os seis cadastros de domínio: entidades, nomes com papel e validade, vínculos tipados e datados
    RegistrySheet.cs (C#, parte do Registry) a ficha: campos como dados, valores, etiquetas, busca, duplicar, excluir, sociedade
    RegistryCalendar.cs (C#, parte do Registry) calendários locais, eras e o uso por entidade, com validade
    local_calendar.gd conversão universal <-> calendário local (funções sobre uma definição; usa o calendar.gd)
    RegistryPlaces.cs (C#, parte do Registry) lugares (ponto ou disco), presenças no mapa, estimativas e distribuições demográficas
    RegistryBorders.cs (C#, parte do Registry) lugares com contorno desenhado à mão (polígono de vértices lat/lon)
    PlaceGeometry.cs (C#) geometria do contorno na esfera: validar, centro, área, "está dentro", distância até a borda
    Territory.cs     (C#) a camada política: o dono de cada pixel (ushort, grade da altitude), pincel, balde, borracha, área em km²
    TerritoryNatural.cs (C#, parte do Territory) fronteiras naturais: crescer pela terra sem dono por custo (serra, rio, mar) e assentar no relevo
                     (Terrain.cs também dá os lagos do Gleba e a costa do mapa político: CoastImage, distância em km)
    RegistryTerritory.cs (C#, parte do Registry) a camada gravada no banco (comprimida) e a cor de cada país
    domain_hub.gd    liga os painéis de busca, ficha e calendários ao Registry; segue o relógio (set_time/tick)
    calendar.gd      o calendário universal: só conversões (365 dias, sem bissextos); tempo = segundos int64 desde a época
    world_clock.gd   o relógio oficial: presente, consulta, pausa, velocidade, eventos e o contrato dos módulos
    world_store.gd   salva e lê o relógio em JSON (user://evron_world.json), com .bak e troca atômica
    demo_module.gd   DEMONSTRATIVO: um evento e uma camada de teste que exercitam o contrato (sai com o 1º módulo real)
  edit/            comandos de edição: toda mudança é um comando com desfazer e refazer.
    command_stack.gd pilha de desfazer/refazer, limitada a 256 MiB; cada comando = nome + objeto com Undo/Redo/Bytes
    terrain_brush.gd pincel de terreno: modos, nomes, parâmetros e quando marcar (o que o GDScript usa)
    BrushKernel.cs   o trabalho pixel a pixel do pincel (todos os modos, erosão e rios)
    TerrainEdit.cs   uma pincelada como DADO: pixels mexidos, altura antes e depois (arrays; gravável no banco)
    TerrainNoise.cs  ruídos dos pincéis (fbm e cristas) na posição 3D da esfera
    TerritoryEdit.cs uma pincelada de território como DADO: pixels mexidos, dono antes e depois (8 bytes por pixel); vai na mesma pilha de desfazer
  view/            o globo na tela.
    globe_material.gd  o material (globe.gdshader); único lugar que escreve nos uniforms; guarda só a camada da tela
    globe_camera.gd    gira em volta do globo e dá zoom logarítmico, da órbita a ~17 km do chão; a luz vai junto
    globe_view.gd      SubViewport com a esfera e a câmera; converte a tela em ponto da superfície (hover e clique)
    tile_layer.gd      camada em blocos: escolhe os blocos da pirâmide pelo zoom, carrega em threads, cache limitado
    place_layer.gd     as presenças dos cadastros sobre o globo: discos translúcidos com aro, rótulos de tamanho fixo, uma cor por camada
  ui/              painéis: mostram valores e avisam por sinais.
    map_layers.gd    o catálogo das camadas: arquivo, grupo, legenda e o texto com a confiança da calibração
    layer_panel.gd   escolha da camada e leitura do cursor (lat/lon, altitude, terra/mar)
    tool_panel.gd    barra de ferramentas: navegar ou pincel, raio, intensidade, desfazer e refazer
    search_panel.gd  busca nos cadastros (nome, filtro de tipo) e o menu "Novo" (seis tipos e a sociedade)
    sheet_panel.gd   a ficha: identidade, resumo, etiquetas, nomes, conteúdo gerado dos campos, relações, calendários, duplicar e excluir
    calendar_panel.gd janela dos calendários locais: os cadastrados e o formulário de um novo (com a primeira era)
    presence_panel.gd camadas e escopo do mapa de presenças (a ficha aberta ou todas as entidades)
    territory_panel.gd a barra do modo pintar território (pincel, balde, borracha, raio, "só em terra", área, Terminar)
    draw_panel.gd    a barra do modo desenhar fronteira (pontos marcados, Desfazer, Concluir, Cancelar; Esc, Enter e Backspace)
    time_bar.gd      barra de tempo (embaixo à esquerda) e janela do calendário: data, pausa, velocidade, avanços, consulta
    legend_panel.gd, ui_kit.gd
scenes/main.tscn   Main e o Hud (os painéis); a vista 3D é criada em código pelo GlobeView
shaders/globe.gdshader  camada de imagem ou altitude calibrada, com o relevo na iluminação
shaders/globe_tile.gdshader  um bloco da pirâmide; "natural" repinta a água e o grão fino como o globo
shaders/brush.gdshaderinc    círculo de prévia do pincel; lê o parâmetro global "brush" (project.godot, shader_globals)
shaders/experimental.gdshaderinc  o satélite experimental (tools/build_experimental.py, rios de tools/build_indexed_rivers.py)
shaders/natural.gdshaderinc  água do mar pela profundidade e grão fino sintetizado, comuns ao globo e aos blocos
tools/build_tiles.py    imagem equiretangular grande -> pirâmide de blocos de 512 px (data/evron/tiles/<nome>/)
tools/import_maps.py    mapas.zip -> data/evron/ (PNGs + altitude em metros); roda uma vez
tools/build_natural.py  cor natural em 8K (natural.png) a partir de vegetação, biomas, clima, solos, rochas, vulcanismo,
                        bacias endorreicas, lagos e rios; limites interiores com ruído na esfera (semente fixa), costa com
                        um warp próprio mais fino (baías e pontas, sem deslocar a geografia em larga escala).
                        O mar não é pintado ali: o shader o pinta pela profundidade ao vivo, com brilho do sol e
                        detalhe procedural abaixo de 6 km que aparece só de perto
tools/build_natural_tiles.py  a mesma cor natural, em 16K e com mais uma oitava de grão fino, na pirâmide de blocos
                        (tools/build_tiles.py): perto da câmera substitui o grão sintetizado na tela por mais grão de
                        verdade; os dados do Gleba não têm mais detalhe que 9,77 km, então isso não é dado novo
tools/build_rivers.py   rios com largura em metros: rede pelas linhas de fluxo do Gleba (que têm a largura de um vale,
                        9,77 km), linha central suavizada e o vetor até ela em cada texel de 8K; o shader desenha o rio
tests/             shot.gd (executor) + suites/ (uma por assunto); core_suite roda sem os mapas (CI)
Evron.csproj       o projeto C# (Godot.NET.Sdk); .github/workflows/ci.yml compila e roda a core_suite
docs/calibracao/   calibração dos mapas do Gleba (JSON, PDF e os scripts que a reproduzem)
```

## Dados

- **Fonte:** `mapas.zip` (Gleba 0.3.5). Não é alterado nem versionado. `python tools/import_maps.py <zip>` copia os
  PNGs para `data/evron/` (fora do git, com `.gdignore`: o Godot não os importa nem comprime) e converte
  `Elevation GrayScale.png` em metros com a calibração (mar no pixel 32767, de −13.500 a +9.103,4 m).
- **Altitude em float32:** em float16 o passo passaria de 4 m acima de 4 km, o que a edição de terreno não pode perder.
- **Convenção de coordenadas** (código e shader): `dir = (cos lat · sin lon, sin lat, cos lat · cos lon)`;
  mapa equiretangular com `u = lon/360 + 0,5` e `v = 0,5 − lat/180`. Longitude leste positiva.
- **Precisão:** `Vector3` do Godot é float32. Distâncias usam `atan2(|a×b|, a·b)`, não `acos`, que erra quilômetros
  em distâncias curtas. O núcleo C# faz as contas em `double` como o GDScript (que só tem `float` de 64 bits): com
  isso o porte deu o MESMO terreno, bit a bit, em 10 pinceladas de todos os modos.

## GDScript e C#

- O C# não expõe enums nem constantes ao GDScript; métodos e propriedades sim, com o nome do C# (`terrain.GetH(i)`,
  `terrain.Size`). Por isso o enum `Op` e os nomes dos modos ficam em `terrain_brush.gd`, na mesma ordem de
  `BrushKernel.Op`.
- O GDScript não infere o tipo de propriedade do C#: `var w: int = terrain.Size.x`, não `:=`.
- A altitude mora no C# (32 MiB): atravessar a fronteira a cada marca custaria uma cópia inteira.
- Precisa do Godot **.NET** (pasta GodotSharp ao lado do executável) e do .NET SDK 8; `dotnet build` antes de rodar.

## Fluxo

```
usuário --(menu)--> LayerPanel --layer_selected--> Main.set_layer --> GlobeMaterial.show_layer, LegendPanel
mouse --> Main._unhandled_input --> GlobeView.handle_input --> câmera; surface_hovered/clicked --> Main --> LayerPanel
```

- **Sinais para cima, chamadas para baixo.** Um módulo chama métodos de quem ele possui e avisa por sinal quem o possui.

## Como acrescentar algo

- **Nova camada:** uma entrada em `ui/map_layers.gd` (arquivo, grupo, legenda). `nearest: true` para categorias.
- **Novo painel:** um `PanelContainer` em `ui/` que só recebe valores e emite sinais; `Main` liga os dois lados.
- **Nova constante:** no módulo que a usa, com o comentário do porquê do valor.

## Cadastros dos domínios (etapas 0 e 1 do plano `Plano_Dominios_e_Calendarios_Evron.pdf`)

- **SQLite pelo C#** (`Microsoft.Data.Sqlite` no `Evron.csproj`). O banco é um arquivo; o esquema vem de migrações em ordem
  (`Registry.Migrations`), cada uma numa transação, com a versão em `PRAGMA user_version`. Mudar o esquema = acrescentar uma migração,
  nunca editar uma antiga. Chaves estrangeiras ligadas. **Um banco de versão maior que a conhecida é recusado**: `Open` fecha a conexão, `IsOpen()` é falso e o
  `DomainHub` fica inativo (escrever num esquema desconhecido o corromperia). A connection string usa o `SqliteConnectionStringBuilder` (caminho com `;` ou apóstrofo abre).
- **Entidade:** ID inteiro estável, mundo (único por enquanto), um dos seis tipos (`cultura`, `pais`, `raca`, `etnia`, `idioma`,
  `religiao`) e resumo opcional. Só o nome é obrigatório. A data de criação é a **real**, não a do mundo.
- **Nomes** (`entity_name`): texto, papel (principal, alternativo, histórico, autodenominação, exônimo, oficial, popular, gentílico,
  etnônimo, denominação coletiva), idioma opcional e validade `[início, fim)`. O nome principal é o de exibição; os outros papéis mantêm
  gentílico, etnônimo etc. distintos mesmo com o mesmo texto. `Correct` troca a grafia sem história; `RenameAt(t)` é mudança
  histórica (o nome antigo vale até t e continua consultável por `NameAt` e por `Find`).
- **Vínculos** (`relation`): tipo, origem, destino, validade `[início, fim)`. Dirigidos, de muitos para muitos. Os tipos são dados
  (`relation_type`, com o tipo de entidade aceito em cada ponta, ou qualquer); o vínculo é recusado se o tipo não existe, se as pontas
  não servem ou se repete o mesmo vínculo em período sobreposto. O vínculo nunca copia a entidade: reutilizar é apontar para o mesmo ID.
- **Tempo:** segundos `int64` do relógio universal; `long.MinValue`/`MaxValue` = sem limite. Datas incertas, precisão e calendários
  locais ainda não existem (etapas 3 e 6).
- Em erro de uso o C# lança exceção; chamado do GDScript ela vira `ERROR` no log e a chamada devolve vazio (os testes conferem que nada foi gravado).
  Por isso o hub, depois de gravar um campo, relê o que ficou (`GetField`) e o painel mostra isso, não o que foi digitado.

### Fichas (etapa 4)

- **Campos como dados** (`field_def`, `field_domain`, `field_value`): um campo de texto por tópico das seções 4 a 9 do plano (62), semeado
  na migração 2 com a dica do plano. O tipo da entidade escolhe quais campos a ficha mostra. **Campo personalizado** (`AddField`) é o mesmo
  mecanismo: texto, número com unidade, escolha ou sim/não, aplicado a um ou mais tipos. Uma seção nova da ficha = linhas em `field_def`,
  não um painel novo.
- **Estados de vazio:** sem linha = não preenchido; `unknown` = desconhecido; `na` = não se aplica; `known` com número 0 = zero. Texto em branco
  volta a "não preenchido". Nada é convertido em silêncio (a vírgula decimal é aceita; texto que não é número é recusado).
- **A ficha** é um `Dictionary` único (`Registry.Sheet(id, t)`): nomes, etiquetas, campos com estado e valor, e vínculos nos dois sentidos com o
  rótulo certo de cada lado (`out_label` / `in_label` em `relation_type`). Campos vazios ficam recolhidos em "Adicionar informação".
- **Busca** (`Search`): nome de qualquer papel e época, sem diferenciar maiúsculas nem acentos (feita em C#, até 200 resultados), com filtros de
  tipo, etiqueta e vínculo; o resultado mostra o nome principal na data consultada e, se casou por outro, esse nome.
- **Duplicar** cria identidade nova (resumo, valores e etiquetas copiados; nomes alternativos não; vínculos só se pedido e só os em aberto).
  **Excluir** é correção de erro de criação: avisa quantos vínculos vão junto e apaga tudo da entidade. **Sociedade** (`CreateSociety`) cria país,
  cultura e/ou etnia ligados, que é o começo da ficha antiga; raça, idioma e religião não são criados.
- **Fluxo:** painel emite sinal → `DomainHub` chama o Registry → o hub devolve ao painel. Os sinais de edição (`name_changed`, `summary_changed`, `field_edited`) levam o **id da entidade da ficha em que
  se digitou**: se a ficha trocar enquanto o campo tem o foco (clique numa presença no globo), o texto vai para a entidade certa, não para a que acabou de abrir. Só mudanças estruturais (nome alternativo, etiqueta,
  vínculo, abrir outra ficha) refazem a ficha; editar campo não, para não tirar o foco de quem digita.
- **Ainda não feito:** desfazer/refazer dos cadastros (a pilha de comandos está na `main`; falta escrever os comandos dos cadastros); mudança de nome **com data** na interface (`RenameAt` existe no núcleo; falta o seletor de data); a "visão composta" completa da ficha antiga (hoje: criar a sociedade e navegar pelas relações, sem abas lado a lado); escolher registros existentes ao criar a sociedade; fontes e `property_version` para o restante dos campos; importação. Duas migrações paralelas em ramos diferentes precisam ser renumeradas ao integrar.

### Calendários locais (etapa 3)

- **O que é um calendário local aqui:** conserva os 12 meses e os 365 dias do universal (o `calendar.gd` da ramificação `calendario` continua sendo
  a única regra de dias e meses) e varia a **numeração dos anos** (eras), a **virada do dia** (`day_offset`: o mês e o ano viram junto), os **nomes
  dos meses** e o formato. Outra duração de ano ou outra sequência de meses é a etapa 7 do plano.
- **Cadastros** (migração 3): `calendar` (definição, confiabilidade `exata | aproximada | indisponivel`, fonte), `era` (marco em segundos
  universais, direção `up | down`, número do ano do marco), `calendar_era` (a era que o calendário usa em cada período, com prioridade) e `calendar_use`
  (entidade + calendário + finalidade civil/ritual/tradicional/administrativo/outro + validade `[início, fim)` + prioridade de exibição).
  Era e calendário são cadastros separados: vários calendários podem usar a mesma era. Um calendário serve a várias entidades e uma entidade usa
  vários; só se recusa repetir entidade + calendário + finalidade em períodos sobrepostos. Trocar o calendário civil numa data = `EndCalendarUse(t)`
  + novo uso começando em t (consulta antes e depois dá o vínculo certo, fim excluído).
- **Conversão** (`local_calendar.gd`, só funções sobre o `Dictionary` de `Registry.CalendarDef`): `to_local(def, t)`, `to_universal(def, era, ano, mês, dia…)`
  e `span(def, era, ano[, mês])`. O ano de uma era conta a partir do ano universal em que cai o marco (um marco no meio do ano faz do ano parcial o
  número `first`); "antes de" é uma era `down` com `first = 0`, válida até o marco; duas eras no mesmo instante: vale a de maior prioridade na ida e a volta
  é sempre exata. **Exato ou nada:** sem era válida, calendário indisponível, data inexistente ou fora da validade da era devolvem um status com o motivo
  e nunca um instante; data só com ano ou mês vira um intervalo (`span`), não um instante. Testado: ida e volta exata em milhares de instantes (inclusive antes
  da época), virada de dia, mês, ano e era.
- **Interface:** a ficha ganhou "Calendários" (data universal e, abaixo, a data local de cada calendário que a entidade usa, por prioridade; "Usar" liga outro).
  O botão "Calendários…" do painel de busca abre a janela para criar um calendário com a primeira era (nome, marco, numeração, direção, hora da virada e nomes
  dos meses). O formulário cria calendários com a era valendo **para sempre**: datas muito antes do marco mostram anos negativos; períodos de era e várias eras
  existem no núcleo e ainda não têm tela.
- **O hub segue o relógio:** `Main._on_clock_changed` chama `DomainHub.set_time(clock.shown())` (presente ou consulta). As datas escritas na ficha atualizam na hora;
  a ficha em si (nomes, vínculos e usos válidos na data) só é refeita por `tick()` se o conteúdo dela mudou (compara o hash do `Registry.Sheet` na data nova com o da ficha mostrada: um relógio andando sem cruzar nenhuma validade não reconstrói nada), no máximo 2 vezes por segundo e nunca com o usuário digitando ou com um menu aberto. A busca e o mapa também só se redesenham se o resultado mudou.
- **Ainda não feito:** editar ou apagar calendário e era; períodos de era e reformas na interface; calendários aritméticos (ano ≠ 365 dias), datas ambíguas
  por reforma e viradas locais por lugar (etapas 7 e seguintes); nomes de mês por idioma (hoje um conjunto por calendário); semanas; região do uso.

### Lugares, presenças e demografia (etapa 5)

- **Lugar** (`place`): nome, tipo (assentamento, região, local sagrado, natural, outro), `lat`/`lon` e `radius_km`: **0 = ponto; > 0 = área aproximada em disco**; e, desde as
  fronteiras, pode ser um **contorno** desenhado à mão (ver "Fronteiras desenhadas à mão"). É compartilhável: o mesmo lugar em duas fichas é o mesmo registro (a capital do país
  e a sede da religião). Distâncias pela esfera (`atan2`), então o disco atravessa a longitude 180° e cobre o polo.
- **Presença** (`presence`): entidade + lugar + função (capital, sede, origem, presença, centro cultural, lugar sagrado, território, reivindicação, outro) +
  validade `[início, fim)` + certeza. A **camada do mapa vem do tipo da entidade**: país = fronteira política, cultura = presença cultural, etnia = distribuição
  étnica, idioma = área linguística, religião = presença religiosa, raça = habitat. Nenhuma camada implica a outra; o território político de um país não vira a
  presença da cultura dele. Mudar a capital = `EndPresence(t)` + nova presença em t.
- **Estimativa** (`population_estimate`): o que se conta para o tipo da entidade (**habitantes** para país, **integrantes** para etnia/cultura/raça, **falantes**
  para idioma, **adeptos** para religião), num lugar e numa data: faixa `low..high` (iguais = exato) **ou** só um nível (baixa/média/alta), nunca os dois, e
  **nível nunca vira número**. Consulta em t devolve, em cada lugar, a estimativa mais recente com data até t: não projeta para trás nem para a frente.
  O idioma oficial segue sendo um vínculo (`idioma_oficial`); os falantes são outra informação, em outra base.
- **Distribuição** (`distribution` + `distribution_share`): a composição percentual da população da entidade-sujeito num lugar e data, por raça/etnia/cultura/religião/idioma,
  declarando `exclusive` (cada pessoa em uma só categoria) e `complete` (a lista traz todas). Regras: exclusiva + completa soma 100%; exclusiva não passa de 100% e,
  se incompleta, o resto é "desconhecido"; **não exclusiva não tem teto** (falantes de vários idiomas contam em cada um). O denominador (opcional) é a estimativa da
  mesma entidade, no mesmo lugar e data; com faixa numérica gera a faixa absoluta por categoria; sem ele (ou só com nível) fica só o percentual. É criada inteira e de uma vez:
  para mudar, exclui-se e recria-se. Excluir uma categoria a tira das distribuições e tira o "completa" delas.
- **Somas** (`SumEstimates`): recusa bases diferentes (habitantes, integrantes, falantes e adeptos não se somam entre si), lugares ou datas diferentes, só nível, uma
  estimativa só e a mesma entidade duas vezes. Entre entidades da mesma base só soma se as duas estiverem como categorias de uma distribuição **exclusiva** no mesmo lugar e
  data. Marginais (uma distribuição por raça e outra por religião) **não geram cruzamento**: não existe consulta que cruze, de propósito; cruzar exige um registro próprio (futuro).
- **No globo** (`view/place_layer.gd`, dentro da SubViewport, em `direção × raio × 1,0015`): cada área é um disco translúcido com aro e cada lugar um rótulo de tamanho fixo
  (★ capital, ◆ sede ou lugar sagrado, ● demais) com a função e as entidades; várias entidades no mesmo lugar dividem o rótulo e têm aros um pouco mais para dentro.
  Os menus de lugar da ficha mostram até 50 (os da própria ficha primeiro) e têm busca por nome, então qualquer lugar é alcançável; os nomes das presenças vêm no mesmo `SELECT`.
  O painel "Presenças no mapa" (esquerda, acima da barra de tempo) escolhe a ficha aberta ou todas as entidades e as camadas; a data é a do relógio.
- **O que se vê se seleciona:** `Main.select` fixa o ponto para os cadastros e chama `DomainHub.pick(dir, tolerância)`, que consulta as presenças visíveis (mesmas camadas e escopo)
  dentro do raio do lugar ou da tolerância (cresce com a altura da câmera, ao menos 40 km). Uma entidade achada abre a ficha (se já é a aberta, a ficha não é refeita: o que se digita nela fica);
  várias aparecem na lista de busca. **Nenhuma camada marcada = nenhuma presença** (a lista de camadas vazia no `MapItems`/`EntitiesAt` não significa "todas").
- **Na ficha:** "Presença no mapa" (lista com "Ver", que centraliza o globo; vincular lugar existente com função; **criar lugar no ponto fixado** com nome, raio e função),
  "População" (os números seguem o formato da ficha: `1.200` é 1200, `1,5` é 1,5, `2.000,5` é 2000,5; estimativas por lugar, na data mostrada: faixa, só nível, certeza; as composições lidas, com a faixa absoluta, o "desconhecido" e o aviso de lista incompleta).
- **Ainda não feito:** criar distribuições pela interface (hoje só pelo núcleo e testes); editar lugar (nome, raio, posição) e mover um marcador; polígonos de fronteira, território
  administrado × reivindicado em desenho próprio e "percentuais por região" como camada; nomes alternativos e históricos de lugar; critérios numéricos configuráveis para os níveis
  baixa/média/alta; fonte da estimativa na interface; recálculo de estimativas por data (hoje cada uma é um registro).

### Fronteiras desenhadas à mão

- **O que é:** um lugar com **contorno**: polígono de vértices `lat/lon` (`place_vertex`, migração 5) unidos por **arcos de círculo máximo**. `place.lat/lon` guarda o centro (onde fica o rótulo) e
  `radius_km = 0`; quem tem vértices é contorno, aconteça o que acontecer com o raio. O contorno é um lugar como os outros: pode ser compartilhado e é ligado às entidades por presenças
  (território, reivindicação etc.), então a camada, a data e o clique funcionam sem caso especial. `Registry.AddPolygonPlace` cria, `SetPlaceVertices` troca o contorno (um disco ou ponto vira contorno),
  `PlaceVertices` e `PlaceAreaKm2` leem; `MapItems`/`PresencesOf` trazem `vertices` e `area_km2` (também o disco).
- **Validação** (`PlaceGeometry.Validate`, tudo ou nada): 3 a 2000 pontos, em pares lat/lon válidos; o último ponto pode repetir o primeiro; recusa pontos seguidos no mesmo lugar, **lados que
  se cruzam ou se tocam** (testado no plano gnomônico em torno do centro, onde círculos máximos são retas), contorno **sem área** e **grande demais** (precisa caber a menos de 85° do centro:
  o contorno é sempre a região menor; para algo maior, divide-se em regiões).
- **Geometria na esfera, em vetores unitários e double** (a convenção de `EvronGeo`): nada de grade, então o contorno atravessa a longitude 180° e cobre o polo sem caso especial. **Área** pela
  soma dos ângulos sólidos dos triângulos (centro, p_i, p_i+1) com sinal (Van Oosterom & Strackee), válida também para contorno côncavo: um octante dá πR²/2 exato. **Dentro:** soma do giro do
  rumo (visto do ponto) de cada vértice ao seguinte, ±2π dentro e 0 fora; só vale a menos de 85° do centro (um ponto no lado oposto do planeta também "gira" 360° e é descartado antes).
  **Distância até a borda:** menor distância aos arcos (pé da perpendicular no arco ou o vértice mais próximo).
- **Clique (`EntitiesAt`)**: o contorno acha o ponto se está dentro ou a até a tolerância da borda (`distance_km` 0 dentro; senão a distância à borda); o disco e o ponto seguem como antes. Entre contornos
  aninhados, o menor (pelo raio equivalente à área) vem primeiro.
- **No globo** (`view/place_layer.gd`): o contorno é triangulado no plano gnomônico (`Geometry2D.triangulate_polygon`, côncavo inclusive) e cada triângulo é subdividido com pontos médios sobre a esfera até
  os lados ficarem curtos, para o preenchimento acompanhar a curvatura; o aro é uma faixa ao longo dos arcos. Um contorno que não triangula (não deveria passar pela validação) ainda desenha o aro.
  O **rascunho** (`show_draft`) é uma linha amarela pelos pontos marcados (e o lado que fecharia, mais fraco) com uma marca em cada ponto.
- **Desenhar** (`DomainHub.start_border`/`draw_click`/`draw_undo`/`draw_finish`/`draw_cancel`, barra `ui/draw_panel.gd`): na seção "Presença no mapa" da ficha, o nome da região, a função (padrão: Território) e
  "Desenhar no mapa" abrem o modo; o **clique no globo marca um ponto** (arrastar continua girando a câmera; `Main.select` roteia o clique ao hub enquanto `drawing`). **Desfazer ponto**, **Concluir** (3 pontos ou mais)
  e **Cancelar**; Esc, Enter e Backspace fazem o mesmo. Concluir cria o lugar e liga a entidade com a função escolhida; um contorno inválido não é gravado e o desenho continua para corrigir. No modo, abrir
  outra ficha e o clique de seleção são ignorados. **Redesenhar** (botão na linha da presença de um contorno) troca o contorno do mesmo lugar.
- **Fronteira vizinha sem fresta:** o ponto clicado a menos de 2% da altura da câmera (ao menos 8 km) de um **vértice de um contorno que está no mapa** cola nesse vértice (as bordas compartilhadas ficam exatamente
  iguais). Para ver o vizinho, ponha o painel de presenças em "Todas as entidades".
- **Ainda não feito:** mover ou apagar um vértice solto de um contorno já criado (hoje: Redesenhar); buracos e várias partes num mesmo território (ilhas); contorno maior que 85° do centro; pré-visualização do lado
  a fechar sob o mouse; importar contornos; verificar sobreposição entre territórios de países diferentes (hoje cada um é independente, e o clique lista todos que cobrem o ponto).

### Território pintado (a camada política por pixel)

Alternativa ao contorno por pontos para o **mapa político**: o país é uma mancha de cor que preenche o mapa, como em jogos de estratégia. As outras ideias (províncias e traço livre)
e o raciocínio de cada método estão em `docs/alternativas-fronteiras.md`.

- **Dado** (`Territory.cs`): um `ushort` por pixel na grade da altitude, o id do cadastro do **país** dono (1 a 65535; 0 = ninguém), no formato RG8 que a GPU lê. Um dono por pixel: **sem fresta e sem sobreposição**, a
  borda nasce onde duas cores se encontram, e ilhas, buracos e países enormes saem naturais. A camada é gravada em `territory` (migração 6), numa linha só, **comprimida** (deflate; um mapa quase vazio cabe em centenas de KB),
  ~1,5 s depois da última edição e ao fechar. A **cor** de cada país é a coluna `entity.color` (RGB), automática (passo de matiz áureo pelo id: vizinhos tendem a ser bem diferentes) enquanto o autor não escolhe.
- **Pincelar** (`Territory.Dab/End/Fill/ClearOwner`): o disco do pincel é o do terreno (`Terrain.DiskInto`: pela superfície, atravessa 180° e cobre o polo). Pincel dá o território ao país da barra e **toma** o de outro país
  (conquista); **borracha** só apaga o território do país da barra (nunca o do vizinho); **balde** preenche a região conectada de mesmo dono (e mesma terra/água) clicada; **"só em terra"** pinta só onde a altitude é ≥ 0, então a costa
  do país segue a costa do mapa. Cada pincelada, balde ou "apagar tudo" é **um comando** (`TerritoryEdit`, 8 bytes por pixel) na mesma pilha de desfazer do terreno (Ctrl+Z / Ctrl+Y). A área em km² pesa cada linha pela largura real
  dos pixels (perto do polo eles são estreitos) e é guardada até a próxima edição.
- **Interface:** na ficha de um **país**, a seção "Território" mostra a área, o seletor de cor (a prévia vai para a paleta enquanto o seletor está aberto; ao fechar, grava), **Pintar território** e **Apagar território**.
  "Pintar território" abre a barra (canto inferior direito): Pincel, Balde, Borracha, raio, "Só em terra", área e Terminar (Esc). Com o modo ligado, o **botão esquerdo pinta** (o direito gira a câmera) e o anel do pincel aparece sob o mouse;
  escolher uma ferramenta de terreno sai do modo. O painel "Presenças no mapa" liga e desliga a camada pela caixa "Fronteira política", e o **clique no território seleciona o país dono do pixel** (abre a ficha).
  Excluir o país apaga o território dele; um país sem cor na paleta (alfa 0) não é desenhado.
- **No shader** (`political.gdshaderinc`, usado pelo globo e pelos blocos): parâmetros globais `political_map` (RG8: dono = r + 256·g), `political_palette` (256 × 256: cor do país de id por `(id & 255, id >> 8)`) e `political_on`,
  escritos por `GlobeMaterial`. A cor do país cobre o território (55%, o relevo continua aparecendo) e uma **linha escura** marca onde dois países se encontram. A borda é **suavizada**: cada ponto olha os 4 pixels em volta e fica com
  o dono de maior peso bilinear (no lugar de degraus, diagonais), e a linha vale onde o segundo colocado é outro país e a disputa está quase empatada. Resolução da borda = a da grade (~9,8 km por pixel).
- **Fronteiras naturais** (`TerritoryNatural.cs`, etapa 1 de `docs/mapa-politico.md`): na barra, **Crescer este país** / **Crescer todos** (Dijkstra na grade, distância real na esfera; o atrito por km sobe com
  declividade, altitude, rio grande do Gleba ou do pincel Vales e mar; só ocupa terra sem dono, a partir do território e da capital) e **Assentar fronteiras no relevo** (watershed numa faixa de 60 km: a divisa vai
  para a crista ou o rio). Tudo é comando com desfazer. Nos mapas reais, 13 capitais crescem em ~1 s (`paint_suite` com a cena).
- **Mapa político** (camada "Mapa político", `globe.gdshader` modo 4; etapa 2 de `docs/mapa-politico.md`): a cor de cada país em tom de mapa sob um
  sombreado com luz fixa do noroeste (não o sol: a cor vai na emissão), o mar pela profundidade ao vivo, halo e anéis junto à costa e a linha de costa,
  da textura `coast_map` (`Terrain.CoastImage`, RGH: km até a costa e lago), recalculada fora da pincelada e só com a camada na tela. Em todas as
  camadas a fronteira vota com B-spline cúbica 4×4 (`political_owner`): curva, com largura constante em pixels de tela.
- **GPU:** a camada inteira (16 MiB) volta à GPU, no máximo 10 vezes por segundo durante a pincelada e uma vez ao soltar (como a altitude).
- **Ainda não feito (de propósito, para testar o método primeiro):** nome grande do país no centro, barra de população e ícones de cidades sobre o território; linha de costa; "território compartilhado" entre países;
  recalcular as camadas do Gleba que ficam desatualizadas; subir a resolução da camada (8K); a seleção por clique escolhe só o país (não a província); o desfazer não atravessa a exclusão de um país.

## Testes

```
dotnet build
godot --headless --path . -s tests/run_suite.gd -- tests/suites/core_suite.gd   (sem os mapas: o que o CI roda)
godot --path . -s tests/shot.gd -- <pasta_das_capturas>                         (tudo, com janela e capturas)
```

- As suítes com cena dividem uma instância do programa, nesta ordem (`shot.gd`): cada uma parte do estado da anterior.
- Os pincéis das suítes com cena andam por eventos de mouse simulados; com o mouse de verdade sobre a janela, eventos
  reais entram junto e as capturas mudam. Para comparar resultados, use as suítes sem cena.

## Blocos (pirâmide de níveis)

- Nível z: 2^(z+1) × 2^z blocos de 512 px; o relevo de 16K tem os níveis 0 a 4 (682 blocos, 19 MB em JPEG).
- A cada quadro, uma árvore de quatro filhos a partir dos 2 blocos do nível 0 escolhe, por região visível, o nível
  em que 1 texel ≈ 1 pixel da tela. Blocos atrás do horizonte saem. Um bloco só é trocado pelos filhos quando os
  4 já chegaram: nunca abre buraco. O globo de 4K fica ~10 km abaixo, tapando frestas entre níveis.
- Carga em threads (`WorkerThreadPool`), no máximo 4 texturas criadas por quadro, cache de 160 blocos (~213 MiB de
  vídeo), o nível 0 nunca sai. Medido no autoteste: o nível 4 chega em ~150 ms; processo com 100–145 MiB de RAM (com o .NET; varia entre rodadas).
- A camada do globo tem mipmaps e é lida com `textureGrad`, usando as derivadas da coordenada deslocada meia volta
  onde o u salta (longitude 180°): de longe não cintila e não há costura. Camadas de categorias seguem sem mipmap.
- O "16K" do Gleba é o mapa de 4K ampliado 4× (sem detalhe novo). A pirâmide é a estrutura que vai receber o
  detalhe de edição, dados novos ou geração procedural.

## Edição do terreno

- Ferramentas: Navegar, Elevar, Rebaixar, Nivelar (puxa para a altura do ponto inicial), Suavizar (média 3×3) e
  **Montanhas** e **Erosão** (procedurais, ver abaixo). Controle de *Rugosidade* (quanto o ruído manda na forma).
  Com um pincel ativo, o botão esquerdo pinta e o direito gira a câmera. Ctrl+Z desfaz, Ctrl+Y ou Ctrl+Shift+Z refaz.
- O peso do pincel cai de 1 no centro a 0 na borda sem degrau; o disco é medido pela superfície da esfera, atravessa
  a longitude 180° e cobre os polos.
- **Montanhas:** soma ao terreno um ruído de cristas (ridged multifractal, 6 oitavas, cristas de ~20 a 320 km, com
  deslocamento de domínio para serpentear), calculado na posição 3D da esfera: sem emenda em 180° nem estiramento nos
  polos. A intensidade vale ×6 (1000 = picos de milhares de metros). A semente é sorteada a cada pincelada: as marcas
  de uma mesma pincelada se somam (a crista cresce), outra pincelada cria outro relevo; `seed_value` fixo repete o
  mesmo relevo (testes). O ruído medido vai de −0,67 a 0,92 (mediana 0,3) e é normalizado para essa faixa.
- **Montanhas só somam** (`max(0, crista)`): vale = sem mudança. Antes os vales eram negativos e criavam água no
  meio do continente (teste `edit_suite`: nenhum pixel baixa e nenhum vira água).
- **Elevar/Rebaixar/Nivelar** usam fBm (colinas, ~100 km) pela rugosidade; **Erosão** é térmica (conserva massa,
  ângulo de repouso 150 m entre pixels, 3 passadas por marca). Ruídos em `edit/TerrainNoise.cs`.
  Estudo completo e limites no cofre: *Pincéis Procedurais de Terreno*.
- **Vales** (erosão hidráulica): escoamento D8, captação acumulada de cima para baixo, entalhe ∝ raiz(captação − 1) ×
  desnível (espigão não entalha), sedimento que desce o rio e deposita onde achata (poço retém 60%; ~74% do material
  entalhado fica no disco, ~26% sai). Os pixels do tronco principal com captação ≥ 0,8% da região pintada, marcados ao soltar o mouse viram **rio**,
  guardado em `Terrain.R` (byte por pixel, desfaz junto com a altura) e desenhado em azul por cima de qualquer camada
  (`river_paint` em relief.gdshaderinc). A água é roteada sobre a altura suavizada (5×5) para não
  prender em platôs, e acumulada na região de toda a pincelada: o rio é contínuo ao longo do traço (teste: trecho
  conectado de 46 pixels, ~200 km). Limite: onde o relevo do Gleba é plano e em degraus, o rio ainda se interrompe.
- **Mar continua mar:** o sedimento dos Vales não levanta um pixel de mar acima de −1 m (o resto segue para o mar
  aberto). Antes, uma pincelada na costa criava ilhas (218 pixels num teste do `edit_suite`; `core_suite` também cobre).
- Custo no raio máximo (1000 km), C# contra o GDScript de antes: Elevar ~8 ms por marca (122), Erosão 68 ms (692),
  Vales 115 ms (2021) e 73 ms ao soltar o mouse (937). A primeira marca do programa paga a compilação JIT do C#.
- A altitude volta para a GPU no máximo 10 vezes por segundo durante a pincelada e uma vez ao soltar: ~2 ms para
  copiar as linhas mexidas para a imagem e ~10 ms para enviar a textura inteira (32 MiB).
- O histórico guarda 12 bytes por pixel mexido (índice, antes, depois) e para em 256 MiB: os comandos mais antigos
  saem.
- O que muda com a edição: a camada Altitude, o relevo na luz de todas as camadas, a cor do mar no satélite
  experimental e a leitura do cursor. As imagens do Gleba (clima, biomas…) **não** mudam: são derivados que ficam
  desatualizados até haver recálculo (a proposta pede para marcá-los).
- Ainda só em memória: fechar o programa perde as edições (a persistência em SQLite é o próximo passo).

## Limites conhecidos (próximas etapas da E0)

- O globo usa os mapas de 4096 px (9,77 km por pixel no equador): de perto fica borrado; os blocos existem, mas o
  dado de 16K disponível não tem mais detalhe que o de 4K.
- Ainda não há banco (SQLite), histórico nem calendário: as edições ficam só em memória.
- As camadas são lidas de `data/evron/`, que não entra no export do Godot.
- Erosão e rios rodam na grade de 4K (9,8 km por pixel): um vale de verdade não cabe num pixel, e por isso o rio
  ainda se interrompe nos platôs em degraus do Gleba. O passo seguinte é a altitude em blocos editáveis (a mesma
  pirâmide), com a erosão rodando na resolução do bloco.
- A camada Relevo (16K, em blocos) é uma imagem pronta: a edição muda a luz, não a cor. A legenda a marca como
  desatualizada depois de uma edição, como as outras camadas do Gleba.

## Calendário e relógio (etapas 1 a 3 do plano `Plano_Calendario_e_Mapas_Dinamicos_Evron.pdf`)

- **Calendário (versão 1, proposta do plano como configuração inicial):** 12 meses de duração usual, fevereiro com 28 dias
  sempre, ano = 365 dias = 31.536.000 s, dia de 24 h. O tempo oficial é um `int` de segundos desde 1º de janeiro do ano 0,
  00:00 (época técnica). O `Time` do Godot não é usado: ele é gregoriano, com bissextos. Antes da época os instantes são
  negativos e a divisão é por piso (`Calendar.floordiv`), não a do GDScript, que arredonda para zero.
- **Narrativa em aberto:** ano inicial, era e nomes de eras **não** estão definidos. O programa abre no *cenário técnico de
  teste* (1º de janeiro do ano técnico 1, 00:00), identificado como tal; o número do ano não é fato da ambientação.
- **Presente × consulta:** `WorldClock.now` é o presente e só anda por avanço ou reprodução; `enter_view(t)` só muda
  `shown()`, a data que interface e camadas mostram. Consultar pausa a reprodução, recusa todos os avanços (decisão desta
  implementação: o presente nunca muda por engano) e não vai para o salvamento. `exit_view()` volta pausado.
- **Reprodução:** a velocidade é do mundo (segundos do mundo por segundo real: 1 min/s, 1 h/s, 1 dia/s), não `Engine.time_scale`.
  A fração de segundo sobra entre quadros (nada se perde com o quadro lento); um quadro conta no máximo 1 s real.
- **Avanços:** +1 hora, +1 dia e +7 dias são durações fixas; +1 mês conserva o dia e a hora (31 jan → 28 fev → 28 mar); +1 ano
  = 365 dias; "Avançar até" só aceita datas depois do presente e processa tudo o que vence no caminho.
- **Contrato dos módulos** (`WorldClock.register`): `step_seconds()` e `on_step(t)`. Os passos são múltiplos do passo contados
  desde a época, então 30 dias de uma vez e 30 × 1 dia chamam exatamente os mesmos passos. Eventos (`schedule`) disparam uma vez;
  no mesmo instante, eventos antes de módulos, cada grupo na ordem de cadastro/registro. O calendário **não** cria mortes,
  guerras ou colheitas: só avisa a passagem do tempo a quem a equipe ativar.
- **Salvamento:** `user://evron_world.json` (esquema 1, calendário versão 1): presente, fração, velocidade, eventos e o que já
  disparou. Não vai a consulta nem a pausa (abre sempre pausado) e reabrir **não** avança o tempo. Grava em `.tmp`, guarda o
  anterior como `.bak` e troca; se o arquivo estiver estragado, lê o `.bak`. Salva a cada comando, a cada 30 s e ao fechar.
- **Semente e versões:** `WorldClock.world_seed` (fixa, 1, no cenário técnico) e `models` (nome → versão) vão para o salvamento;
  `derived_seed(nome)` é um SHA-256 de semente + nome, estável entre execuções e versões do Godot (o `hash()` do Godot não promete isso).
  Ao abrir um mundo salvo com outra versão de um modelo, a barra avisa.
- **Ainda não feito (de propósito):** tarefas em blocos com progresso e cancelamento (nenhum módulo é pesado: a mistura sazonal é
  um uniform no shader); semanas, nomes locais de meses e fusos (precisam do dia da semana da época, decisão narrativa em aberto);
  estados históricos e edições datadas (etapa 6, plano próprio). A camada e o evento de `demo_module.gd` são de teste.
- Os testes (`calendar_suite`, sem cena; `time_suite`, com a barra) usam `main.save_path = ""` para não tocar no salvamento do usuário.

## Temperatura sazonal (etapa 4 do plano)

- `tools/build_temperature.py` (chamado por `import_maps.py`) converte `Temperatura Janeiro/Julho.png` em °C (float32,
  `data/evron/temperature_{jan,jul}_4096x2048.f32`) **antes** de qualquer mistura: T = −20 + 60·t pela escala magma, a mesma
  calibração do `build_natural.py`. Resolução de 0,24 °C; resíduo da calibração de Köppen de 0,5 °C. O valor −20,0 significa
  "−20 °C ou menos" (a escala satura: 7,0% do globo em janeiro e 5,9% em julho). Nenhum pixel ficou fora da escala.
- `world/seasonal_temperature.gd`: função pura da data. Âncoras: janeiro em 15 jan 12:00 e julho em 15 jul 12:00 (181 e 184 dias);
  `T = (1 − s)·Tjan + s·Tjul`, com `s` = `july_weight(t)`. Passa exatamente pelos dois mapas nas âncoras e não salta na virada do
  ano (testado). Repete-se todo ano: é referência sazonal, não clima de um dia, nem tendência de longo prazo.
- Na tela, o shader (`mode` 3) lê os dois mapas em °C, mistura com o uniform `season_july` e só então pinta com a escala magma;
  por quadro só muda esse número. A camada "Temperatura — sazonal (estimada)" segue a data exibida (presente ou consulta).
- O ponto fixado mostra valor, condição (**estimado**), data, origem e incerteza; uma referência cortada em −20 °C vira um limite
  ("≤ −X °C"). A leitura tem `CONSULTA` e o presente preservado ao lado quando se consulta outra data.
- Fora do plano desta etapa: chuva, umidade, vento, ondas (etapa 5). Comparar com o Average Rainfall só faz sentido com o modelo de chuva.
