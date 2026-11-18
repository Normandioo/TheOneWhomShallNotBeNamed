---
tags: [mundo, interface]
---
# Camadas do Mapa

**51 camadas** no menu, em grupos, cada uma com legenda no canto inferior direito e o grau de confiança da [[Calibração dos Mapas]]:

- **Visão geral:** satélite do Gleba (padrão) e o satélite experimental.
- **Relevo 16K (em blocos):** o relevo de 16384 × 8192 carregado em blocos pelo zoom ([[E0 - Prova Técnica]]).

## Satélite experimental (cor natural) · não agradou, deixado de lado
Montado dos dados (`tools/build_natural.py`):
- **Terra:** mistura de chão nu, gramíneas, arbustos e árvores pelas frações da vegetação; árvores tropicais, temperadas ou coníferas pelo bioma; grama mais verde onde chove; chão nu de areia (quente) a cinza (frio); rocha nas encostas íngremes.
- **Rios:** pelo fluxo de água do Gleba (o `River.png` marca todo riacho e fica denso demais). Os grandes viram água de verdade, com curvas lisas e largura pelo fluxo; os afluentes ficam como um tom mais escuro; no seco, uma faixa verde de mata ciliar acompanha o rio. Limite: com 12,7 km por pixel, o rio mais fino tem ~13 km de largura.
- **Gelo:** clima EF e geleiras; gelo marinho onde nem o mês mais quente passa de −2 °C.
- **Mar:** pintado no shader pela profundidade, ao vivo (uma edição de terreno muda a cor). Contraste baixo, porque o fundo do Gleba é em degraus.
- Halo azul da atmosfera na borda.

## Grupos
- **Relevo:** altitude calibrada (pintada direto dos metros, mar à esquerda do 0 e terra à direita), elevação em cores do Gleba, sem gelo, era glacial, declividade do Gleba.
- **Clima:** temperatura (jan., jul.), chuva (média, jan., jul.), umidade (média, jan., jul.), Köppen, sombra de chuva, continentalidade, ventos, correntes, ZCIT, altas subtropicais, frente polar.
- **Ecologia:** biomas, vegetação.
- **Solos:** textura, riqueza, espessura, permeabilidade.
- **Hidrologia:** terra e água, rios, fluxo de água, corpos de água, bacias endorreicas, drenagem, aquíferos (corpos, profundidade, espessura), distância ao oceano.
- **Geologia:** rocha do substrato, placas, microplacas, limites de placas, orogenia, vulcanismo, províncias.
- **Organização:** regiões, super-regiões e subcontinentes do Gleba, latitude e longitude.

Camadas de categoria ou identificador não misturam pixels vizinhos.

## Planejado
- Ler no cursor o valor da camada (°C, mm), não só a altitude.
- Camadas do próprio mundo: territórios, assentamentos, rotas, populações.

Implementado na [[E0 - Prova Técnica]].
