---
tags: [tecnico]
---
# Estrutura do Projeto Godot

Projeto em `E:\ProjetoEvron`.

```
project.godot
Evron.csproj              o projeto C# (Godot.NET.Sdk 4.7.2, .NET 8)
scenes/main.tscn          Main e o Hud; a vista 3D é criada em código pelo GlobeView
scripts/main.gd           raiz de composição: cria os módulos, liga os sinais, roda o quadro (sem regra do mundo)
scripts/data/             evron_geo (raio, lat/lon, pixel, distância), evron_maps (lê data/evron/)
scripts/world/Terrain.cs  a altitude e os rios em memória (C#)
scripts/edit/             terrain_brush.gd (fachada) e command_stack.gd; BrushKernel, TerrainEdit, TerrainNoise em C#
scripts/view/             globe_material (único que mexe no shader), globe_camera, globe_view (esfera, clique, cursor)
scripts/ui/               map_layers (catálogo das 49 camadas), layer_panel, legend_panel, ui_kit
shaders/globe.gdshader    camada de imagem ou altitude calibrada, com relevo na iluminação
tools/import_maps.py      mapas.zip -> data/evron/ (PNGs + altitude em metros, float32)
tests/shot.gd             executor do autoteste; tests/suites/ tem uma suíte por assunto
tests/run_suite.gd        roda uma suíte só, para iterar
tests/suites/core_suite   o núcleo num terreno sintético: roda sem os mapas (é a do CI)
.github/workflows/ci.yml  CI no GitHub: compila o C# e roda a core_suite a cada push
requirements.txt          dependências Python das ferramentas
docs/                     arquitetura.md, a proposta e calibracao/ (JSON, PDF, guia do Gleba, scripts)
data/evron/               mapas importados (fora do git, com .gdignore)
```
A regra que separa as camadas: **o mundo não conhece a tela**. Ele avisa por sinais; vista e interface escutam. O detalhe está em `docs/arquitetura.md`.

## Importar os mapas
`python tools/import_maps.py D:/downloads/mapas.zip` (precisa de Pillow e numpy). O script confere os extremos da altitude e que nenhuma terra fica abaixo do mar.

## Rodar o autoteste
Antes, compilar o C#: `dotnet build` (na pasta do projeto).

`godot --path E:\ProjetoEvron -s tests/shot.gd -- <pasta_das_capturas>` (abre uma janela para as capturas). Uma suíte só: `-s tests/run_suite.gd -- tests/suites/<suite>.gd <pasta> [scene]`.

O projeto precisa do **Godot .NET** (não está no PATH): `E:\Godot-4.7.2-mono\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe` (para testes, o `_console.exe` ao lado). O Godot da Steam não tem C# e não abre mais o projeto ([[Núcleo em C#]]).

Ver [[E0 - Prova Técnica]] e [[Decisões Técnicas]].
