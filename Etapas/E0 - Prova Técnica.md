---
tags: [etapa]
status: em andamento
---
# E0 – Prova Técnica

**Pergunta:** o Godot dá conta dos mapas reais, da edição e da persistência na máquina de referência?

## Escopo
- [x] Base copiada do Projeto Marte; módulos de Marte e do sistema solar removidos ([[Decisões Técnicas]])
- [x] Importar os mapas do Gleba com a altitude calibrada em metros ([[Mapas do Gleba]], [[Calibração dos Mapas]])
- [x] Globo de Evron (raio 8.282,3 km) que gira e dá zoom da órbita a ~17 km do chão
- [x] 49 camadas com legenda calibrada ([[Camadas do Mapa]])
- [x] Cursor: latitude, longitude e altitude; clique fixa um ponto (certo também perto de 180° e a 70°N)
- [x] Relevo de 16K por blocos: pirâmide de 5 níveis (682 blocos de 512 px), escolha pelo zoom, carga em threads, cache de 160 blocos (~213 MiB de vídeo); o detalhe máximo chega em ~150 ms. O "16K" do Gleba é o 4K ampliado, sem detalhe novo ([[Desempenho e Escala]])
- [ ] Satélite em cor natural: a versão experimental não agradou; o do Gleba voltou a ser o padrão
- [x] Editar o terreno com pincel: elevar, rebaixar, nivelar e suavizar, com círculo de prévia; cada pincelada é um comando com desfazer e refazer (Ctrl+Z / Ctrl+Y). Uma marca de 200 km custa ~3 ms; reenviar a altitude para a GPU, ~5–9 ms. Ainda só em memória
- [ ] Persistência: SQLite pela extensão do Godot, salvar e reabrir
- [ ] Medir CPU, RAM, GPU e latência na máquina de referência ([[Desempenho e Escala]])
- [ ] Decidir o empacotamento

**Pronto quando:** as medições estiverem registradas e a escolha do motor confirmada com evidência.

Próximo: E1 em [[Etapas e Entregas]]. Código: [[Estrutura do Projeto Godot]].
