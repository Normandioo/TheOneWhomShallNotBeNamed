---
tags: [mundo, dados]
---
# Mapas do Gleba

Fonte: `mapas.zip`, exportado do Gleba 0.3.5. O zip é a fonte e não é alterado.

| Material | Quantidade | Uso |
|---|---|---|
| PNG de base | 51 imagens de 4096 × 2048 (48 RGB e 3 em cinza de 16 bits) | Camadas físicas e ambientais |
| Relevo ampliado | `resized/relevo.png`, RGB de 16384 × 8192 | Visualização e teste de blocos (próximo passo da [[E0 - Prova Técnica]]) |
| Fontes editáveis | 2 arquivos `.xcf` | **Ignorar** (decisão do autor) |

- Os 3 mapas de cinza: `Elevation GrayScale` (o combinado, usado), `Land` e `Bathy` (só as metades esticadas, sem informação nova).
- Guia de legendas extraído dos scripts do Gleba: confirma unidades, 37 rochas e 24 biomas, mas não as faixas das rampas de cor.
- Importação no projeto: `python tools/import_maps.py <zip>` → `data/evron/` ([[Estrutura do Projeto Godot]]).

Ver [[Calibração dos Mapas]] e [[Camadas do Mapa]].
