# Arquitetura do projeto

O jogo é dividido em quatro camadas. A regra que as separa: **a simulação não conhece a tela**. Ela avisa por sinais, e quem mostra (vista e interface) escuta. Assim dá para testar a simulação sem nenhum nó, e trocar a interface sem mexer nas regras.

```
scripts/
  main.gd          raiz de composição: cria os módulos, liga os sinais, roda o quadro. Sem regra de jogo.
  data/            dados de Marte (arquivos e geografia). Só funções estáticas.
    mars_geo.gd      lat/lon <-> direção, regiões nomeadas
    mola_reader.gd   relevo real MOLA (4 px/grau)
  sim/             a simulação. Não depende de cena, câmera nem interface.
    mars_physics.gd  fórmulas puras (temperatura, pressão, órbita, ebulição...)
    planet_state.gd  controles do jogador + ciclo da água + efeito estufa. Fonte da verdade.
    hypsometry.gd    quanta água é preciso para o mar chegar a cada altitude
    climate.gd       clima numa grade 144x72 (vento, brisa/monção térmica, massas de ar e frentes, umidade, chuva, neve, vegetação e tundra, correntes e ressurgência, estações); física em docs/pesquisa-atmosfera.md
    climate_runner.gd agenda o passo do clima em pedaços por quadro
    game_clock.gd    calendário e velocidade do tempo
    auto_terraformer.gd terraformação automática (demonstração)
    ephemeris.gd     posições reais dos planetas (elementos do JPL) e da Lua (série de Meeus), em double
    solar_bodies.gd  os corpos (tamanho, cor, textura), posições relativas e orientação (eixo e rotação) da Terra, de Marte e da Lua; Fobos e Deimos em órbita kepleriana no equador de Marte (fases ilustrativas, sem efeito nas marés)
    belt_generator.gd cinturões de asteroides (principal, troianos de Júpiter, Kuiper) como órbitas keplerianas
  view/            o que o jogo mostra de Marte.
    planet_materials.gd o material de Marte (globe.gdshader); único lugar que escreve nos uniforms
    climate_textures.gd grades do clima -> texturas
    colony_layer.gd, colony_model.gd  colônias na esfera de Marte e donos das regiões
  space/           a vista do jogo: o sistema solar em 3D, com Marte em foco
    space_view.gd    junta câmera, cena, marcadores e barra de foco; usa o relógio e o material de Marte do jogo
    space_camera.gd  câmera que gira em volta de um corpo e dá zoom da superfície até 500 UA
    space_scene.gd   corpos, órbitas (planetas e Lua) e cinturões; origem flutuante e transparência pelo zoom
    space_overlay.gd nomes e pontos dos corpos em resolução cheia, e o clique que escolhe um corpo
    space_hud.gd, space_textures.gd
  ui/              painéis: mostram valores e avisam por sinais.
    control_panel.gd, time_panel.gd, gauge_panel.gd, legend_panel.gd
    map_legends.gd   nome e legenda de cada modo de mapa (mesma ordem do shader)
    region_info.gd, ui_kit.gd
scenes/main.tscn   Main e o Hud (os painéis); a vista 3D é criada em código pelo SpaceView
shaders/           globe (Marte), space_body/orbit/belt (Terra, Lua, planetas, órbitas e cinturões)
tests/             shot.gd (executor) + suites/ (uma por assunto)
```

## Fluxo de dados

```
jogador --(slider)--> ControlPanel --control_changed--> PlanetState.set_control
PlanetState --control_changed/limits_changed/sea_level_changed--> Main --> painel, materiais, câmera
Main._process: clock.tick -> planet.step -> climate_runner.tick -> auto_terraformer.step -> space.update -> HUD
ClimateRunner --step_finished--> Main --> planet.vegetation, texturas do clima
SpaceView --surface_clicked--> Main --> seleção de região; clique em outro corpo foca nele (dentro do SpaceView)
```

- **Sinais para cima, chamadas para baixo.** Um módulo chama métodos de quem ele possui e avisa por sinal quem o possui.
- **O estado vive na simulação.** Os sliders só mostram o `PlanetState`; mexer no slider pede uma mudança, e o estado confirma por sinal. (Antes o valor vivia no slider, que arredondava para 0,01 e travava a terraformação automática a 1x.)
- **Unidade de tempo:** a simulação recebe "anos de jogo" (`GameClock.tick` converte segundos reais).

## Como acrescentar algo

- **Nova regra do planeta:** em `PlanetState` (ou `Climate`, se for espacial), com teste em `tests/suites/simulation_suite.gd`.
- **Novo painel:** um `PanelContainer` em `ui/` que só recebe valores e emite sinais; `Main` liga os dois lados.
- **Novo modo de mapa:** uma entrada em `ui/map_legends.gd` **na mesma ordem** do uniform `map_mode` do shader.
- **Nova constante de balanceamento:** no módulo que a usa, com o comentário do porquê do valor.

## A vista do espaço (a vista padrão)

- **Marte:** usa o mesmo material do jogo (mares, gelo, nuvens, modos de mapa), com a orientação real do IAU: eixo inclinado 25,2° (as estações) e rotação de 24h39. Colônias e o clique em regiões funcionam na esfera dele.

- **Escala:** 1 unidade = 1000 km. A Terra tem 6,4 unidades, uma UA tem 149.598, e a câmera vai de 3% do raio acima da superfície até 500 UA.
- **Origem flutuante:** o foco da câmera é sempre a origem da cena. Posições absolutas ficam em double (`PackedFloat64Array`, o `Vector3` do Godot é float32) e só a posição *relativa ao foco* vira `Vector3`. Sem isso a Terra, a 1 UA do Sol, tremeria ~20 km.
- **Corpos distantes:** além da metade do plano `far` da câmera, o corpo é aproximado e encolhido na mesma proporção (parece igual na tela), para a razão far/near ficar pequena. Acima de ~1e7 o Godot perde precisão na projeção e para de desenhar.
- **Transparência pelo zoom:** a órbita de um corpo some quando é pequena demais na tela, ou quando está longe do foco comparada ao zoom (senão seria uma linha solta cruzando a tela). Os cinturões só aparecem de 0,5 UA para fora.
- **Tempo:** a vista usa o relógio do jogo (a data é a do jogo). A Terra e Marte só giram até 0,5 dia/s (as velocidades "1 h/s" e "1 dia/s" existem para isso); acima disso ficam parados, porque girando mais rápido piscariam. Pausar mantém o modo em que estava.
- **Entrada:** o mouse não chega a nós dentro de um `SubViewport` (o contêiner do 3D ignora o mouse). O `Main` e o `SpaceView` recebem os eventos e repassam à câmera por `handle_input`.

## Dados e créditos

- Relevo de Marte: MOLA (NASA PDS Geosciences), domínio público.
- Terra (`data/space/earth_2048.jpg`): Blue Marble, NASA Earth Observatory (cópia da Wikimedia Commons). A NASA pede o crédito "NASA Earth Observatory".
- Lua (`data/space/moon_1k.jpg`): mosaico da LRO (LROC), NASA Scientific Visualization Studio (CGI Moon Kit).
- Relevo da Terra (`data/space/earth_height_5400.jpg`): GEBCO 2008 (só a altitude de terra) pelo Blue Marble Next Generation, NASA Earth Observatory. Relevo da Lua (`data/space/moon_height_8bit.jpg`): altitude LOLA (LRO) do CGI Moon Kit, NASA SVS, versão de 8 bits (de -9,1 a +10,8 km). Os dois entram no `space_body.gdshader` como inclinação do terreno na luz, com `relief` por corpo.
- Planetas: elementos keplerianos médios do JPL ("Approximate Positions of the Major Planets", E. M. Standish, tabela 1, válidos de 1800 a 2050).
- Lua: Jean Meeus, *Astronomical Algorithms*, 2ª ed., cap. 47 (série truncada, erro de poucos centésimos de grau).
- Cinturões: distribuições estatísticas reais (lacunas de Kirkwood, troianos a ±60° de Júpiter, plutinos na ressonância 3:2 com Netuno), não um catálogo de asteroides.

## Testes

`godot --path E:\ProjetoMarte -s tests/shot.gd -- <pasta_das_capturas>`

As suítes sem cena (`physics_suite`, `simulation_suite`, `space_physics_suite`) rodam primeiro. As com cena dividem uma única instância do jogo, em ordem, porque cada uma parte do estado da anterior. A primeira falha para tudo. Cada suíte herda de `tests/test_suite.gd`. Para iterar em uma só: `godot --path E:\ProjetoMarte -s tests/run_suite.gd -- tests/suites/<suite>.gd <pasta_das_capturas> [scene]`.
Os testes de entrada enviam eventos por `Input.parse_input_event`, o caminho que o jogo usa de verdade.
