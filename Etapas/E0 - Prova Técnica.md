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
- [ ] Relevo de 16K por blocos (pirâmide de níveis); de perto o globo ainda fica borrado (12,7 km por pixel)
- [ ] Editar um trecho de terreno com pincel, com desfazer
- [ ] Persistência: SQLite pela extensão do Godot, salvar e reabrir
- [ ] Medir CPU, RAM, GPU e latência na máquina de referência ([[Desempenho e Escala]])
- [ ] Decidir o empacotamento

**Pronto quando:** as medições estiverem registradas e a escolha do motor confirmada com evidência.

Próximo: E1 em [[Etapas e Entregas]]. Código: [[Estrutura do Projeto Godot]].
