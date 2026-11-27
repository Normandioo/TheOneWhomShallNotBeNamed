# Documentação

**Vivos (mantidos junto com o código):**
- [arquitetura.md](arquitetura.md): estrutura do código, convenções, fluxo, testes, blocos, edição de terreno, calendário, temperatura.
- [playtest.md](playtest.md): publicação automática e atalho de atualização dos playtesters.
- [mapa-politico.md](mapa-politico.md): plano e protótipo do mapa político.
- [alternativas-fronteiras.md](alternativas-fronteiras.md): alternativas estudadas para fronteiras.
- [riscos-baixa-memoria.md](riscos-baixa-memoria.md): riscos de RAM/GPU em máquinas fracas e o estado de cada correção. Use o monitor F3 para medir.

**Pesquisa e registros (resultado de estudos; não mudam com o código):**
- `calibracao/`: calibração dos mapas do Gleba (JSON, PDF e os scripts que a refazem).
- `pesquisa-pinceis/`: estudo comparativo dos pincéis de terreno.
- `coast_proto/`: ensaios de costa e batimetria (gerados por `tools/coast_prototype.py`; o caminho é fixo no script).
- `interface/`: imagens de referência da interface.
- `Proposta_Projeto_Evron_RPG.pdf`: a proposta original.

Os scripts de `tools/` e esta pasta se referenciam por caminho; antes de mover qualquer coisa, procure o nome da pasta no código.
