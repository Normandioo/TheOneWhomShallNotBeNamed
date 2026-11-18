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
    evron_geo.gd     raio (8.282,3 km), lat/lon <-> direção <-> pixel, distância pela superfície
    EvronGeo.cs      a mesma convenção para o núcleo em C#
    evron_maps.gd    lê data/evron/: a altitude calibrada (float32) e as camadas PNG
    WorldDb.cs       (C#) SQLite do mundo: abrir, migrar por `user_version`, consultas com parâmetros, transação
  world/           o estado do mundo, sem tela.
    Terrain.cs       a altitude em memória (float[]) e os rios (byte[]); disco do pincel na esfera; vizinhos D8;
                     entrega as imagens para a GPU copiando só as linhas mexidas
    Registry.cs      (C#) os seis cadastros de domínio: entidades, nomes com papel e validade, vínculos tipados e datados
    RegistrySheet.cs (C#, parte do Registry) a ficha: campos como dados, valores, etiquetas, busca, duplicar, excluir, sociedade
    domain_hub.gd    liga os painéis de busca e de ficha ao Registry (sinal do painel -> chamada ao núcleo -> resposta ao painel)
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
  view/            o globo na tela.
    globe_material.gd  o material (globe.gdshader); único lugar que escreve nos uniforms; guarda só a camada da tela
    globe_camera.gd    gira em volta do globo e dá zoom logarítmico, da órbita a ~17 km do chão; a luz vai junto
    globe_view.gd      SubViewport com a esfera e a câmera; converte a tela em ponto da superfície (hover e clique)
    tile_layer.gd      camada em blocos: escolhe os blocos da pirâmide pelo zoom, carrega em threads, cache limitado
  ui/              painéis: mostram valores e avisam por sinais.
    map_layers.gd    o catálogo das camadas: arquivo, grupo, legenda e o texto com a confiança da calibração
    layer_panel.gd   escolha da camada e leitura do cursor (lat/lon, altitude, terra/mar)
    tool_panel.gd    barra de ferramentas: navegar ou pincel, raio, intensidade, desfazer e refazer
    search_panel.gd  busca nos cadastros (nome, filtro de tipo) e o menu "Novo" (seis tipos e a sociedade)
    sheet_panel.gd   a ficha: identidade, resumo, etiquetas, nomes, conteúdo gerado dos campos, relações, duplicar e excluir
    time_bar.gd      barra de tempo (embaixo à esquerda) e janela do calendário: data, pausa, velocidade, avanços, consulta
    legend_panel.gd, ui_kit.gd
scenes/main.tscn   Main e o Hud (os painéis); a vista 3D é criada em código pelo GlobeView
shaders/globe.gdshader  camada de imagem ou altitude calibrada, com o relevo na iluminação
shaders/globe_tile.gdshader  um bloco da pirâmide; relief.gdshaderinc tem o relevo comum aos dois
shaders/brush.gdshaderinc    círculo de prévia do pincel; lê o parâmetro global "brush" (project.godot, shader_globals)
tools/build_tiles.py    imagem equiretangular grande -> pirâmide de blocos de 512 px (data/evron/tiles/<nome>/)
tools/import_maps.py    mapas.zip -> data/evron/ (PNGs + altitude em metros); roda uma vez
tools/build_natural.py  cor natural da terra e do gelo (natural.png) a partir de vegetação, biomas, clima e declividade;
                        o mar não é pintado ali: o shader o pinta pela profundidade ao vivo
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

- O globo usa os mapas de 4096 px (12,7 km por pixel no equador): de perto fica borrado; os blocos existem, mas o
  dado de 16K disponível não tem mais detalhe que o de 4K.
- Ainda não há banco (SQLite), histórico nem calendário: as edições ficam só em memória.
- As camadas são lidas de `data/evron/`, que não entra no export do Godot.
- Erosão e rios rodam na grade de 4K (12,7 km por pixel): um vale de verdade não cabe num pixel, e por isso o rio
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
