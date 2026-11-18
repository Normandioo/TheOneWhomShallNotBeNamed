---
tags: [tecnico, decisao]
---
# Núcleo em C#

Desde 18/11/2026 o trabalho pixel a pixel da edição do terreno roda em **C#**; o resto do projeto segue em GDScript. Commit `991cd03`, na main e no `pfv` ([[Decisões Técnicas]]).

## Por que
O pincel Vales em GDScript levava **~2 s por marca** no raio de 1000 km: a tela congelava a cada movimento do mouse. O GDScript é interpretado e cada pixel passava por chamadas, Dictionaries e Variants. A reescrita total em C# foi descartada: interface, vista, câmera e testes não pesam, e trocar tudo custaria semanas sem ganho.

## O que está em C#
| Arquivo | Papel |
|---|---|
| `scripts/world/Terrain.cs` | A altitude (float32) e os rios em arrays; disco do pincel, vizinhos, imagens para a GPU |
| `scripts/edit/BrushKernel.cs` | Os 7 modos do pincel, pixel a pixel ([[Pincéis Procedurais de Terreno]]) |
| `scripts/edit/TerrainEdit.cs` | Uma pincelada como dados: índices, antes e depois (desfazer/refazer) |
| `scripts/edit/TerrainNoise.cs` | Ruído fBm e de cristas |
| `scripts/data/EvronGeo.cs` | A mesma geografia de `evron_geo.gd` (raio, lat/lon, ângulo) |

`terrain_brush.gd` ficou como fachada: modos, nomes e parâmetros que a interface usa (o C# não mostra enums ao GDScript).

## Garantias
- **Mesmo resultado bit a bit** que a versão GDScript: 10 pinceladas de todos os modos dão alturas idênticas. Isso exigiu fazer as contas em `double` onde o GDScript fazia (o `float` do GDScript é 64 bits; `Vector3` e arrays são 32).
- Única diferença de propósito: o Vales **não levanta o mar acima de −1 m** (antes criava ilhas na costa: 218 pixels, um deles de −290 m para +337 m).
- `core_suite` testa o núcleo num terreno sintético, sem os mapas; roda no CI do GitHub a cada push.

## Comparação (18/11/2026, PC de desenvolvimento, RTX 3050)
Mesmo Godot .NET, mesmas pinceladas e semente. Uma medição de cada.

**Tempo de quadro pintando** (inclui o envio para a GPU; 16,7 ms = 60 fps)

| Pincel | GDScript | C# | Ganho |
|---|---|---|---|
| Elevar 400 km | 20,5 ms | 4,6 ms | 4,5× |
| Montanhas 400 km | 24,3 ms | 5,5 ms | 4,4× |
| Erosão 400 km | 104 ms | 11,3 ms | 9× |
| Vales 400 km | 266 ms | 18,1 ms | 15× |
| Elevar 1000 km | 123 ms | 16,7 ms | 7× |
| Erosão 1000 km | 626 ms | 42 ms | 15× |
| Vales 1000 km | 1,93 s | 107 ms | 18× |
| Soltar o Vales 1000 km | 2,83 s | 244 ms | 12× |

**Outros**
| Medida | GDScript | C# |
|---|---|---|
| Desfazer 31 pinceladas | 300 ms | 11 ms |
| Abrir até o primeiro quadro | 1,6 s | 2,2 s (runtime .NET) |
| Primeira pincelada da sessão | — | +12 ms (compilação JIT) |
| Memória do processo (sem janela) | 315 MiB | 331 MiB |
| Globo parado | 0,8 ms | 0,8 ms |

Com raio até 400 km todos os modos passam de 55 fps em C#. O que ainda pesa: Vales com 1000 km (~9 fps).

## Custos da escolha
- **Exige o Godot .NET**, que a Steam não distribui: `E:\Godot-4.7.2-mono\`. O Godot da Steam não abre mais o projeto.
- Compilar antes de rodar: `dotnet build` (SDK .NET 8).
- Conversa GDScript ↔ C#: membros com o nome do C# (`GetH`, `HeightAt`, `Size`), sem enums nem constantes do C#, e o tipo de uma propriedade C# precisa ser escrito (`var w: int = terrain.Size.x`).
- Alternativa que roda no Godot da Steam: GDExtension em C++ ou Rust, ao custo de compilar uma DLL por plataforma. Não vale enquanto o .NET servir.

## Desfazer
Cada pincelada guarda só arrays (índices, antes, depois). O histórico tem limite de **256 MiB** em vez de 200 comandos; o comando mais recente nunca sai. É o formato pensado para virar acontecimento no banco ([[Modelo de Dados]], [[Tempo e Histórico]]).
