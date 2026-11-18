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
  view/            o globo na tela.
    globe_material.gd  o material (globe.gdshader); único lugar que escreve nos uniforms; guarda só a camada da tela
    globe_camera.gd    gira em volta do globo e dá zoom logarítmico, da órbita a ~17 km do chão; a luz vai junto
    globe_view.gd      SubViewport com a esfera e a câmera; converte a tela em ponto da superfície (hover e clique)
  ui/              painéis: mostram valores e avisam por sinais.
    map_layers.gd    o catálogo das camadas: arquivo, grupo, legenda e o texto com a confiança da calibração
    layer_panel.gd   escolha da camada e leitura do cursor (lat/lon, altitude, terra/mar)
    legend_panel.gd, ui_kit.gd
scenes/main.tscn   Main e o Hud (os painéis); a vista 3D é criada em código pelo GlobeView
shaders/globe.gdshader  camada de imagem ou altitude calibrada, com o relevo na iluminação
tools/import_maps.py    mapas.zip -> data/evron/ (PNGs + altitude em metros); roda uma vez
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

## Testes

```
godot --headless --path . -s tests/run_suite.gd -- tests/suites/geo_suite.gd
godot --path . -s tests/shot.gd -- <pasta_das_capturas>      (com janela: tira capturas)
```

## Limites conhecidos (próximas etapas da E0)

- O globo usa os mapas de 4096 px (12,7 km por pixel no equador): de perto fica borrado. O relevo de 16K e os
  blocos (pirâmide de níveis) vêm a seguir.
- Ainda não há edição, desfazer, banco (SQLite), histórico nem calendário.
- As camadas são lidas de `data/evron/`, que não entra no export do Godot.
