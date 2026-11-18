# Correntes de ar, massas de ar e frentes: pesquisa para o clima do jogo

Referência para deixar o clima de `scripts/sim/climate.gd` mais realista. A primeira metade explica a física (Terra e
Marte); a segunda diz **o que o nosso modelo já faz, o que falta e como acrescentar**, em ordem de custo/benefício.
Valores com "~" são aproximados; os marcados "(memória)" vêm de literatura conhecida, mas não foram conferidos online
nesta pesquisa. Os números de Marte que já estão em `docs/pesquisa-marte.md` não são repetidos aqui.

---

## 1. Resumo em 6 linhas

1. O ar anda de onde a pressão é alta para onde é baixa, mas a rotação (Coriolis) o desvia até ele correr **ao longo**
   das isóbaras. Perto do chão o atrito deixa uma parte cruzar: é isso que enche as baixas e esvazia as altas.
2. **Massa de ar** é um bolsão de milhares de km com temperatura e umidade quase iguais, herdadas da região onde ficou
   parado (fonte). **Frente** é a borda estreita entre duas massas. Quase toda a chuva das latitudes médias cai nas frentes.
3. A massa só existe se o ar "lembrar" de onde veio. Quem decide isso é o **tempo de relaxamento radiativo**: no Marte
   de hoje o ar perde a temperatura própria em ~1 sol; com 1 bar, em ~2 meses (mais que na Terra, porque a gravidade
   menor exige quase 3x mais ar por m² para dar a mesma pressão). **Massas de ar e frentes são uma recompensa da
   terraformação**: aparecem conforme a atmosfera engrossa.
4. Marte é pequeno e gira quase tão rápido quanto a Terra: os ciclones têm o mesmo tamanho físico (~700 km de raio de
   deformação), então cabem só **2 a 4** por volta do planeta (na Terra, 5 a 7). Os sistemas são grandes e regulares.
5. Nos solstícios marcianos a célula de Hadley vira **uma só**, cruzando o equador: a faixa de chuva tropical (ZCIT)
   migra muito mais para o hemisfério de verão do que na Terra.
6. O que falta no nosso modelo, por ordem de impacto: (a) **o ar não carrega temperatura** (cada célula calcula a sua do
   zero), por isso não existe massa de ar nem frente; (b) os sistemas de tempo são ruído sorteado, não nascem do
   contraste de temperatura; (c) não há subida por **convergência** do vento (ZCIT, frentes); (d) o lado de baixo da
   serra não aquece (foehn).

---

## 2. Por que o ar se move

### As forças

| Força | O que faz | Escala típica |
|---|---|---|
| Gradiente de pressão | Empurra da alta para a baixa | Diferença de ~1–2% da pressão em 1000 km |
| Coriolis | Desvia para a **direita** no norte e para a **esquerda** no sul; zero no equador | `f = 2Ω sen(lat)`. Marte: Ω = 7,09e-5 rad/s; a 45° f ≈ 1,0e-4 s⁻¹ (igual à Terra) |
| Atrito | Freia o vento perto do chão (~1 km de camada) e o faz cruzar as isóbaras | Mar: ~10–20° de cruzamento; terra rugosa: ~30–45° |
| Empuxo | Ar mais quente que o vizinho sobe; mais frio, desce | É o que faz convecção, frentes e brisas |

- **Vento geostrófico:** longe do chão e do equador, pressão e Coriolis se equilibram e o vento corre paralelo às
  isóbaras, com a baixa à esquerda no norte (Buys-Ballot). Por isso baixas giram anti-horário no norte e horário no sul.
- **Perto do equador** (|lat| < ~10°) Coriolis some: o vento vai direto da alta para a baixa. É lá que a brisa e a
  monção têm o padrão "sopra para o lado quente" que o nosso vento térmico já usa.
- **Vento térmico:** onde a temperatura muda com a latitude, o vento de oeste **aumenta com a altura**. Contraste
  equador-polo forte → jato forte → mais tempestades. É a ligação entre "quanto o polo é frio" e "quanto chove nas
  latitudes médias".

### O tamanho natural dos sistemas (raio de deformação de Rossby)

`L_R = N · H / f` (N = estabilidade, H = altura de escala, f = Coriolis). Abaixo disso o ar se ajusta como na brisa;
acima, como num ciclone.

| | Terra | Marte hoje | Marte 1 bar (N₂/O₂) |
|---|---|---|---|
| Gravidade (m/s²) | 9,81 | 3,71 | 3,71 |
| Gradiente adiabático seco g/cp | 9,8 K/km | ~4,8 K/km (CO₂, cp ≈ 770) | ~3,7 K/km (cp ≈ 1000) |
| Altura de escala | ~8 km | ~11 km | ~20+ km (ar mais quente e leve) |
| L_R a 45° | ~1000 km | ~700 km | ~1000 km |
| Volta da latitude 50° | 25 700 km | 13 700 km | 13 700 km |
| Ondas por volta (tempestades) | 5–7 | **1–3** (observado) | ~2–4 |

Na nossa grade (2,5° ≈ 148 km em Marte), um ciclone marciano tem **~30–40° de longitude** (12–16 células). Hoje
`EDDY_CELLS = 4` dá manchas de ~10°: pequenas e numerosas demais para Marte.

### Quanto tempo o ar "lembra" (relaxamento radiativo)

`τ ≈ (p / g) · cp / (4 σ T³)` — massa de ar por m² vezes calor específico, dividido por quanto ela irradia por kelvin.

| | Massa de ar por m² | τ | Consequência |
|---|---|---|---|
| Marte hoje (6 mbar, 210 K) | ~160 kg | **~1 sol** | A temperatura é do chão de cada lugar. Não há massas de ar: o tempo é quase igual todo dia |
| Terra (1 bar, 255 K) | ~10 000 kg | ~1 mês | Massas viajam milhares de km; ondas de frio, frentes |
| Marte 1 bar (270 K) | ~27 000 kg | **~2 meses** | Massas ainda mais persistentes que na Terra; estações mais atrasadas e suaves |

(Na prática o ar também troca calor com o chão por turbulência, mais rápido que por radiação: sobre terra, horas a dias;
sobre o mar, dias. A tabela dá a ordem de grandeza e, principalmente, **como ela muda com a pressão**.)

---

## 3. A circulação global

### Na Terra (três células)

| Faixa | Célula | Vento na superfície | Tempo |
|---|---|---|---|
| 0–30° | Hadley: sobe no equador, desce a ~30° | Alísios (de leste, puxando para o equador) | ZCIT chuvosa no equador; desertos a ~30° (o ar que desce aquece e seca) |
| 30–60° | Ferrel (indireta, mantida pelos ciclones) | Ventos de oeste | Ciclones, frentes, chuva o ano todo |
| 60–90° | Polar | De leste, frio | Ar seco, altas polares |

A frente polar (~50–60°) e o jato ficam na borda entre ar polar e ar tropical. A ZCIT segue o Sol com atraso de 1–2
meses e anda ~5–10° sobre o mar, até ~20–25° sobre continente (monção).

### Em Marte

- **Célula de Hadley larga e assimétrica.** Nos solstícios é uma só, de ~30°S a ~30°N na superfície (mais larga em
  altura): o ar sobe no hemisfério de verão e desce no de inverno. Nos equinócios fica brevemente com duas. A poeira pode
  dobrar a vazão da célula.
- **Por que é larga:** pela teoria de Held–Hou, a largura cresce com `√(g·H·Δθ/θ₀) / (Ω·a)`. Marte tem o raio `a`
  quase pela metade e Ω quase igual: a célula ocupa uma fração maior do planeta. Com mar e ar grosso o contraste cai e a
  célula estreita um pouco, mas deve continuar mais larga que a da Terra.
- **Assimetria do periélio:** o verão do sul cai no periélio (Ls 251°), com ~40% mais sol que o verão do norte. A célula
  de Hadley do verão do sul é a mais forte do ano. Somado ao relevo (o norte é ~5 km mais baixo), o ar que desce do
  hemisfério sul (alto) para o norte (baixo) é favorecido.
- **Tempestades de latitudes médias:** fortes no **outono, inverno e primavera do norte**, quase nenhuma no verão.
  Ondas de número 1–3, regulares (período de 2–7 sóis). Elas preferem as **planícies baixas** Acidalia, Utopia e Arcadia:
  as tempestades de poeira que cruzam o equador passam por esses três "corredores" na proporção ~4:2:1.
- **Ondas estacionárias:** Tharsis e a dicotomia norte-sul forçam uma onda fixa de número 1–2 (o vento ondula sempre nos
  mesmos lugares). É por isso que os corredores de tempestade são fixos.
- **Fluxo de condensação:** hoje ~25–30% do ar (CO₂) congela no polo de inverno e é puxado para lá. Com atmosfera de N₂
  isso some.

### Num Marte terraformado (o que esperar)

Há poucos modelos 3D de Marte terraformado. O que existe aponta para:
- Mais mar → temperatura média maior e mais chuva (o mar absorve mais sol que o solo claro).
- Com 1 bar o transporte de calor é muito mais eficiente: a obliquidade e as estações pesam menos, o contraste
  equador-polo cai (o nosso `lat_k` já faz isso, de 70 K para 50 K).
- Os modelos de Marte antigo (1 bar) mostram que é **difícil** chover muito em Marte: o planeta tende ao frio e a neve
  acumulada nas terras altas domina. Chuva forte exige mar quente e grande. Bom para o jogo: chuva é conquista.

---

## 4. Massas de ar

### Classificação de Bergeron

Duas letras: **umidade** da fonte (c = continental, seca; m = marítima, úmida) e **temperatura** (A = ártica,
P = polar, T = tropical, E = equatorial). Uma terceira letra diz como ela está em relação ao chão por onde passa:
**k** = mais fria que o chão (é aquecida por baixo → instável → cúmulos, pancadas, boa visibilidade) e
**w** = mais quente que o chão (resfriada por baixo → estável → estratos, nevoeiro, garoa, poluição presa).

| Tipo | Fonte (Terra) | Propriedades | Tempo que traz |
|---|---|---|---|
| cA | Gelo polar, Groenlândia | Muito fria e seca, estável | Frio extremo, céu limpo |
| cP | Interior de continente no inverno (Sibéria, Canadá) | Fria e seca | Onda de frio, geada; vira neve de lago sobre água aberta |
| mP | Oceano de latitude alta | Fria e úmida, instável quando vai para terra mais quente | Pancadas, neve na serra, céu mutável |
| cT | Deserto subtropical | Quente, muito seca | Onda de calor, seca |
| mT | Oceano tropical | Quente e úmida | Abafado, tempestades de verão, nevoeiro quando chega a costa fria |
| mE | Oceano equatorial | Quente, saturada | Chuva convectiva diária |

### O que faz uma região ser fonte

1. Superfície grande e **uniforme** (mar, gelo, planície, deserto).
2. Ar **parado** dias a semanas: centros de alta pressão, ventos fracos, subsidência.
3. Tempo suficiente frente ao τ da seção 2 (no Marte de hoje, nunca).

### Fontes prováveis num Marte terraformado

| Região | Tipo provável | Por quê |
|---|---|---|
| Polos / calotas residuais | cA (cAk sobre o mar) | Gelo, inverno escuro; o polo norte vira mar gelado se o oceano for grande |
| Oceano do norte (Vastitas Borealis) | mP no inverno, mT no verão | Superfície grande e uniforme; ventos de oeste |
| Hellas e Argyre (mar ou lago) | mT / mP locais | Bacias fundas: ar mais denso (Hellas ~2x a pressão de Tharsis), ar se acumula |
| Terras altas do sul | cP no inverno, cT no verão | Continente grande, alto e seco; inverno longo no afélio |
| Tharsis / Elysium | "cA de altitude" | Platô de 5–10 km: ar frio e ralo que escorre encosta abaixo (catabático) |
| Planícies do norte sem mar | cT / cP alternando | Baixas, recebem as tempestades (corredores da seção 3) |

### Como uma massa muda no caminho

| Processo | O que acontece | Exemplo na Terra | No jogo |
|---|---|---|---|
| Aquecida por baixo (k) | Fica instável, forma cúmulos, chove em pancadas | **Neve de lago**: ar cP sobre água aberta; precisa de ~75 km de mar sob o vento e o ar a ~1,5 km de altura ≥13 K mais frio que a água | Neve de efeito-mar nas costas do oceano do norte no outono |
| Resfriada por baixo (w) | Estável, nevoeiro e estratos, não chove | mT sobre corrente fria (Califórnia, Atacama) | Costas com corrente fria: nevoeiro e deserto costeiro |
| Sobe a serra | Esfria, condensa, chove a barlavento | Andes, Himalaia | Já temos (`lift`) |
| Desce a serra (**foehn**) | Aquece ~1 K/100 m (Terra) descendo; como perdeu água subindo, chega **mais quente e seca** que antes | Chinook, zonda | Lado de baixo de Tharsis, das bordas de Hellas: quente e seco |
| Subsidência | Ar que desce de alto aquece e seca; inversão térmica | Desertos subtropicais | Faixa a ~30° e centros de alta |
| Mistura e evaporação | A massa ganha umidade sobre mar e floresta | Monção | Já temos (evaporação, transpiração) |

---

## 5. Frentes

### Os quatro tipos

| Frente | O que é | Inclinação | Nuvens e chuva | Depois que passa |
|---|---|---|---|---|
| Fria | Ar frio avança e levanta o quente à frente | Íngreme (~1:50–1:100) | Faixa **estreita** (50–100 km) de cúmulo-nimbos, chuva forte e curta, rajadas | Esfria rápido, vento vira, céu abre, ar seco |
| Quente | Ar quente avança e sobe por cima do frio | Suave (~1:100–1:300) | Faixa **larga** (300–1000 km) que chega antes: cirros → altostratos → nimbostratos, chuva contínua e fraca | Esquenta, abafado |
| Estacionária | Nenhuma avança | — | Chuva persistente numa faixa por dias | Enchentes |
| Oclusa | A fria alcançou a quente; o ar quente foi levantado do chão | — | Chuva em espiral perto do centro da baixa | O ciclone morre |

A frente fria anda ~25–50 km/h, a quente ~15–25 km/h (por isso a fria a alcança). Toda frente fica num **cavado de
baixa pressão**: o vento muda de direção ao cruzá-la.

### O ciclo de vida (modelo norueguês, escola de Bergen)

1. **Frente estacionária** entre ar polar e tropical, com vento em sentidos opostos dos dois lados.
2. **Onda:** uma ondulação faz o ar quente avançar num ponto e o frio no vizinho. A pressão cai no vértice: nasce uma baixa.
3. **Maturidade:** setor quente em forma de cunha entre a frente quente (à frente) e a fria (atrás). Chuva larga na
   quente, linha de temporais na fria.
4. **Oclusão:** a fria alcança a quente; o setor quente é erguido; a baixa atinge a pressão mínima.
5. **Dissipação:** sem ar quente no chão, o contraste acaba e a baixa enche.

Dura de alguns dias a pouco mais de uma semana. Os ciclones vêm em **famílias** ao longo da frente polar, cada um num
estágio, andando com o vento de oeste. (O modelo é uma simplificação; o de Shapiro–Keyser, com a frente fria "quebrada",
descreve melhor os ciclones marítimos.)

### Frontogênese: onde as frentes nascem

Uma frente se forma onde o vento **junta** ar de temperaturas diferentes (convergência ou deformação perpendicular ao
gradiente de temperatura) e morre onde ele os separa. Na prática: na borda dos continentes no inverno (terra fria x mar
quente), na borda do gelo marinho, e ao longo da corrente de jato.

### Anticiclones

Centros de alta: o ar desce, aquece e seca → céu limpo, vento fraco, inversão (nevoeiro e geada à noite). São as
fábricas de massas de ar. Um anticiclone que "trava" (bloqueio) desvia as tempestades por semanas: ondas de calor no
verão, frio persistente no inverno. Em Marte também há bloqueios, ligados aos corredores de tempestade de poeira.

---

## 6. Circulações locais

| Circulação | Escala | Mecanismo | Em Marte |
|---|---|---|---|
| Brisa marítima/terrestre | 10–100 km, diária | Terra esquenta de dia mais que o mar | Subgrade na nossa malha (148 km); só a média conta |
| Monção | Continental, sazonal | Mesma ideia, ao longo do ano | Já temos (vento térmico) |
| Vale/montanha | Diária | Encosta aquecida puxa ar para cima de dia; à noite o ar frio escorre | **Muito forte** em Marte (relevo enorme, ar fino) |
| Catabático | Platôs e gelo | Ar frio e denso desce por gravidade, rápido | Calotas polares e Tharsis; também Valles Marineris e bordas de Hellas |
| Foehn | Sotavento de serras | Ver seção 4 | Tharsis (quase 10 km acima do entorno), Elysium, Hellas |
| Redemoinhos de poeira | <1 km | Chão muito quente sob ar frio | Comuns hoje; com mais ar e solo úmido, viram trombas/redemoinhos menores |

---

## 7. Correntes oceânicas (complemento)

O nosso `_update_currents` gira o vento ~45° (transporte de Ekman, que na verdade dá **90°** na média da camada) e trava
na costa. O que ainda dá para ganhar:
- **Ressurgência:** onde o vento empurra a água para longe da costa (costa oeste dos continentes, com ventos que vão
  para o equador), sobe água fria do fundo. Resultado: mar frio, ar estável (w), **nevoeiro e deserto costeiro**
  (Atacama, Namíbia) e muita vida marinha.
- **Intensificação de borda oeste:** as correntes quentes do lado oeste dos oceanos (Golfo, Kuroshio) são estreitas e
  rápidas; as frias do lado leste, largas e lentas. As quentes alimentam os ciclones e as costas leste ficam mais úmidas.
- **Gelo marinho:** com o mar abaixo de ~−2 °C a superfície congela, corta a evaporação e reflete o sol (realimentação
  forte). Vira fonte de ar cA.

---

## 8. O nosso modelo hoje, peça por peça

| Fenômeno | Como `climate.gd` faz hoje | Falta |
|---|---|---|
| Faixas de vento (alísios, oeste) | Fixas: `ub = -cos(3·lat)`, `vb = -0,35·sen(6·lat)` | Não migram com a estação; Hadley não vira célula única no solstício |
| Monção / brisa | `_thermal` → vento para o lado quente (`tw_u`, `tw_v`) | Bom. Falta a subida onde o vento converge (ZCIT, linha de brisa) |
| Temperatura do ar | `temp_c` calculada do zero em cada célula (latitude + altitude + estação + anomalia do mar) | **O vento não carrega calor.** Sem isso não há massa de ar, onda de frio, frente |
| Sistemas de tempo | Ruído de valor (`_eddy_noise`), força fixa por latitude (`_eddy_amp`) | Não dependem do contraste de temperatura nem da estação; tamanho ~10° (pequeno para Marte); sem formato de frente |
| Chuva de serra | `lift` pelo gradiente do relevo suavizado | Falta o lado de baixo (foehn: aquecer e secar) |
| Convecção | Só em terra quente e úmida | Falta sobre o mar quando o ar é mais frio que a água (neve/chuva de efeito-mar) |
| Correntes oceânicas | Vento girado 45°, travado na costa, leva a anomalia do mar | Falta ressurgência e gelo marinho |
| Pressão | Não existe como campo | Para mostrar altas, baixas e isóbaras no mapa |

---

## 9. Como acrescentar (em ordem de custo/benefício)

Todas as propostas cabem na estrutura atual: grades `W×H`, advecção semi-lagrangiana com `_sample`, buffers duplos
trocados em `step_end`, e o passo em pedaços do `ClimateRunner` (só ler valores do passo anterior, nunca da linha
vizinha recém-escrita). Cada uma pede um teste em `tests/suites/climate_suite.gd`.

### 9.1 Temperatura que viaja com o vento (massas de ar) — a peça central

Um campo novo `ta` = **anomalia de temperatura do ar** em relação ao equilíbrio local (o `tc` de hoje). O vento a
carrega e ela relaxa de volta ao equilíbrio com um tempo que depende da espessura do ar e da superfície.

```gdscript
const TA_RELAX_THIN := 2.0    # 1/s de clima: no Marte de hoje o ar esquece a origem quase na hora (τ ~1 sol)
const TA_RELAX_THICK := 0.05  # com 1 bar: τ de semanas, a massa atravessa o continente
const TA_RELAX_SEA := 2.0     # o mar "puxa" o ar para a temperatura dele mais rápido que a terra (fluxo de calor maior)
var ta := PackedFloat32Array()  # °C de diferença entre o ar que chegou e o equilíbrio deste lugar
var _ta2 := PackedFloat32Array()
var _teq := PackedFloat32Array()  # tc de equilíbrio do passo anterior (para a advecção ler sem depender da ordem das linhas)

# em step_rows, depois de calcular tc (equilíbrio) e o vento:
var arrived := _sample(_teq, sx, sy) + _sample(ta, sx, sy)  # temperatura do ar que chegou
var relax := lerpf(TA_RELAX_THIN, TA_RELAX_THICK, _atm) * (TA_RELAX_SEA if water else 1.0)
var a := (arrived - tc) * (1.0 - minf(1.0, relax * dt))
_ta2[idx] = a
tc += a        # a temperatura usada para saturação, neve, vegetação e o mapa passa a ser a do ar que chegou
```

O que isso faz aparecer sozinho, sem nenhuma regra especial:
- **Ondas de frio:** no inverno, ar do interior do continente ou do polo avança com o vento e congela a costa.
- **Ar quente úmido sobre terra fria** → `tc` cai sob a temperatura do ar → nevoeiro (nuvem fina) e garoa.
- **Contraste costa/interior** mais suave e realista, com a costa a sotavento do mar mais amena.
- **Gancho de jogo:** com o Marte de hoje (`relax` alto) nada muda. Conforme a pressão sobe, o tempo "ganha memória" e
  as massas de ar aparecem. Dá para mostrar isso como marco.
- Para evitar a dependência entre linhas no passo em pedaços, `_teq` guarda o `tc` do passo anterior (mesma técnica de
  `q`/`_q2`).

### 9.2 Subida por convergência (ZCIT, frentes, linhas de brisa)

Onde o vento se junta o ar não tem para onde ir a não ser para cima. Calcular a divergência do vento do passo anterior
e somar ao `lifting`:

```gdscript
const CONV_LIFT_K := 0.6  # quanto a convergência (células/s por célula) vira subida (mesma unidade de `lifting`)
var div := (wind_u[j * W + (i + 1) % W] - wind_u[j * W + (i + W - 1) % W]) * 0.5 \
	+ (wind_v[maxi(j - 1, 0) * W + i] - wind_v[mini(j + 1, H - 1) * W + i]) * 0.5
lifting += clampf(-div * CONV_LIFT_K, -0.3, 0.4)  # convergência sobe e chove; divergência desce e abre o céu
```

(Ler `wind_u/wind_v` do passo anterior tem o mesmo problema de ordem: copiar para um buffer em `step_begin`, ou aceitar
uma linha de atraso, que é imperceptível.) Resultado: faixa de chuva tropical onde os alísios se encontram, cinturão
seco a ~30° onde o ar desce, chuva na linha onde a monção encontra o vento contrário.

### 9.3 Frentes a partir do contraste de temperatura

Com `ta` (9.1) existe gradiente de temperatura do ar que se move. Uma frente é onde ele é forte; o tipo depende do lado
de onde o vento vem:

```gdscript
const FRONT_K := 0.04   # subida por (K por célula) de gradiente, com o vento atravessando
# _tair: cópia de temp_c feita em step_begin (o passo anterior), para não ler linhas recém-escritas
# gradiente da temperatura do ar, em K por célula
var gx := (_tair[j * W + (i + 1) % W] - _tair[j * W + (i + W - 1) % W]) * 0.5
var gy := (_tair[maxi(j - 1, 0) * W + i] - _tair[mini(j + 1, H - 1) * W + i]) * 0.5
var adv := -(u * gx + v * gy)   # >0: ar quente chegando (frente quente); <0: ar frio chegando (frente fria)
var front := absf(adv) * FRONT_K
lifting += front * (0.6 if adv > 0.0 else 1.0)  # a quente sobe devagar e larga; a fria é mais violenta
```

Para o formato certo: na frente quente a chuva fica larga e **antes** da linha (o `haze` sobe primeiro, em cirros); na
fria, estreita e intensa. Aproximação barata: somar `front` ao `haze_target` só quando `adv > 0`, e reduzir o
`RAIN_THRESHOLD` (pancada forte) quando `adv < 0`.

### 9.4 Sistemas de tempo que nascem do contraste (tempestades com estação e lugar certos)

Trocar a força fixa `_eddy_amp[j]` pela **taxa de crescimento de Eady**, proporcional ao contraste de temperatura
norte-sul (e ao Coriolis):

`σ ≈ 0,31 · f · |∂u/∂z| / N ≈ 0,31 · (g / (N·T)) · |∂T/∂y|`

Na prática: a cada `step_begin`, calcular por linha o gradiente médio norte-sul de `tc` (com o mar contando) e usar
`_eddy_amp[j] = smoothstep(a, b, |∂T/∂y| · |sen(lat)|)`. Ganhos:
- Tempestades fortes no **inverno** de cada hemisfério e fracas no verão (como em Marte e na Terra).
- Elas se concentram onde há contraste: borda do gelo, costa no inverno, borda do mar polar.
- Com terraformação o contraste equador-polo cai (`lat_k`): as tempestades enfraquecem, coerente com o transporte de
  calor mais eficiente.

E ajustar o tamanho para Marte: ruído com células grossas **anisotrópicas**, ~12 células em longitude por ~5 em
latitude (ondas de número 2–4), em vez do quadrado de 4×4. Para os corredores, multiplicar a força por um fator suave
que favorece as baixadas: `lerpf(0.6, 1.2, smoothstep(2000.0, -4000.0, hgt))` (Acidalia, Utopia, Arcadia ficam baixas).

### 9.5 Faixas de vento que migram com a estação

Hoje `ub`/`vb` são calculados uma vez em `setup`. Deslocar a latitude delas pelo **equador térmico** (latitude da
insolação máxima suavizada, já disponível via `season`): `lat_ef = lat - shift`, com `shift` até ~20–25° nos
solstícios, amortecido pelo mar (`SEASON_OCEAN`) e pela espessura do ar. Como o `lift` e as correntes dependem de
`wu/wv`, isso exige recalcular a parte do relevo — bastam alguns valores de `shift` pré-calculados (ex.: 9 tabelas de
−20° a +20°) e interpolar entre a mais próxima, sem custo por passo.

Efeito: a ZCIT (com 9.2) anda para o hemisfério de verão, o sul tem uma estação chuvosa tropical no periélio mais forte
que o norte, e os desertos subtropicais se deslocam com ela.

### 9.6 Foehn (sotavento quente e seco)

O `lift` já é zerado onde o ar desce (`maxf(up, 0)`). Guardar também a descida e aquecer:

```gdscript
var sink := minf(maxf(-up, 0.0) / 1000.0, LIFT_MAX)   # km que o ar desce por célula (em setup)
# em step_rows: o ar que desce aquece pelo gradiente seco (~4 K/km em Marte) se já deixou a água do outro lado
tc += sink * 4.0 * smoothstep(0.0, 0.5, 1.0 - qq / maxf(sat, 1e-6))
```

Com 9.1 o calor viaja junto: o vale a sotavento de Tharsis fica quente e seco (bom para colônia, ruim para lavoura).

### 9.7 Neve e chuva de efeito-mar

Abrir a convecção sobre o mar quando o ar está mais frio que a água (massa "k"):

```gdscript
if water:
	var unstable := s - tc   # mar mais quente que o ar que chegou (com 9.1, ar polar sobre mar aberto)
	convection = CONV_MAX * smoothstep(5.0, 15.0, unstable) * smoothstep(0.45, 0.85, 0.5 + 0.5 * eddy2)
```

A nuvem formada sobre o mar anda com o vento e descarrega na primeira costa; abaixo de 0 °C o código atual já transforma
em neve. Só funciona com 9.1 (sem ela o ar sobre o mar tem a temperatura do mar).

### 9.8 Ressurgência e gelo marinho

- Ressurgência: em células de mar vizinhas à costa onde a corrente se afasta da terra, puxar `sst` para baixo (−3 a
  −6 °C). O `OCEAN_HEAT_EFFECT` e o `_coast_anom` já levam isso ao ar e à costa: nevoeiro (haze) e menos chuva saem de
  graça.
- Gelo marinho: mar com `tc` < −2 °C para de evaporar (`evap_k` → 0) e, no shader, fica branco. Combina com o albedo de
  `docs/pesquisa-marte.md` §10.

### 9.9 Pressão diagnóstica e um modo de mapa "Massas de ar"

Sem resolver equações de pressão: `p' ≈ −k · (temperatura média da coluna − média da latitude)` (ar quente = baixa
térmica, frio = alta), mais as baixas dos sistemas de tempo (`-eddy`). Dá para:
- Um modo de mapa com `ta` em cores (azul = massa fria, vermelho = quente) e isóbaras.
- Marcar frentes onde `front` (9.3) passa de um limiar: azul com triângulos onde `adv < 0`, vermelho onde `adv > 0`.
  Lembrar de acrescentar a entrada em `ui/map_legends.gd` **na mesma ordem** do `map_mode` do shader.

### 9.10 Ventos catabáticos (opcional)

Componente de vento descendo a encosta proporcional ao frio do ar e à inclinação (`-∇hgt`), forte em calotas e platôs
no inverno. Visual (e espalha o ar frio das terras altas para as baixadas com 9.1). Prioridade baixa: na nossa grade a
maior parte é subgrade.

---

## 9b. O que já está no jogo (17/11/2026)

| Item | Estado | Onde / constantes |
|---|---|---|
| 9.1 Massas de ar | Feito | `ta`, `_theta` em `climate.gd`; `TA_RELAX_THIN/THICK/SEA`, `TA_MAX`, `LAPSE`. Relaxamento em escala log entre o ar fino e o grosso |
| 9.2 Convergência | Feito | `_pu/_pv` (vento do passo anterior), `CONV_LIFT_K` |
| 9.3 Frentes | Feito | `front` (+ quente, − fria), `FRONT_K`, `FRONT_MAX`; cirros antes da frente quente na `haze` |
| 9.4 Tempestades por contraste | Feito | `_update_storminess`, `EDDY_GRAD`; padrão 3x mais largo (`EDDY_STRETCH`); baixadas mais tempestuosas (`_storm_k`) |
| 9.5 Faixas sazonais | Feito | `_build_bands`: 5 tabelas (−20° a +20°) do vento já desviado pelo relevo, interpoladas por `itcz_lat`; `BAND_FOLLOW` (fração da declinação do Sol que a ZCIT acompanha). As correntes seguem a tabela do meio (média do ano) |
| 9.6 Foehn | Feito | `sink`, `FOEHN_K` (efeito pequeno na grade de 2,5°: ~0,5 °C de média) |
| 9.7 Efeito-mar | Feito | Convecção sobre o mar com `SEA_CONV_DT` |
| 9.8 Ressurgência e gelo marinho | Feito (sem gelo no visual) | `upwell`, `UPWELL_C`; `SEA_ICE_C` corta a evaporação, o shader ainda não pinta o gelo |
| 9.9 Mapa de massas de ar | Feito | Modo 7 do mapa; `ta` no canal A de `temp_map`, `front` no B de `weather_map` |
| 9.10 Catabáticos | Feito | `_down_u/_down_v` (encosta abaixo), `KATABATIC_K`; ativo no inverno da latitude ou com neve no chão |

Problema antigo encontrado no caminho: as correntes não têm giro de volta (a água só vai para onde o vento manda), e a
faixa de 45–60°N do oceano do norte fica ~10 °C mais fria que a latitude. Isso também cria tempestade lá o ano todo.

## 10. Ordem sugerida e testes

| # | Mudança | Esforço | Depende de | Teste sugerido (`climate_suite.gd`) |
|---|---|---|---|---|
| 1 | 9.1 Temperatura advectada | Médio | — | Com atm = 1, uma célula a sotavento de um bloco frio fica mais fria que o equilíbrio; com atm ≈ 0, a diferença é ~0 |
| 2 | 9.2 Convergência | Pequeno | — | A chuva média na faixa onde `vb` muda de sinal (equador) é maior que a 30° |
| 3 | 9.6 Foehn | Pequeno | (1 ajuda) | A célula logo depois de uma serra (vento descendo) é mais quente e seca que a de antes |
| 4 | 9.4 Tempestades por contraste | Médio | 1 | `_eddy_amp` no inverno do norte > no verão do norte, na mesma latitude |
| 5 | 9.3 Frentes | Médio | 1 | Num degrau de temperatura empurrado pelo vento, a chuva se concentra perto do degrau |
| 6 | 9.7 Efeito-mar | Pequeno | 1 | Ar frio sobre mar quente gera nuvem; ar quente sobre mar frio não |
| 7 | 9.5 Faixas sazonais | Médio | — | A latitude da chuva tropical máxima muda de sinal entre Ls 90° e Ls 270° |
| 8 | 9.8 Ressurgência / gelo | Pequeno | — | `sst` na costa de ressurgência < `sst` no meio do oceano na mesma latitude |
| 9 | 9.9 Mapa de massas de ar | Pequeno | 1, 5 | Captura no `shot.gd` |

Cuidado de desempenho: o passo roda em pedaços por quadro; 9.1–9.3 somam ~3 `_sample` e algumas contas por célula
(10 368 células), o mesmo custo de uma variável advectada a mais, como `haze`.

### Ganchos de jogo que saem disso

- **Marco "o tempo ganhou memória":** quando τ passa de alguns sóis, aparecem as primeiras frentes. Avisar o jogador.
- **Eventos:** "onda de frio" (geada mata lavoura em colônia, a partir de 9.1), "frente estacionária" (enchente, 9.3),
  "foehn" (seca de sotavento, 9.6).
- **Escolha de lugar para colônia:** costa de corrente quente x costa de ressurgência; barlavento chuvoso x sotavento
  quente; corredor de tempestades x região abrigada.

---

## Fontes

Conferidas online nesta pesquisa:
- Célula de Hadley e ondas baroclínicas em Marte: [NASA NTRS 20190001069](https://ntrs.nasa.gov/api/citations/20190001069/downloads/20190001069.pdf), [Showman et al., *Atmospheric Circulation of Terrestrial Exoplanets* (arXiv 1306.2418)](https://arxiv.org/pdf/1306.2418), [Guendelman, Waugh & Kaspi 2021](https://weizmann.ac.il/EPS/kaspi/sites/EPS.kaspi/files/publications/Guendelman-Waugh-Kaspi-2021_1.pdf), [GFDL, Wilson](https://www.gfdl.noaa.gov/bibliography/related_files/rjw0202.pdf)
- Corredores de tempestade em Marte (Acidalia, Utopia, Arcadia): [Battalio et al. 2022, energética das ondas em reanálises](https://people.earth.yale.edu/sites/default/files/battalio_2022_transient_eddy_kinetic_energetics_on_mars_in_three_reanalysis_datasets.pdf), [Battalio, bloqueios (US CLIVAR)](https://usclivar.org/sites/default/files/2024-04/battalio_michael_blocking_poster.pdf), [resumo LMD (Battalio)](https://web.lmd.jussieu.fr/~aspiga/antichambre/ABS/christophe/oral_Battalio_Joseph.txt), [NASA NTRS 20170000649](https://ntrs.nasa.gov/api/citations/20170000649/downloads/20170000649.pdf)
- Marte terraformado e Marte antigo com 1 bar: [Shimizu 2017, dissertação (Okayama)](https://epa.desc.okayama-u.ac.jp/2017/Mthesis-shimizu/doc/shimizu2017.pdf), [Wordsworth et al. 2015](https://arxiv.org/pdf/1506.04817), [Turbet et al. 2017](https://arxiv.org/pdf/1701.07886), [ROCKE-3D, oceano em Marte (NASA NTRS)](https://ntrs.nasa.gov/api/citations/20210026735/downloads/MWayPNASCircumpolarReprint.pdf), [arXiv 2603.00402](https://arxiv.org/pdf/2603.00402v1)
- Massas de ar (Bergeron): [AMS Glossary](https://glossarystaging.ametsoc.net/wiki/Warm_air_mass), [Penn State EME 810](https://courses.ems.psu.edu/eme810/node/579), [Northern Vermont Univ.](https://atmos.northernvermont.edu/classes/met130/notes/chapter11/airmass_classification.html)
- Frentes e ciclones: [NOAA JetStream, modelo norueguês](https://www.noaa.gov/jetstream/synoptic/norwegian-cyclone-model), [Univ. of Utah, notas](https://www.inscc.utah.edu/~u0028395/classes/5110/lecture_notes/norwegian_cyclone_model.pdf), [Schultz & Vaughan 2011](https://www.inscc.utah.edu/~u0028395/classes/5110/papers/Schultz+Vaughan-2011.pdf), [EUMETrain, Norueguês x Shapiro–Keyser](https://resources.eumetrain.org/data/5/569/print_2.htm), [LibreTexts, ciclones de latitudes médias](https://geo.libretexts.org/Bookshelves/Meteorology_and_Climate_Science/Atmospheric_Processes_and_Phenomena/12%3A_Extratropical_Cyclones/12.02%3A_Mid-latitude_Frontal_Cyclones)
- Modificação de massas, neve de lago e foehn: [Ohio Univ., *The Physical Environment*](https://people.ohio.edu/dyer/TPE/tpe_3e/weather_systems/air_mass_modification.html), [Univ. of Utah, neve de lago](https://www.inscc.utah.edu/~krueger/5220/Lake_Effect_Snow.pdf), [SKYbrary, efeito foehn](https://skybrary.aero/index.php/F%C3%B6hn_Effect)

Da literatura conhecida, não conferidos nesta pesquisa (memória): raio de deformação e taxa de Eady (Holton,
*An Introduction to Dynamic Meteorology*; Vallis, *Atmospheric and Oceanic Fluid Dynamics*), teoria de Held & Hou
(1980) para a largura da célula de Hadley, inclinações e velocidades típicas das frentes, ângulo do vento com as isóbaras
por atrito, ressurgência e intensificação de borda oeste (Stommel 1948), e as estimativas de τ, L_R e altura de escala
para Marte com 1 bar (contas feitas aqui com g = 3,71 m/s², cp do CO₂ ≈ 770 e do N₂/O₂ ≈ 1000 J/(kg·K)).
