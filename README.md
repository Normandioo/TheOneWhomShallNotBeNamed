# Evron

Gerenciador do mundo de Evron: globo 3D com mapas calibrados, editor de relevo e de território, cadastros dos domínios (SQLite),
calendários locais e relógio do mundo. Godot 4.7.2 **.NET** (GDScript na interface, C# no núcleo pesado) e ferramentas em Python.

## Para rodar

1. Instale o Godot 4.7.2 **.NET** e o .NET SDK 8.
2. Os mapas ficam fora do git (`data/evron/`): `python tools/import_maps.py <caminho>/mapas.zip` (uma vez; `pip install -r requirements.txt`).
3. `dotnet build` e abra a pasta no Godot (ou `godot --path .`).

Dentro do jogo: **F1** ajuda, **F3** monitor de desempenho (grava `perf.csv` em `user://`).

## Testes

```
dotnet build
godot --headless --path . -s tests/run_suite.gd -- tests/suites/core_suite.gd   # sem os mapas (é o que o CI roda)
godot --path . -s tests/shot.gd -- <pasta_das_capturas>                         # todas as suítes, com janela e mapas
```

## Onde está o quê

| Pasta | Conteúdo |
|---|---|
| `scripts/` | o jogo: `data/` mapas e geografia, `world/` estado do mundo (C# e GDScript), `edit/` comandos com desfazer, `app/` controladores, `view/` globo, `ui/` painéis |
| `shaders/` | globo, blocos, mapa político, satélite experimental |
| `tools/` | geração dos dados (mapas, blocos, rios, costa): Python |
| `tests/` | `suites/` uma suíte por assunto |
| `docs/` | documentação; veja [docs/README.md](docs/README.md) |
