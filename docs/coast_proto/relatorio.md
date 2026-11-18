# Protótipo de correção de costa
Recortes escolhidos por medida (maior densidade de costa / mais ilhas pequenas), raio 6.371 km, 9,77 km/px na grade de 4096x2048. Sigmas calibrados no recorte continental: d025 = 1.40, d05 = 6.97.

## continental
- **d025 (alvo 0.25 px)**: deslocamento médio 2.44 km (0.25 px), máximo 2.44 km; área terra 570608 -> 571050 px (+0.1%); componentes 13 -> 13; fusões 0, ilhas partidas 0 — OK
- **d05 (alvo 0.50 px)**: deslocamento médio 4.96 km (0.51 px), máximo 17.10 km; área terra 570608 -> 592895 px (+3.9%); componentes 13 -> 4; fusões 1, ilhas partidas 1 — REJEITAR
- **d05 com proteção de feições automática (por falha)**: deslocamento médio 5.07 km (0.52 px), máximo 15.45 km; área terra 570608 -> 568835 px (-0.3%); componentes 13 -> 13; fusões 0, ilhas partidas 3 — REJEITAR
- **d05 com proteção autoral (por tipo de feição)**: deslocamento médio 3.31 km (0.34 px), máximo 9.77 km; área terra 570608 -> 570540 px (-0.0%); componentes 13 -> 13; fusões 0, ilhas partidas 0 — OK

## arquipelago
- **d025 (alvo 0.25 px)**: deslocamento médio 2.44 km (0.25 px), máximo 2.44 km; área terra 252656 -> 252550 px (-0.0%); componentes 30 -> 30; fusões 0, ilhas partidas 0 — OK
- **d05 (alvo 0.50 px)**: deslocamento médio 4.52 km (0.46 px), máximo 14.65 km; área terra 252656 -> 249158 px (-1.4%); componentes 30 -> 16; fusões 4, ilhas partidas 1 — REJEITAR
- **d05 com proteção de feições automática (por falha)**: deslocamento médio 4.65 km (0.48 px), máximo 14.65 km; área terra 252656 -> 248925 px (-1.5%); componentes 30 -> 23; fusões 0, ilhas partidas 1 — REJEITAR
- **d05 com proteção autoral (por tipo de feição)**: deslocamento médio 3.34 km (0.34 px), máximo 9.77 km; área terra 252656 -> 252471 px (-0.1%); componentes 30 -> 30; fusões 0, ilhas partidas 0 — OK

## emenda_longitude
- **d025 (alvo 0.25 px)**: deslocamento médio 2.44 km (0.25 px), máximo 2.44 km; área terra 1152 -> 1148 px (-0.3%); componentes 1 -> 1; fusões 0, ilhas partidas 0 — OK
- **d05 (alvo 0.50 px)**: deslocamento médio 4.27 km (0.44 px), máximo 12.21 km; área terra 1152 -> 892 px (-22.6%); componentes 1 -> 1; fusões 0, ilhas partidas 0 — OK
- **d05 com proteção de feições automática (por falha)**: deslocamento médio 4.27 km (0.44 px), máximo 12.21 km; área terra 1152 -> 892 px (-22.6%); componentes 1 -> 1; fusões 0, ilhas partidas 0 — OK
- **d05 com proteção autoral (por tipo de feição)**: deslocamento médio 0.00 km (0.00 px), máximo 0.00 km; área terra 1152 -> 1152 px (+0.0%); componentes 1 -> 1; fusões 0, ilhas partidas 0 — OK
