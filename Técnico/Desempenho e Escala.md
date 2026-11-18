---
tags: [tecnico]
---
# Desempenho e Escala

**Máquina de referência:** Nitro 5, i5-9300H, GTX 1650, 8 GB de RAM. Registrar sistema, armazenamento, drivers, resolução, VRAM e perfil de energia.

| Indicador | Meta inicial | Condição |
|---|---|---|
| Navegação | ≥ 30 fps | 1080p, qualidade econômica, dados carregados |
| Resposta | ≤ 150 ms de retorno visual | Seleção e início de operações comuns |
| RAM | ≤ 2,5 GiB sustentada, 3,5 GiB de pico | Soma dos processos, carga A |
| VRAM | ≤ 1,5 GiB | Medir texturas, geometrias e buffers |
| Abertura | ≤ 15 s | Carga A, com e sem cache |
| Processos longos | Interface responde, cancelamento seguro | Importação, blocos, cálculos, reconstrução |

**Carga A:** os 52 PNG, relevo de 16K em blocos, 10 mil assentamentos, 2 mil áreas, 100 mil versões.
**Carga B:** 50 mil assentamentos, 10 mil áreas, 1 milhão de versões (ensaio de expansão).

## Técnicas
- Carregar por área e zoom, limitar caches, descartar blocos sem uso.
- Simplificar geometria só na tela; editar e salvar a completa.
- Um mapa de 16384 × 8192 tem ~512 MiB em RGBA: ler, editar e gerar **em blocos**.
- Testar sessão longa: memória crescendo sem parar, travamento ou perda de edição reprovam a entrega.

## Hoje
- O globo carrega só a camada da tela (~24 MB de RAM e outro tanto de VRAM por PNG) e a altitude (32 MB).
- Relevo em blocos (autoteste, no PC de desenvolvimento): nível mais detalhado em ~150 ms; cache cheio de 160 blocos ≈ 213 MiB de vídeo; texturas no total ≈ 302 MiB; processo ≈ 90 MiB de RAM.
- Pincel de terreno (C#): com raio de 400 km todos os modos ficam entre 4,6 e 18 ms por quadro (≥ 55 fps); com 1000 km, de 17 ms (Elevar) a 107 ms (Vales). Envia à GPU só as linhas da altitude que mudaram. Comparação com o GDScript em [[Núcleo em C#]]. Se pesar na máquina de referência: dividir a altitude em blocos editáveis.
- Abertura até o primeiro quadro: ~2,2 s (0,6 s é o runtime do .NET). Processo sem janela com o terreno e 31 pinceladas no histórico: ~330 MiB.
- Medições na máquina de referência ainda não feitas ([[E0 - Prova Técnica]]).
