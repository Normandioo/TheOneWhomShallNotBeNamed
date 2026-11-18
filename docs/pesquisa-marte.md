# Marte: dados para a simulação de terraformação

Referência para o jogo. Os números físicos vêm da NASA (Mars Fact Sheet) e da literatura citada no fim.
A tabela de oceanos (seção 6) foi calculada direto do nosso mapa `data/mars_height_1440x720.rh`.
Valores marcados com "~" são aproximados; os marcados com "(memória)" não foram conferidos em fonte online nesta pesquisa.

---

## 1. Resumo em 5 linhas

1. Marte tem 38% da gravidade da Terra, ar 160x mais fino (6 mbar) e quase todo de CO₂ (95%).
2. A temperatura média é −63 °C. O efeito estufa atual aquece só ~5 K (na Terra: 33 K).
3. O relevo vai de −8 km (Hellas) a +21 km (Olympus Mons). O norte é ~3 km mais baixo que o sul.
4. Só há CO₂ acessível para chegar a ~20 mbar. Uma atmosfera respirável exige importar gás, sobretudo N₂.
5. Esquentar é relativamente rápido (séculos). Produzir O₂ por plantas leva ~100 mil anos.

---

## 2. Planeta e órbita

| Grandeza | Marte | Terra | Observação |
|---|---|---|---|
| Raio médio | 3389,5 km | 6371 km | equatorial 3396,2 / polar 3376,2 km |
| Área da superfície | 1,448 × 10⁸ km² | 5,10 × 10⁸ km² | 28% da Terra |
| Gravidade | 3,71 m/s² | 9,81 m/s² | 0,38 g |
| Velocidade de escape | 5,03 km/s | 11,19 km/s | |
| Dia solar (sol) | 24 h 39 min 35 s | 24 h | |
| Ano | 687 dias terrestres = 668,6 sols | 365,25 dias | |
| Inclinação do eixo | 25,19° | 23,44° | varia de ~15° a ~45° em milhões de anos (caótico) |
| Excentricidade | 0,0934 | 0,0167 | órbita bem mais oval |
| Distância ao Sol | 1,381 a 1,666 UA (média 1,524) | 1 UA | |
| Luz solar no topo da atmosfera | 586 W/m² (493 a 717) | 1361 W/m² | variação de ±19% ao longo do ano |
| Albedo (Bond) | 0,25 | 0,30 | |
| Temperatura de equilíbrio | 210 K (−63 °C) | 255 K (−18 °C) | sem efeito estufa |

### Estações

A posição na órbita se mede pela **longitude solar (Ls)**: Ls 0° é o equinócio de primavera do norte.
O periélio (mais perto do Sol) fica em **Ls ≈ 251°**, perto do verão do sul.

| Estação (hemisfério norte) | Ls | Duração |
|---|---|---|
| Primavera | 0°–90° | 194 sols |
| Verão | 90°–180° | 178 sols |
| Outono | 180°–270° | 142 sols |
| Inverno | 270°–360° | 154 sols |

Consequência: **o verão do sul é curto e quente; o do norte é longo e ameno.**
A temporada de tempestades de poeira coincide com o periélio (Ls 180°–360°).

---

## 3. Atmosfera

### Composição atual (aprox., Curiosity/SAM)

| Gás | Fração | Pressão parcial (de 6,1 mbar) |
|---|---|---|
| CO₂ | ~95% | ~5,8 mbar |
| N₂ | ~2,8% | ~0,17 mbar |
| Ar | ~2,0% | ~0,12 mbar |
| O₂ | ~0,17% | ~0,01 mbar |
| CO | ~0,07% | |
| H₂O | ~0,02% (varia muito) | ~0,001 mbar |

### Pressão

- Média na superfície: **~6,1 mbar** (o "nível zero" do relevo MOLA foi definido perto disso).
- Topo do Olympus Mons: ~1 mbar. Fundo de Hellas: ~12 mbar.
- Varia **~25–30% ao longo do ano**: no inverno de cada polo, parte do CO₂ congela sobre ele. A pressão mínima ocorre no inverno do sul, que é mais longo.
- Densidade do ar na superfície: ~0,020 kg/m³ (Terra: 1,225). O vento empurra ~1% do que empurraria na Terra com a mesma velocidade.

### Massa de ar por pressão (útil para custos no jogo)

Pressão na superfície = peso da coluna de ar ÷ área. Como a gravidade é baixa, Marte precisa de **mais massa por m²** que a Terra para a mesma pressão.

```
massa da atmosfera (kg) = P (Pa) × 1,448e14 m² / 3,71 m/s²
1 mbar em Marte  = 3,9 × 10¹⁵ kg
1 bar em Marte   = 3,9 × 10¹⁸ kg  (76% da massa da atmosfera da Terra)
coluna de 1 bar  = 27 000 kg/m²   (Terra: 10 300 kg/m²)
```

Efeito colateral bom: 1 bar em Marte protege **mais** contra radiação que 1 bar na Terra, mesmo sem campo magnético, porque a coluna de ar é 2,6x mais pesada.

### Pressão com a altitude

```
P(h) = P0 × exp(−h / Hs)
Hs (altura de escala) = R × T / (M × g)
```

| Atmosfera | T média | M (kg/mol) | Hs |
|---|---|---|---|
| Atual (CO₂) | 210 K | 0,044 | **~11 km** |
| CO₂ grossa, mais quente | 250 K | 0,044 | ~13 km |
| Tipo Terra (N₂/O₂) | 288 K | 0,029 | **~22 km** |

Exemplos (P0 = pressão no nível zero):

| Lugar | Altitude | Hoje (P0 = 6,1 mbar, Hs 11 km) | Terraformado (P0 = 1000 mbar, Hs 22 km) |
|---|---|---|---|
| Fundo de Hellas | −8 km | 12,6 mbar | 1440 mbar |
| Planícies do norte | −4 km | 8,8 mbar | 1200 mbar |
| Nível zero | 0 | 6,1 mbar | 1000 mbar |
| Planalto de Tharsis | +5 km | 3,9 mbar | 800 mbar |
| Topo de Arsia/Ascraeus | +18 km | 1,2 mbar | 440 mbar |
| Topo do Olympus Mons | +21 km | 0,9 mbar | 390 mbar |

Como Hs em Marte é grande, **montanhas pesam menos na pressão** que na Terra (onde Hs ≈ 8,5 km).

### Temperatura com a altitude (lapse rate)

- Gradiente seco = g / cp.
  - CO₂ atual: 3,71 / ~750 ≈ **4,5–5 K/km**. O observado perto da superfície é menor, **~2,5 K/km** (a poeira aquece o ar em altura) (memória).
  - Ar tipo Terra (cp ≈ 1005): **~3,7 K/km** seco. Com umidade, ~2–3 K/km (estimativa por analogia com a Terra).
- Na Terra é 6,5 K/km. **Em Marte a altitude esfria menos.** O código usa 4 K/km (`climate.gd`, `static_t`), dentro da faixa.

### Efeito estufa e transporte de calor

- Efeito estufa atual: **~5 K**. O ar é fino demais para guardar calor.
- O ar fino tem pouca capacidade térmica. Por isso há:
  - **variação diária enorme** no solo do equador: ~60–90 K entre dia e noite (memória);
  - **grande diferença equador–polo** (o ar não leva calor ao polo).
- Com atmosfera mais grossa, as duas coisas diminuem. Na Terra (1 bar) a diferença entre equador e polo é ~50–60 K.

### Perda de atmosfera

- Marte não tem campo magnético global (só restos magnetizados na crosta do sul).
- Perda atual medida pela MAVEN: **~2–3 kg/s** (memória), maior durante tempestades solares.
- A esse ritmo, perder 1 bar (3,9 × 10¹⁸ kg) levaria **dezenas de bilhões de anos**.
- **Conclusão para o jogo: a fuga de ar não importa na escala da terraformação.** Ela importou ao longo de 4 bilhões de anos.

---

## 4. Ventos e circulação

### Padrão global

| Fenômeno | Como é em Marte | Diferença para a Terra |
|---|---|---|
| Célula de Hadley | Nos solstícios vira **uma célula só**: o ar sobe no hemisfério de verão e desce no de inverno, cruzando o equador | Mais larga e mais forte que na Terra; nos equinócios fica com duas células |
| Alísios / ventos de oeste | Existem, com o mesmo desvio de Coriolis (dia de 24,6 h) | Ventos de oeste fortes no hemisfério de inverno (jatos acima de 100 m/s em altura) |
| Ondas e frentes | Tempestades em latitudes médias, sobretudo no **inverno do norte** | Mais regulares e previsíveis que na Terra |
| Marés térmicas | Fortes: o Sol aquece a atmosfera inteira a cada dia | Fracas na Terra |
| Ventos de encosta | **Muito fortes**: o relevo é enorme (Tharsis, Valles Marineris, borda de Hellas) | Sobem a encosta de dia e descem à noite |
| Fluxo de condensação | O CO₂ que congela no polo de inverno "puxa" ar para lá | Não existe na Terra |

### Velocidades típicas na superfície

- Normais: **2–7 m/s** (Viking, InSight).
- Rajadas e tempestades: **20–30 m/s**.
- Redemoinhos de poeira (dust devils): comuns, alguns com vários km de altura.

### Poeira

- Profundidade óptica normal: ~0,3–0,9. Tempestade global de 2018: ~10 (Opportunity parou por falta de sol).
- Tempestades globais: em média **1 a cada ~3 anos marcianos**, na temporada do periélio.
- Efeito: dia mais frio na superfície, noite mais quente, ar a 20–50 km de altura bem mais quente.

---

## 5. Clima e água hoje

### Nuvens e precipitação

- **Cinturão de nuvens do afélio:** nuvens de gelo de água entre ~10°S e 30°N, em Ls ~40°–140°.
- **Capuz polar:** nuvens sobre o polo no outono/inverno.
- **Nuvens orográficas:** sobre os vulcões de Tharsis (a de Arsia Mons chega a 1800 km de comprimento).
- **Neve:** de CO₂ nos polos; de água como "virga" (cai e evapora antes do chão), vista pela Phoenix.
- **Geada e neblina:** de manhã, em crateras e cânions.

### Água líquida

| Pressão | Ponto de ebulição da água |
|---|---|
| 6,1 mbar | 0 °C (ponto triplo: abaixo disso, gelo vira vapor direto) |
| 10 mbar | 7 °C |
| 20 mbar | 17 °C |
| 50 mbar | 33 °C |
| 100 mbar | 46 °C |
| 300 mbar | 69 °C |
| 500 mbar | 81 °C |
| 1013 mbar | 100 °C |

- Hoje só as terras mais baixas (Hellas, norte) passam de 6,1 mbar. Mesmo ali a água pura ferve a ~2–5 °C.
- **Salmouras de perclorato** ficam líquidas até ~−70 °C (memória). O solo tem ~0,5% de perclorato.

### Reservas de água (GEL = camada global equivalente: profundidade se espalhada no planeta todo)

| Reservatório | Quantidade |
|---|---|
| Calotas polares | ~22–33 m GEL |
| Total perto da superfície (calotas + gelo enterrado em médias latitudes) | **~34 m GEL** |
| Água perdida desde a origem (razão D/H) | pelo menos ~137 m GEL (memória: Villanueva 2015) |
| Oceano antigo do norte (hipótese) | ~100–500+ m GEL |

1 m GEL = 1,45 × 10⁵ km³ de água.

### CO₂ disponível

- Calota sul: depósitos enterrados de gelo de CO₂ que aumentariam a pressão em até ~80% (memória: Phillips 2011).
- **Total acessível (calotas + solo + rochas): ~20 mbar**, segundo Jakosky & Edwards (2018).
- 20 mbar de CO₂ aquecem **menos de 10 K**. Não basta para terraformar.
- Robert Zubrin contesta: acredita em mais CO₂ escondido e num efeito estufa descontrolado.

---

## 6. Relevo (calculado do nosso mapa)

Estatísticas de `data/mars_height_1440x720.rh` (resolução de 0,25°, ponderado por área):

| Medida | Valor |
|---|---|
| Ponto mais baixo | −8068 m (Hellas; o real é ~−8200 m, perdido na resolução) |
| Ponto mais alto | +21 136 m (Olympus Mons) |
| Média | −551 m |
| Mediana | −154 m |
| Média do hemisfério norte | −2180 m |
| Média do hemisfério sul | +1077 m |

**Dicotomia:** o norte é ~3,3 km mais baixo que o sul. Um oceano se formaria primeiro no norte e em Hellas/Argyre.

### Feições principais

| Feição | Dado |
|---|---|
| Olympus Mons | ~21 km acima do nível zero, ~600 km de largura |
| Tharsis | domo de ~5000 km, ~10 km de altura, três vulcões de 14–18 km |
| Elysium Mons | ~12–13 km |
| Valles Marineris | ~4000 km de comprimento, até ~7 km de profundidade |
| Hellas | bacia de ~2300 km de diâmetro, ponto mais baixo do planeta |
| Argyre | bacia de ~1800 km |
| Utopia | bacia enterrada de ~3300 km nas planícies do norte |

### Tabela de oceano: água ↔ nível do mar

Calculada integrando o nosso mapa de altitude.

| Água líquida (GEL) | Nível do mar | Área coberta |
|---|---|---|
| 1 m | −6673 m | 0,4% |
| 10 m | −5688 m | 1,3% |
| 20 m | −5005 m | 2,2% |
| **34 m (toda a água conhecida hoje)** | **−4638 m** | **5,5%** |
| 50 m | −4404 m | 8,3% |
| 100 m | −3963 m | 14,8% |
| 135 m (linha de costa antiga "Deuteronilus", −3760 m) | −3760 m | 19,0% |
| 300 m | −3051 m | 26,7% |
| 500 m | −2377 m | 32,5% |
| 1000 m | −1060 m | 43,1% |
| 1500 m | 0 m | 51,2% |
| 2406 m | +1500 m | 73,8% |

---

## 7. Solo e radiação

| Item | Dado |
|---|---|
| Solo | basalto moído, óxido de ferro (cor vermelha) |
| pH | ~7,7, levemente alcalino (Phoenix) |
| Perclorato | ~0,4–0,6% em massa: tóxico para humanos, alimento para alguns micróbios |
| Nitrogênio fixado | nitratos de ~70–1100 ppm (Curiosity) (memória). Pouco para agricultura |
| Matéria orgânica | quase nenhuma |
| Radiação na superfície | ~0,64 mSv/dia ≈ 230 mSv/ano (Curiosity/RAD). Terra: ~2,4 mSv/ano |
| UV | sem camada de ozônio: UV-C chega ao chão e esteriliza a superfície |
| Inércia térmica | baixa na poeira, alta na rocha: o solo esquenta e esfria rápido |

---

## 8. Limites para a vida (marcos de jogo)

Valores de McKay et al. (fonte secundária, conferir o original antes de citar):

### Plantas e micróbios

| Gás | Limite |
|---|---|
| Pressão total | > 10 mbar (para haver água líquida) |
| CO₂ | > 0,15 mbar (fotossíntese) |
| N₂ | > 1–10 mbar (fixação de nitrogênio) |
| O₂ | > 1 mbar (respiração das plantas) |

### Humanos respirando sem equipamento

| Gás | Limite |
|---|---|
| Pressão total | > 500 mbar com mistura de gases (> 250 mbar se for O₂ puro) |
| O₂ | > 130 mbar (hipóxia) e < 300 mbar (risco de incêndio) |
| CO₂ | < 10 mbar (tóxico acima) |
| N₂ | > 300 mbar (gás de enchimento) |

### Escada de marcos sugerida

| Marco | Condição | O que muda |
|---|---|---|
| 1. Gelo derrete | P > 6,1 mbar e T > 0 °C | Lagos efêmeros nas terras baixas |
| 2. Micróbios e líquens | P > 10 mbar, T média > −20 °C local | Primeiro verde, solo começa a se formar |
| 3. Limite de Armstrong | P > 63 mbar | Humanos não precisam mais de traje pressurizado, só de máscara de O₂ e roupa térmica (memória) |
| 4. Máscara simples | P > 250 mbar | Máscara de O₂ basta |
| 5. Céu aberto | P > 500 mbar, O₂ > 130 mbar, CO₂ < 10 mbar | Respiração livre |

**Tensão de design:** o CO₂ que esquenta o planeta (marcos 1–2) precisa ser removido para os humanos (marco 5).

---

## 9. Métodos de terraformação

### Aquecer

| Método | Efeito | Fonte |
|---|---|---|
| Liberar CO₂ dos polos e do solo | até ~20 mbar, < 10 K de aquecimento | Jakosky & Edwards 2018 |
| Gases de efeito estufa artificiais (fluorados) | dezenas de K com pressões parciais pequenas, exige indústria enorme (memória) | Marinova et al. 2005; Gerstell et al. 2001 |
| **Nanobastões condutores** (~9 µm, ferro/alumínio de Marte) | **≥ 30 K** liberando 30 L/s, com vida útil de ~10 anos no ar. ~5000x mais eficiente que gases | Ansari, Kite et al. 2024 |
| Telhas de aerogel de sílica (2–3 cm) | +50 K **local**, sob a telha (memória) | Wordsworth et al. 2019 |
| Espelhos orbitais | aquecem um polo para liberar o CO₂ | Zubrin & McKay 1993 |

### Engrossar a atmosfera

- O CO₂ de Marte não basta. A pressão acima de ~20 mbar exige **importar gás**.
- O **N₂ é o gargalo para humanos**: Marte tem ~0,17 mbar, e é preciso ~300 mbar. Fontes imaginadas: cometas, amônia de corpos do sistema solar externo.

### Oxigenar

- 130 mbar de O₂ em Marte = ~5 × 10¹⁷ kg de O₂.
- A biosfera da Terra produz ~2,7 × 10¹⁴ kg de O₂ por ano, mas quase todo é consumido de volta. Só o carbono enterrado deixa O₂ sobrando.
- **Estimativa: ~100 mil anos** com biologia. Milênios com engenharia de vários terawatts (Zubrin & McKay 1993).

### Linha do tempo realista (McKay)

| Fase | Tempo |
|---|---|
| Aquecer e engrossar com CO₂ | ~100 anos (se houver CO₂) |
| Ecossistema de plantas/micróbios | séculos a milênios |
| Ar respirável por biologia | ~100 000 anos |

O jogo acelera isso (começa em 2070). É uma escolha de design válida, mas vale saber a escala real.

---

## 10. Albedo das superfícies (para feedback de clima)

| Superfície | Albedo |
|---|---|
| Geada fresca de CO₂ | 0,6–0,8 |
| Calota de gelo de água com poeira | ~0,4–0,6 |
| Poeira clara (Tharsis, Arabia) | 0,25–0,30 |
| Basalto escuro (Syrtis Major) | 0,10–0,15 |
| Oceano | ~0,06 |
| Floresta | 0,10–0,15 |
| Campo / savana | ~0,20 |
| Nuvens | 0,4–0,8 |

Feedbacks importantes:
- Gelo derrete → superfície escurece → mais calor (positivo).
- Oceano e floresta são escuros → esquentam o planeta.
- Mais nuvens → refletem luz (esfria) mas seguram calor à noite (aquece).

---

## 11. Fórmulas prontas para o código

```gdscript
# Luz solar no topo da atmosfera (W/m²) conforme a posição na órbita.
# ls_deg = longitude solar; periélio em Ls 251°.
func solar_flux(ls_deg: float) -> float:
	var e := 0.0934
	var r := 1.524 * (1.0 - e * e) / (1.0 + e * cos(deg_to_rad(ls_deg - 251.0)))
	return 586.2 * pow(1.524 / r, 2.0)

# Declinação do Sol (graus): latitude onde o Sol fica a pino ao meio-dia.
func declination(ls_deg: float) -> float:
	return rad_to_deg(asin(sin(deg_to_rad(25.19)) * sin(deg_to_rad(ls_deg))))

# Insolação média do dia (W/m²) numa latitude.
func daily_insolation(lat_deg: float, ls_deg: float) -> float:
	var phi := deg_to_rad(lat_deg)
	var d := deg_to_rad(declination(ls_deg))
	var c := clampf(-tan(phi) * tan(d), -1.0, 1.0)
	var h0 := acos(c)  # meio arco do dia
	return solar_flux(ls_deg) / PI * (h0 * sin(phi) * sin(d) + cos(phi) * cos(d) * sin(h0))

# Pressão local (mbar) a partir da pressão no nível zero.
func local_pressure(p0_mbar: float, h_m: float, scale_height_m: float) -> float:
	return p0_mbar * exp(-h_m / scale_height_m)

# Ponto de ebulição da água (°C) para uma pressão (mbar). Equação de Antoine, válida de ~1 a 1013 mbar.
func boiling_c(p_mbar: float) -> float:
	var mmhg := p_mbar * 0.750062
	return 1730.63 / (8.07131 - log(mmhg) / log(10.0)) - 233.426
```

---

## 12. O que isto muda no jogo atual

Comparação com o código em `scripts/main.gd` e `scripts/climate.gd`.
Itens 1–4 já aplicados: `MarsPhysics.water_gel`, `Hypsometry.sea_level_for`, `MarsPhysics.local_atmosphere`, `lat_k` em `sim/climate.gd`, estações (`MarsPhysics.orbit`, `MarsPhysics.daily_insolation`, `Climate.season`, uniform `cap_season` no shader), modo "Permitir extremos" (`PlanetState.EXTREME_MAX`, `MarsPhysics.boiling_c`/`vapor_fraction`), efeito estufa descontrolado por vapor d'água (`PlanetState.greenhouse_c`) e a vegetação devolvendo isso ao clima (seção 6 da pesquisa): reciclagem de chuva (`Climate.land_evap_rate`), aquecimento por albedo (`PlanetState.veg_warming_c`). A geração lenta de gases pela biosfera (~100 mil anos, seção 9) chegou a ser feita e foi cortada: na escala real não muda nada que o jogador veja.

**Calota sazonal e velocidade do gelo.** A calota de CO₂/água de Marte hoje chega a **~55–60° de latitude** no inverno ([NASA/JPL](https://www.jpl.nasa.gov/images/pia01247-seasonal-changes-in-mars-north-polar-ice-cap/), [Wikipedia](https://en.wikipedia.org/wiki/Martian_ice_caps)); o shader (`shaders/globe.gdshader`, uniform `cap_season`) agora calibra a amplitude sazonal pra bater com isso em vez de um valor arbitrário. Fervura (líquido -> vapor) continua rápida (`WATER_RATE`, é rápida na vida real também), mas congelar/derreter um oceano ou calota inteiros agora é devagar de propósito (`main.ICE_RATE`, ~2000 anos de jogo pra trocar tudo): um oceano tem inércia térmica enorme, não vira gelo em poucos segundos de simulação. A água líquida deixou de ter seu próprio atraso — ela é só o que sobra depois do vapor (rápido) e do gelo (lento), por conservação de massa.

**Usina de chuva (indústria).** Mesmo terraformado por inteiro, o clima sozinho nunca molha o interior de um continente grande sem montanha nem costa perto (seção 6: chuva só nasce onde o ar é forçado a condensar, por relevo ou diferença de temperatura mar/terra — ver a dúvida sobre as nuvens grudarem na costa). Em vez de mudar a física do clima, a colônia fundada pelo jogador virou uma usina de chuva local: força condensação num raio ao redor (`Climate.set_industry`, `Climate.INDUSTRY_RADIUS`/`INDUSTRY_RATE` em `climate.gd`), chamada de `main.gd` toda vez que uma colônia é fundada. Ainda depende de atmosfera e temperatura razoáveis — não cria vegetação em lugar impossível (topo de montanha, polo gelado) — só resolve a falta de fonte de condensação natural longe da costa. Ideia de jogo, não um fenômeno real; o limite físico de verdade (montanha muito alta, oceano) continua valendo, como a conversa sobre cobrir o planeta inteiro concluiu.

1. **Nível do mar (`SEA_FULL = 1500 m`).** Pela tabela da seção 6, isso exige ~2400 m GEL de água: ~70x tudo o que se conhece. Toda a água conhecida dá um mar a **~−4640 m**. Um oceano do tamanho do antigo (~135–300 m GEL) fica entre −3760 e −3050 m.
2. **Pressão igual no planeta inteiro.** Hoje `pressure_mbar` é um número só. Com `local_pressure`, Hellas teria ~2x a pressão de Tharsis. A água derreteria e a vida surgiria primeiro nas terras baixas, como seria na realidade.
3. **Diferença equador–polo fixa (`lat_t`, ~70 K).** Ela deveria cair com a pressão: ~60–70 K hoje, ~40–50 K com 1 bar.
4. **Sem estações.** Ls, excentricidade e inclinação de 25° ainda não existem no modelo. As fórmulas da seção 11 resolvem isso.
5. **Gases separados.** O jogo tem uma barra "Atmosfera". Separar CO₂, N₂ e O₂ permitiria os marcos da seção 8 e a tensão entre aquecer e respirar.

---

## Fontes

Conferidas online nesta pesquisa:
- [NASA Mars Fact Sheet](https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html)
- Jakosky & Edwards 2018, *Inventory of CO₂ available for terraforming Mars*, Nature Astronomy: [Astronomy.com](https://www.astronomy.com/science/theres-not-enough-co2-to-terraform-mars/), [Sci.News](https://www.sci.news/space/mars-terraforming-06258.html), [Scientific American](https://www.scientificamerican.com/blog/observations/can-mars-be-terraformed/)
- Ansari, Kite et al. 2024, *Feasibility of keeping Mars warm with nanoparticles*, Science Advances: [arXiv 2409.03925](https://arxiv.org/abs/2409.03925), [EurekAlert](https://www.eurekalert.org/news-releases/1053947), [Space.com](https://www.space.com/mars-terraforming-engineered-dust-nanoparticles)
- Limites de habitabilidade (McKay et al., cópia secundária): [McKay 2008, slides](https://de.slideshare.net/sacani/ecosynthesis-mckay2008reviewaaas), [Nautilus](https://nautil.us/make-mars-great-again-236288/)
- Zubrin & McKay 1993, *Technological requirements for terraforming Mars*: [marspapers.org](https://marspapers.org/paper/Zubrin_1993_3.pdf)
- Reservas de água: [National Academies 2003](https://www.nationalacademies.org/read/10715/chapter/8), [Clifford & McCubbin, EPSC 2015](https://meetingorganizer.copernicus.org/EPSC2015/EPSC2015-876-1.pdf), [Jakosky, MTT 2025](https://www-mars.lmd.jussieu.fr/mtt2025/abstracts/Jakosky.pdf)

Valores marcados "(memória)" vêm de literatura conhecida, mas não foram conferidos nesta pesquisa: MAVEN (perda de gás), Phillips 2011 (CO₂ enterrado), Villanueva 2015 (D/H), Wordsworth 2019 (aerogel), Marinova 2005 (gases fluorados), Curiosity/RAD e Phoenix (solo, radiação).
