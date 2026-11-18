# Arquitetura do projeto

Gerenciador do mundo de Evron (proposta: `docs/Proposta_Projeto_Evron_RPG.pdf`, se presente). Godot 4.7, GDScript.
Base copiada do Projeto Marte: a arquitetura, a câmera, o globo e os testes; o que era de Marte e do sistema solar saiu.

A regra que separa as camadas: **o mundo não conhece a tela**. Ele avisa por sinais, e quem mostra (vista e
interface) escuta. Assim dá para testar o mundo sem nenhum nó, e trocar a interface sem mexer nas regras.

```
scripts/
  main.gd          raiz de composição: cria os módulos, liga os sinais, roda o quadro. Sem regra do mundo.
  data/            o planeta e os mapas. Só funções estáticas.
    evron_geo.gd     raio (8.282,3 km), lat/lon <-> direção <-> pixel, distância pela superfície
    evron_maps.gd    lê data/evron/: a altitude calibrada (float32) e as camadas PNG
    WorldDb.cs       (C#) SQLite do mundo: abrir, migrar por `user_version`, consultas com parâmetros, transação
  world/           o estado do mundo, sem tela.
    Registry.cs      (C#) os seis cadastros de domínio: entidades, nomes com papel e validade, vínculos tipados e datados
    RegistrySheet.cs (C#, parte do Registry) a ficha: campos como dados, valores, etiquetas, busca, duplicar, excluir, sociedade
    domain_hub.gd    liga os painéis de busca e de ficha ao Registry (sinal do painel -> chamada ao núcleo -> resposta ao painel)
  view/            o globo na tela.
    globe_material.gd  o material (globe.gdshader); único lugar que escreve nos uniforms; guarda só a camada da tela
    globe_camera.gd    gira em volta do globo e dá zoom logarítmico, da órbita a ~17 km do chão; a luz vai junto
    globe_view.gd      SubViewport com a esfera e a câmera; converte a tela em ponto da superfície (hover e clique)
    tile_layer.gd      camada em blocos: escolhe os blocos da pirâmide pelo zoom, carrega em threads, cache limitado
  ui/              painéis: mostram valores e avisam por sinais.
    map_layers.gd    o catálogo das camadas: arquivo, grupo, legenda e o texto com a confiança da calibração
    layer_panel.gd   escolha da camada e leitura do cursor (lat/lon, altitude, terra/mar)
    search_panel.gd  busca nos cadastros (nome, filtro de tipo) e o menu "Novo" (seis tipos e a sociedade)
    sheet_panel.gd   a ficha: identidade, resumo, etiquetas, nomes, conteúdo gerado dos campos, relações, duplicar e excluir
    legend_panel.gd, ui_kit.gd
scenes/main.tscn   Main e o Hud (os painéis); a vista 3D é criada em código pelo GlobeView
shaders/globe.gdshader  camada de imagem ou altitude calibrada, com o relevo na iluminação
shaders/globe_tile.gdshader  um bloco da pirâmide; relief.gdshaderinc tem o relevo comum aos dois
tools/build_tiles.py    imagem equiretangular grande -> pirâmide de blocos de 512 px (data/evron/tiles/<nome>/)
tools/import_maps.py    mapas.zip -> data/evron/ (PNGs + altitude em metros); roda uma vez
tools/build_natural.py  cor natural da terra e do gelo (natural.png) a partir de vegetação, biomas, clima e declividade;
                        o mar não é pintado ali: o shader o pinta pela profundidade ao vivo
tests/             shot.gd (executor) + suites/ (uma por assunto)
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
  em distâncias curtas.

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
  nunca editar uma antiga. Chaves estrangeiras ligadas.
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
- **Fluxo:** painel emite sinal → `DomainHub` chama o Registry → o hub devolve ao painel. Só mudanças estruturais (nome alternativo, etiqueta,
  vínculo, abrir outra ficha) refazem a ficha; editar campo não, para não tirar o foco de quem digita.
- **Ficha em outra data:** `DomainHub.shown_t` ("o que não tem fim" por enquanto) é o instante lido; quando o relógio do mundo estiver nesta
  ramificação, ele passa a ser a data mostrada.
- **Ainda não feito:** desfazer/refazer dos cadastros (a pilha de comandos está no ramo `pfv`); mudança de nome **com data** na interface
  (`RenameAt` existe no núcleo, falta o seletor de data do calendário, etapa 3); a "visão composta" completa da ficha antiga (hoje: criar a
  sociedade e navegar pelas relações, sem abas lado a lado); escolher registros existentes ao criar a sociedade; selecionar no mapa
  (etapa 5); fontes, `property_version` para o restante dos campos, demografia e lugares estruturados, importação. Duas migrações paralelas em
  ramos diferentes precisam ser renumeradas ao integrar.

## Testes

```
godot --headless --path . -s tests/run_suite.gd -- tests/suites/geo_suite.gd
godot --path . -s tests/shot.gd -- <pasta_das_capturas>      (com janela: tira capturas)
```

## Blocos (pirâmide de níveis)

- Nível z: 2^(z+1) × 2^z blocos de 512 px; o relevo de 16K tem os níveis 0 a 4 (682 blocos, 19 MB em JPEG).
- A cada quadro, uma árvore de quatro filhos a partir dos 2 blocos do nível 0 escolhe, por região visível, o nível
  em que 1 texel ≈ 1 pixel da tela. Blocos atrás do horizonte saem. Um bloco só é trocado pelos filhos quando os
  4 já chegaram: nunca abre buraco. O globo de 4K fica ~10 km abaixo, tapando frestas entre níveis.
- Carga em threads (`WorkerThreadPool`), no máximo 4 texturas criadas por quadro, cache de 160 blocos (~213 MiB de
  vídeo), o nível 0 nunca sai. Medido no autoteste: o nível 4 chega em ~150 ms; processo com ~90 MiB de RAM.
- O "16K" do Gleba é o mapa de 4K ampliado 4× (sem detalhe novo). A pirâmide é a estrutura que vai receber o
  detalhe de edição, dados novos ou geração procedural.

## Limites conhecidos (próximas etapas da E0)

- O globo usa os mapas de 4096 px (12,7 km por pixel no equador): de perto fica borrado; os blocos existem, mas o
  dado de 16K disponível não tem mais detalhe que o de 4K.
- Ainda não há edição, desfazer, banco (SQLite), histórico nem calendário.
- As camadas são lidas de `data/evron/`, que não entra no export do Godot.
