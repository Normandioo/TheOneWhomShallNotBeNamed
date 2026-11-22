# Riscos de queda em PCs com pouca RAM ou placa de vídeo fraca

Análise **estática** (leitura do código e dos arquivos de dados) feita na sessão da branch `costas-batimetria`, em 2026-11-22. Nada aqui foi medido
com o jogo rodando: os números são estimativas a partir do tamanho das imagens e dos arrays. Onde algo não foi verificado, está dito.

Para quem receber este documento: cada item tem **o que é**, **onde está**, **por que pode derrubar o jogo**, **como corrigir** e **como conferir**.
Os itens 1 a 3 são os que eu corrigiria primeiro.

Contexto dos mapas: grade de 4096×2048 pixels (uns 9,8 km por pixel no equador); camadas de imagem em 8192×4096 (o satélite); `data/evron/` fica ao
lado do executável (não vai no `.pck`).

---

## 1. Pico de RAM ao abrir o satélite em 8K  — risco alto

- **Onde:** `scripts/view/globe_material.gd`, `set_layer` (decodifica `EvronMaps.load_layer(file)`, redimensiona, `generate_mipmaps()` e cria a
  `ImageTexture`); `_load_rivers()` (só no satélite antigo).
- **O que acontece:** `natural.png` e `natural_satellite.png` têm 8192×4096 RGBA8 = **134 MB decodificados** cada. O fluxo é: decodificar (134 MB),
  redimensionar para 4096 quando existe a pirâmide de blocos (+33 MB), gerar mipmaps (+33%) e copiar para a GPU. O satélite antigo ainda carrega
  `rivers_8192x4096.rgh` (134 MB) e `rivers_width.png` (34 MB). O pico na troca de camada passa de **300 MB** só na camada.
- **Por que derruba:** em máquina com 4 GB de RAM (ainda mais com GPU integrada que divide a memória) o sistema mata o processo (OOM) ou o Godot
  falha ao criar a textura.
- **Correção possível:** (a) carregar só a pirâmide de blocos quando ela existe, sem decodificar o PNG 8K inteiro; (b) soltar a `Image` logo depois de
  criar a textura (já se solta, mas conferir que nada guarda referência); (c) não manter `layer_nearest` e `layer_linear` com cópias separadas
  (conferir se são a mesma textura); (d) avisar/recusar com mensagem em vez de falhar quando `OS.get_memory_info()` indicar pouca RAM livre.
- **Como conferir:** `OS.get_static_memory_usage()` e o Monitor de memória do Godot antes e depois de `main.set_layer(...)` para cada camada de 8K.

## 2. Costa recalculada em todas as camadas  — risco alto (mudança desta branch)

- **Onde:** `scripts/world/Terrain.cs`, `CoastImage()` (linha ~167); chamada em `scripts/main.gd` (`_process`, `_coast_stale`).
- **O que mudou:** antes a costa só era calculada com o mapa político na tela. Agora **todas** as camadas usam a mesma costa (global `coast_map`),
  então ela é calculada no primeiro quadro e **depois de cada edição de relevo**, em qualquer camada.
- **O que aloca:** `bool[n]` (8 MB), vários `float[n]` de 33 MB (`d` duas vezes, `raw`, `tmp`), `ushort[2n]` (33 MB) e `byte[4n]` (33 MB):
  uns **200 MB temporários** por cálculo. São arrays grandes (LOH do .NET), então o coletor demora a devolver a memória.
- **Por que derruba:** em RAM baixa, a alocação pode falhar com `OutOfMemoryException`. Ela acontece dentro de `Parallel.Invoke`/`Parallel.For` e **não
  é tratada**, então a exceção sobe e derruba o jogo. Mesmo sem falhar, há uma pausa a cada pincelada de relevo.
- **Correção possível:** reaproveitar os buffers em campos da classe (alocar uma vez), `try/catch` em volta do cálculo (se falhar, manter a costa
  anterior e avisar), e recalcular só quando a altitude mudou de fato perto da costa (as edições já marcam os blocos editados: `EditedTiles`).
- **Como conferir:** medir o tempo e a memória de `CoastImage()` (a suíte `paint` já cronometra, limite de 2 s) e rodar duas vezes seguidas vendo se a
  memória volta ao nível anterior.

## 3. Histórico de desfazer com teto fixo de 256 MB  — risco alto

- **Onde:** `scripts/edit/command_stack.gd`, `LIMIT_BYTES := 256 * 1024 * 1024`.
- **O que acontece:** cada edição de relevo ou de território guarda os pixels antes e depois (8 bytes por pixel; fronteiras guardam também os pontos
  e as listas de pixels). O teto é fixo, qualquer que seja a RAM da máquina.
- **Por que derruba:** numa máquina de 4 GB, 256 MB só de histórico, somados aos outros itens, empurram o processo para o limite.
- **Correção possível:** teto proporcional à RAM: por exemplo `clamp(OS.get_memory_info()["physical"] * 0.04, 48 MB, 256 MB)`, lido uma vez ao
  iniciar. Os comandos mais antigos já saem sozinhos quando passa do teto.
- **Como conferir:** suíte `paint`/`brush` (usam a pilha) e um teste novo que fixa o teto baixo e confere que `undo` ainda funciona para o último comando.

## 4. Shader do mapa político muito pesado por pixel  — risco médio

- **Onde:** `shaders/globe.gdshader`, `political_style` e as funções que ela chama (`political_edge`, `political_sea_tint`) e
  `shaders/political.gdshaderinc`, `political_owner`.
- **Custo por pixel (estimado):** `political_owner` lê 16 vizinhos, mais 5 alturas (a abstenção costeira) e a lista de candidatos; `political_edge`
  faz 4 células × 2 anéis × 8 direções = **64 leituras** de dono e 64 de `political_top`; `political_sea_tint` faz 5 leituras; ainda há a costa (+4
  para o gradiente) e o ruído. Dá perto de **100 leituras de textura por pixel** em qualquer ponto de terra.
- **Por que derruba:** em GPU integrada o quadro leva muito tempo; no Windows o driver pode abortar (TDR, ~2 s por quadro) e o jogo fecha ou trava.
- **Correção possível:** (a) `political_edge` só quando o pixel de tela é grande o bastante para ver (de longe a borda interna é imperceptível:
  cortar o cálculo conforme `fwidth`); (b) reduzir para 4 direções × 1 anel num modo "leve"; (c) só fazer `political_sea_tint` para água a menos de
  `dist_km` pequeno (já há `dist < 150`, pode baixar); (d) opção de qualidade nas configurações.
- **Como conferir:** capturar com o Monitor de desempenho do Godot (ms por quadro) no mapa político em tela cheia, GPU integrada se possível.

## 5. Limites de textura e de laço nos shaders  — risco médio

- **Texturas amostradas:** `globe.gdshader` usa **16** (7 do material: `layer_linear`, `layer_nearest`, `river_offset`, `river_width`, `temp_jan`,
  `temp_jul`, `temp_ramp`; 2 de `relief` e 7 globais: `political_map`, `political_palette`, `political_top`, `coast_map`, `satellite_optics`,
  `satellite_river_atlas`, `satellite_water_preview`). 16 é o mínimo garantido em GPUs antigas e no renderizador Compatibility (OpenGL); somando
  as texturas que o próprio Godot usa (sombras, ambiente), o limite pode ser ultrapassado e o shader **não compila** (tela preta ou falha ao iniciar).
  GPUs modernas com Vulkan reportam limites muito maiores; este é um risco de GPU antiga/Compatibility. **Não verificado** em hardware.
- **Laço sem teto:** `satellite_river` (`shaders/experimental.gdshaderinc`) faz `for (i < span.y)` com `span.y` vindo do dado. Com "Rios em destaque"
  ligado, o laço roda em **qualquer** camada, inclusive de longe, onde as células do atlas têm mais trechos. Um teto (por exemplo 32 trechos) evita o
  quadro que não termina.
- **Como conferir:** `godot --rendering-driver opengl3` (Compatibility) para ver se o `globe.gdshader` compila; contar o maior `span.y` do atlas
  (`rivers_indexed.rgbaf`) com um script.

## 6. VRAM total no satélite  — risco médio

- **Estimativa (4096×2048 de base):** altura R32F 33 MB, costa RGH 33 MB, política RG8 17 MB, rios do pincel 8 MB, camada 4K com mipmaps 45 MB (ou 8K,
  179 MB), `natural_water` 34 MB, atlas de rios 82 MB, mais os blocos de perto (`MAX_CACHE = 80`, uns **105 MB**) → **400 a 500 MB** de VRAM no satélite
  experimental. O mapa de temperatura sazonal acrescenta 2 × 33 MB.
- **Por que derruba:** placa de 512 MB a 1 GB, ou GPU integrada com pouca memória reservada, pode falhar ao criar textura ou ficar muito lenta.
- **Correção possível:** cache de blocos menor em máquinas fracas (`MAX_CACHE` conforme a VRAM, `RenderingServer.get_video_adapter_*` não dá a VRAM; usar a
  RAM como aproximação); não manter `natural_water` e o atlas quando o satélite experimental não está na tela (o atlas já é solto ao sair).
- **Como conferir:** `RenderingServer.get_rendering_info(RENDERING_INFO_TEXTURE_MEM_USED)` em cada camada.

## 7. Camadas de território e atualizações para a GPU  — risco baixo/médio

- **Onde:** `scripts/app/territory_editor.gd` (uma `Territory` por nível: país, província, município e os independentes), `scripts/main.gd`
  (`refresh_political`, até 10 vezes por segundo durante a pincelada).
- **O que acontece:** cada camada é `ushort[8,4 M]` = **17 MB**; com 3 níveis de hierarquia mais os independentes (religião, etnia...) são 100 a 140 MB.
  A cada atualização a imagem composta de 16,8 MB sobe inteira para a GPU, até 10 vezes por segundo.
- **Não verificado:** se `political_image()` aloca uma imagem nova a cada chamada (seria lixo de 16 MB × 10/s para o coletor) ou reaproveita a mesma.
- **Correção possível:** reaproveitar a `Image` e atualizar só a faixa de linhas alterada (`update` parcial); criar as camadas independentes só
  quando usadas.

## 8. Renderizador e plano B  — risco baixo/médio, não verificado

- `project.godot` não define o renderizador, então vale o padrão do Godot (Forward+, que exige Vulkan). Em PCs sem Vulkan adequado o jogo pode nem
  abrir. Verificar: o Godot 4.7 cai sozinho para outro renderizador? Se não, oferecer o Compatibility (OpenGL) como alternativa documentada e testar o
  jogo nele (ver item 5).
- Também **não há opção de qualidade** (nem sombra de borda, nem água tingida, nem MSAA) para o usuário desligar em máquina fraca.

---

## Ordem sugerida

1. Item 2: reaproveitar buffers + `try/catch` na costa (mudança pequena, é a que mais piorou nesta branch).
2. Item 3: teto do histórico por RAM.
3. Item 5, laço de `satellite_river`: um `min(span.y, N)`.
4. Item 1: não decodificar o PNG 8K quando a pirâmide de blocos existe.
5. Item 4: custo do shader político (modo leve ou corte por zoom).
6. Itens 6 a 8: medir antes de mexer.

## Como medir (antes e depois de corrigir)

- Memória do processo: `OS.get_static_memory_usage()` e `OS.get_memory_info()`.
- GPU: `RenderingServer.get_rendering_info(...)` (memória de textura, número de chamadas) e o Monitor de desempenho do Godot.
- Testes que cobrem as áreas tocadas: `paint`, `brush`, `globe`, `tiles`, `layers_ui`, `territory_boundary`.

## O que NÃO foi feito

Nenhuma correção foi aplicada: este documento só lista os riscos. Nada foi medido em máquina fraca; todos os números são estimativas.
