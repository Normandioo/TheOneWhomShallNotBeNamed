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
  world/           o estado do mundo, sem tela.
    calendar.gd      o calendário universal: só conversões (365 dias, sem bissextos); tempo = segundos int64 desde a época
    world_clock.gd   o relógio oficial: presente, consulta, pausa, velocidade, eventos e o contrato dos módulos
    world_store.gd   salva e lê o relógio em JSON (user://evron_world.json), com .bak e troca atômica
    demo_module.gd   DEMONSTRATIVO: um evento e uma camada de teste que exercitam o contrato (sai com o 1º módulo real)
  view/            o globo na tela.
    globe_material.gd  o material (globe.gdshader); único lugar que escreve nos uniforms; guarda só a camada da tela
    globe_camera.gd    gira em volta do globo e dá zoom logarítmico, da órbita a ~17 km do chão; a luz vai junto
    globe_view.gd      SubViewport com a esfera e a câmera; converte a tela em ponto da superfície (hover e clique)
    tile_layer.gd      camada em blocos: escolhe os blocos da pirâmide pelo zoom, carrega em threads, cache limitado
  ui/              painéis: mostram valores e avisam por sinais.
    map_layers.gd    o catálogo das camadas: arquivo, grupo, legenda e o texto com a confiança da calibração
    layer_panel.gd   escolha da camada e leitura do cursor (lat/lon, altitude, terra/mar)
    time_bar.gd      barra de tempo (embaixo à esquerda) e janela do calendário: data, pausa, velocidade, avanços, consulta
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
