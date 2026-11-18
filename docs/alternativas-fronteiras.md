# Como desenhar países no mapa: o que existe e o que ficou guardado

O mapa político de Evron pode ser desenhado de mais de um jeito. Três foram pensados; dois estão implementados e um está só projetado. Este arquivo guarda o raciocínio de
cada um, para trocar de método sem refazer a análise. O que está implementado vive em `docs/arquitetura.md` (seções "Fronteiras desenhadas à mão" e "Território pintado").

Referência visual que motivou a mudança: o mapa político de um jogo de estratégia, em que cada país é uma **mancha de cor que preenche o mapa, sem fresta**, com a borda onde duas
cores se encontram, o nome grande no centro, a população embaixo e ícones de cidades.

## Resumo

| Método | Estado | Uma frase |
|---|---|---|
| **A. Pincel de território** (camada política por pixel) | implementado, em teste | Pinta o país no globo como o pincel de terreno; um dono por pixel. |
| **B. Contorno por pontos** (polígono) | implementado e mantido | Clica ponto a ponto; um polígono por região; ótimo para regiões pequenas e para outras camadas. |
| **C. Províncias agrupadas em países** | só projetado | Desenha regiões pequenas e atribui cada uma a um país. |
| **D. Traço livre** (laço com o mouse) | só projetado | Arrasta o mouse desenhando o contorno de uma vez. |

## A. Pincel de território (implementado)

- **Dado:** `Territory.cs`, um `ushort` por pixel na mesma grade da altitude (4096 × 2048, ~9,8 km por pixel no equador); o valor é o id do cadastro do país (1 a 65535; 0 = ninguém).
  Gravado no banco numa linha só, comprimido (deflate), quase sempre abaixo de algumas centenas de KB.
- **Por que serve ao print:** um dono por pixel garante **sem fresta e sem sobreposição**, a borda nasce onde duas cores se encontram, e ilhas, buracos e países enormes (maiores que o limite de 85° do contorno)
  saem naturais. Pintar sobre outro país é uma conquista; a borracha de um país só apaga o dele.
- **Ferramentas:** pincel (raio de 20 a 2500 km), balde (preenche uma área cercada) e borracha; "só em terra" segue a costa do mapa. Tudo entra na mesma pilha de desfazer do terreno.
- **Custo:** a borda tem a resolução da grade (9,8 km): o shader a suaviza (pesos bilineares entre os 4 pixels), mas de muito perto ainda se veem degraus. Subir para 8K custa 64 MiB de RAM e de GPU.
- **Limites conhecidos:** um país só (um dono por pixel; não há "território compartilhado"); a camada de uma etnia, cultura ou religião, que se sobrepõe, continua sendo feita pelos contornos (B).

## B. Contorno por pontos (implementado e mantido)

- **Dado:** um lugar com vértices lat/lon (`place_vertex`), arcos de círculo máximo, validado (sem lados que se cruzam, com área, a menos de 85° do centro). Pode ser compartilhado e ligado a qualquer entidade por presença.
- **Quando usar:** regiões que se **sobrepõem** (o território de um país e a presença de uma cultura), áreas pequenas e precisas, e tudo que precisa de **datas** (a presença tem validade `[início, fim)`).
- **Por que não é o método do mapa político:** cada país é um polígono independente, então dois vizinhos podem deixar fresta ou se sobrepor (o ímã de vértices ajuda, mas não garante), e desenhar um país grande ponto a ponto é trabalhoso.

## C. Províncias agrupadas em países (projetado, não implementado)

**Ideia:** o mapa é dividido em regiões pequenas (províncias); cada província pertence a um país; o país é a união das suas províncias. As linhas finas das províncias aparecem dentro do país, como no print.

**Como encaixa no que já existe (quase tudo é reaproveitado):**
- Uma **segunda camada raster** igual à `Territory.cs`, mas o valor é o id da **província**. O pincel, o balde, a borracha, o desfazer e a gravação em banco são os mesmos; só muda o que o id significa.
- Uma tabela `province(id, name, country_id nullable)` e a cor vem do dono: a **paleta** do shader passa a ser indexada pelo id da província e guarda a cor do país dono (o mesmo truque de hoje, com outra chave).
- **Conquistar** é trocar o `country_id` de uma província (uma linha no banco, sem repintar pixels); a guerra, a população e a economia por província ficam naturais.
- No shader: uma segunda linha fina (entre províncias do mesmo país) e a linha grossa (entre países, que é a de hoje, só que comparando o país dono em vez do id).
- A **população por província** reaproveita as estimativas e distribuições: o lugar da estimativa passa a ser a província.

**Custo e riscos:** é preciso desenhar (ou gerar) dezenas a centenas de províncias antes de ter países, e atribuí-las. Vale a pena se o jogo for tratar guerra, conquista e economia por região; se o mapa político for só ilustrativo, é mais trabalho do que o pincel (A).

**Primeiro passo se for adotado:** reaproveitar o pincel de território para pintar províncias (um país "fictício" por província), e só depois introduzir a tabela de dono.

## D. Traço livre com o mouse (projetado, não implementado)

**Ideia:** arrastar o mouse desenhando o contorno de uma vez (um laço), em vez de clicar ponto a ponto.

**Como encaixa:**
- **Captura:** amostrar a posição do mouse sobre o globo a cada alguns pixels de tela, ignorando pontos muito próximos.
- **Simplificação:** reduzir o traço com Douglas–Peucker (tolerância proporcional à altura da câmera), para sobrar algumas dezenas de pontos em vez de milhares.
- **Saída, duas opções:** (1) criar um **contorno** (B) com `AddPolygonPlace` (já valida cruzamento, área e tamanho); ou (2) **preencher o laço na camada política** (A), com uma função `FillPolygon` que rasteriza o polígono na grade (varredura por linha) e atribui o dono. A opção 2 é o "laço" de um editor de imagens e combina com o pincel: contornar uma área e preencher de uma vez.
- **Risco:** um traço à mão cruza a si mesmo com facilidade (a validação do contorno recusa); na camada política não há esse problema, porque o laço é preenchido por regra par-ímpar.

**Primeiro passo se for adotado:** a opção 2 sobre a camada política, como uma ferramenta nova ao lado de Pincel, Balde e Borracha.

## Como trocar de método

- Os métodos A e B convivem hoje: o território pintado (A) cobre o mapa político; os contornos (B) servem às demais camadas e a regiões datadas. Nada precisa ser apagado para experimentar.
- Para descartar o A: remover o botão "Pintar território" da ficha (`sheet_panel.gd`, `_build_territory`), a barra `territory_panel.gd`, o roteamento do mouse em `main.gd` (`domains.painting_territory`) e `Territory.cs`/`RegistryTerritory.cs`; a migração 6 fica no banco (a tabela `territory` e a coluna `entity.color`) e pode ficar sem uso.
- Para evoluir para C ou D, ver os "primeiros passos" acima: ambos nascem do A.
