---
tags: [mundo, dados, decisao]
---
# Calibração dos Mapas

O Gleba não publica legendas numéricas. Parte dos valores foi **calibrada pelas regras físicas do próprio modelo** (limiares de Köppen e de biomas) e conferida pixel a pixel. Documento completo, JSON e scripts: `E:\ProjetoEvron\docs\calibracao\`.

## Elevação · definido + medido
- Nível do mar no pixel **32767** exato (nenhum pixel de terra abaixo).
- Duas retas (o Gleba normalizou terra e mar separados):
  - terra: `h = (p − 32767) × 9.103,40 / 17.336` (≈ 0,525 m por unidade)
  - mar: `h = (p − 32767) × 13.500 / 32.767` (≈ 0,412 m por unidade)
- Lagos acima do nível do mar existem (29.173 px) e estão certos.

## Temperatura · confiança alta
- Escala de cores **magma**: `T = −20 + 60·t` (°C, média do mês). Cinco fronteiras de Köppen caem na reta com erro ≤ 0,5 °C.
- O início da escala satura: t = 0 é "−20 °C ou menos". Máxima mensal de Evron ≈ 31 °C.

## Chuva · confiança média
- Escala **viridis**: `P = 20 + 298·t` mm/mês; abaixo, uma faixa roxo-escura que vai de 20 mm a 0.
- **Average Rainfall é a média mensal, não o total anual.**
- Acerto de 95% nas regras de Köppen; logarítmica e potências foram piores.

## Clima de Köppen · confiança alta
- As 24 cores do `Clima.png` são a paleta padrão de Beck et al. (2018). Validado pelos biomas (taiga só em ET/Dfc, mediterrânea só em Cs).

## Categorias conferidas · medido
- Rochas (37) e biomas: 100% da terra bate com o guia. Rochas no mar = cor × 0,2.

## Baixa confiança ou relativo
- Umidade e riqueza do solo: 0–100% suposto.
- Espessura e permeabilidade do solo, fluxo de água, sombra de chuva, orogenia: só valores relativos. **Dois pontos lidos no F1 do Gleba** calibrariam cada um.
- Aquíferos: profundidade 0–1.500 m e espessura 0–100 m (faixas do guia).
- Declividade e inacessibilidade: recalcular com a altitude e o raio de Evron.

## Hipóteses (confirmar)
- Províncias geológicas: plataforma, bacia oceânica, 2 variantes oceânicas, orógeno, grande província ígnea.
- Vulcanismo: arco, colisão, rifte/dorsal, ponto quente; cor escura = provavelmente menos ativo.

Ver [[Planeta Evron]], [[Camadas do Mapa]] e [[Controle Autoral]].
