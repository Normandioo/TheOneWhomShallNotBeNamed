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
  world/           o estado do mundo, sem tela.
    Terrain.cs       a altitude em memória (float[]) e os rios (byte[]); disco do pincel na esfera; vizinhos D8;
                     entrega as imagens para a GPU copiando só as linhas mexidas
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
