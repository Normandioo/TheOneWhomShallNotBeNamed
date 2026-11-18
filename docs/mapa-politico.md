# Mapa político com relevo: plano e protótipo

Meta: o mapa político de Evron com a cara das imagens de referência (mapa de jogo de estratégia): cor chapada por país
sob um relevo sombreado forte, mar escuro com halo claro na costa, fronteiras que seguem cristas e rios, estradas,
povoados, capitais e nomes grandes ao longo do país, e a dica com o nome formal ao passar o mouse.

## O protótipo (`tools/mapa_politico.py`)

```
python tools/mapa_politico.py            todas as vistas (golfo, oeste, sul, leste, norte)
python tools/mapa_politico.py oeste      uma vista
```

Saída em `data/evron/politico/` (fora do git, como os mapas): `<vista>.png` (1920×1440, 5.000 km de largura,
2,6 km por pixel), `<vista>.html` (a mesma imagem com a dica do mouse; abre direto do disco) e `mundo.png` (visão
geral dos 424 países). A etapa global leva ~90 s e fica em cache (`mundo.npz`; apague para refazer); cada vista, ~40 s.
Usa `tools/build_rivers.py`, trazido do ramo `satelite-rios` sem mudança.

### O que é dado e o que é inventado

| Camada | De onde vem | Precisão |
|---|---|---|
| Costa | `Landmask.png` como distância com sinal, reamostrada, suavizada e com ruído | presa a 0,8 px do dado (~8 km); um `assert` confere em cada vista; ilhas e canais de 1 px ficam |
| Relevo | `height_4096x2048.f32` (gaussiana 0,8 px tira os degraus do Gleba) | posição e forma do dado; o detalhe abaixo de ~40 km é ruído com amplitude proporcional ao relevo local: só texturiza onde já há serra |
| Mar e lagos | profundidade da mesma altitude; lagos da `Waterbodies.png` | do dado |
| Rios | rede vetorial do `build_rivers.py` (`Waterflow.png`), largura pelo fluxo | do dado |
| Gelo | `Clima.png` (EF) e `BiomasGleba.png` (geleira) | do dado |
| Países | **inventados**: capitais onde é habitável e cada pixel vai para a capital mais barata de alcançar | as fronteiras caem em cristas, rios grandes e estreitos porque atravessá-los custa caro |
| Povoados, cidades, estradas | **inventados** pela habitabilidade (temperatura, chuva, solo, declividade, água por perto); estradas pelo caminho de menor custo | — |
| Nomes | gerador de sílabas | — |

O que faz a fronteira "seguir a realidade", em duas escalas:
1. **Na grade de 4K** (9,77 km): custo por km = 1 + declividade + altitude acima de 1.500 m, vezes um ruído de 20 a
   120 km (sem ele, na planície sai um Voronoi de retas); rio grande soma um pedágio; mar raso custa 10, mar fundo 60
   (ilha perto da costa entra no país; outro continente, não). Gelo e o que nenhuma capital alcança ficam sem dono.
2. **Na tela**: o rótulo de 4K é suavizado e, numa faixa de ~1 px do dado em volta de cada fronteira, um *watershed*
   sobre o relevo detalhado + os rios desenhados escolhe a linha: ela gruda na crista ou no rio mais perto.

### Limites do protótipo

- A busca de custo usa uma janela por capital com o cos da latitude da capital (erro de ~10% a ±12° dela). Bom para o
  protótipo; no jogo, fazer na esfera (ver etapa 1).
- A fonte é a Bahnschrift do Windows. **Não pode ir no jogo** (licença da Microsoft): trocar por uma fonte livre
  (SIL OFL) condensada e pesada, como Oswald ou Barlow Condensed, empacotada no projeto.
- Rótulo em linha reta (como na referência), não em curva; país pequeno demais fica sem nome.
- A dica do HTML mostra o país inventado. No jogo, ela lê o cadastro.

## Plano para o Godot

Cada etapa entrega algo usável e tem teste. A base é o ramo `dominios-calendarios`, que já tem o dono por pixel
(`Territory.cs`, RG8 na grade de 4K), o shader político (`political.gdshaderinc`), os lugares (`RegistryPlaces.cs`)
e o pincel de território. O ramo `satelite-rios` tem os rios vetoriais (`build_rivers.py` → `rivers_8192x4096.rgh`).

### Etapa 1: fronteiras naturais como ferramenta (C#)

**Feita** (ramo `mapa-politico`): `scripts/world/TerritoryNatural.cs` (`Grow`, `Snap`, `SetRiverFlow`) e a seção "Fronteiras naturais" da barra de
território (alcance, Crescer este país, Crescer todos, Assentar fronteiras no relevo). Testes no `territory_suite` (serra, rio, barreiras, desfazer,
país pequeno) e no `paint_suite` (barra; 13 capitais reais crescem em ~1,3 s). Lagos do Gleba contam como água.

- `Territory.Grow(seeds, weights)`: Dijkstra na grade de 4K com o mesmo atrito do protótipo, passo D8 com a distância
  de verdade na esfera (`EvronGeo`, sem a janela aproximada). Botão "crescer países a partir das capitais" no painel
  de território: cada país do cadastro com capital (lugar com papel "capital") recebe o que alcança primeiro.
- `Territory.Snap(owner)`: ajusta uma fronteira pintada à mão para a crista ou o rio mais perto, numa faixa de N km
  (o *watershed* do protótipo). O pincel continua mandando: o ajuste é um comando com desfazer (`TerritoryEdit`).
- O atrito sai de `Terrain` (altitude editada ao vivo) e dos rios: editar uma serra muda a fronteira sugerida.
- Teste (`core_suite`, sem mapas): grade sintética com uma crista e um rio entre duas capitais; a fronteira tem de
  cair sobre eles (≥ 90% dos pixels de fronteira a ≤ 1 px), não atravessar mar fundo, e dar o mesmo resultado na
  mesma entrada.

### Etapa 2: o estilo no shader

**Feita em parte**: camada "Mapa político" (`globe.gdshader`, modo 4): cor do país em tom de mapa (a do cadastro, menos saturada), sombreado com
luz fixa do noroeste em duas escalas (altura suavizada 2×2, sem facetas), mar pela profundidade, halo e anéis a 10/22/38 km, linha de costa e lagos
(`Terrain.CoastImage`: distância em km, suavizada e presa a meio pixel; ~0,8 s no build Debug, recalculada só com a camada na tela). A fronteira
de todas as camadas vota com B-spline cúbica 4×4: sai em curva, sem a escada da grade. Teste da costa no `core_suite` (CI); capturas no
`paint_suite`. **Falta:** os rios do Gleba no estilo (merge do `satelite-rios`), o detalhe fractal abaixo do texel, gelo e o pontilhado de serra.

- **Cor × relevo:** no modo político, luz fixa de mapa (noroeste, 40°) em vez do sol; sombreado em duas escalas
  (macio e bem exagerado + um pouco de fino), sombra puxada para marrom. O detalhe abaixo da resolução do dado é o
  ruído 3D (`TerrainNoise` portado para o shader) vezes uma textura de "relevo local" calculada na importação.
- **Costa e lagos:** textura de distância à costa com sinal, em km (como a `.rgh` dos rios), feita na importação
  com a suavização presa do protótipo. Dela saem a linha da costa com largura constante em pixels, o halo claro e os
  anéis (10, 22 e 38 km). A cor do mar pela profundidade já é ao vivo.
- **Fronteira:** o shader atual decide o dono pelos 4 texels vizinhos; para a linha fina e na posição refinada,
  guardar uma distância até a fronteira (calculada em C# quando `Territory.Version` muda, só nas linhas mexidas) e
  desenhar a linha com largura constante em pixels em qualquer zoom.
- **Rios:** fazer o merge do `satelite-rios` e pintar a rede no tom do mapa político.
- Teste: captura do `shot.gd` numa região fixa, comparada com uma de referência (diferença média abaixo de um limite).

### Etapa 3: símbolos e rótulos

- **Rótulo do país:** em C#, por país: ponto mais interno (transformada de distância), eixo maior (PCA) numa projeção
  local, encolher até caber em 82% e não cobrir outro rótulo. Recalcula quando o território muda. Na tela, `Label3D`
  deitado na superfície ou camada 2D projetada a cada quadro; some quando o país fica pequeno na tela.
- **Capitais e cidades:** da tabela `place` (estrela na capital, quadrado na cidade, nome só nas maiores);
  povoados como pontos, num `MultiMesh` de tamanho constante em pixels, a partir de `population_estimate` ou da
  habitabilidade enquanto não houver dados.
- **Estradas:** tabela nova (`road`: tipo e polilinha em lat/lon). Geradas pelo menor custo (como o protótipo) ou
  desenhadas; vermelhas as principais, amarelas as secundárias; fita em espaço de tela.
- **Nível de detalhe pelo zoom:** de longe só cor, relevo e nomes de país; no meio, fronteiras e cidades; de perto,
  povoados, estradas secundárias e afluentes.

### Etapa 4: dica do mouse

`GlobeView.surface_hovered` → `Territory.OwnerAt(n)` → nome curto e nome formal do cadastro (`entity_name` com papel
"oficial") → painel escuro como o da referência (nome em caixa alta, nome formal embaixo).

### Ordem e riscos

1 → 2 → 3 → 4. A etapa 1 já serve sozinha (fronteiras naturais no pincel de hoje) e não depende das outras.

- Resolução: o dado tem 9,77 km por pixel. Abaixo de ~20 km tudo é ruído controlado; a legenda deve dizer isso.
- Os países do protótipo são inventados; no jogo, o gerador é uma **ajuda** para desenhar, nunca sobrescreve o que o
  usuário pintou sem um comando explícito (com desfazer).
- `tools/build_rivers.py` está igual nos dois ramos: o merge do `satelite-rios` não dá conflito enquanto ninguém o
  mudar só de um lado.
