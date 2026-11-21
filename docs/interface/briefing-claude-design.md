# Evron — Briefing de redesign da interface

**Para:** Claude Design · **Idioma da interface:** português do Brasil · **Resolução de referência:** 1920 × 1080 (mínima suportada: 1280 × 720)
**Anexos:** as 9 capturas da interface atual em `screens/` (estão citadas ao longo do texto pelo nome do arquivo).

---

## 1. Resumo em um minuto

**O que é o Evron.** Uma ferramenta de desktop (Windows e Linux, feita em Godot 4.7) para **criar, organizar e simular um mundo de RPG**: um planeta 3D do tamanho da Terra, com relevo, clima e biomas reais importados, sobre o qual uma única pessoa — o autor do mundo — desenha países, províncias, religiões, culturas, cidades, população e história.

**O que queremos.** Refazer a interface para que ela **pareça e funcione como um jogo de Grand Strategy** (Europa Universalis, Victoria 3, Crusader Kings) e seja **muito mais fácil de usar**. O autor vai passar **muitas horas por sessão**, durante semanas, dentro do programa. O fluxo de trabalho precisa ser **fluidíssimo**: sem ter que adivinhar o que cada botão faz nem onde ele está.

**O problema de hoje, em uma frase.** A interface cresceu por acréscimo: cada funcionalidade nova ganhou o seu próprio painel, botão ou janela, e o resultado é um conjunto de peças soltas que se sobrepõem, repetem nomes e escondem o que é mais usado.

**O que pedimos a você** (detalhes na seção 9): uma proposta completa de design — arquitetura de informação, wireframes, sistema de design com componentes, mockups das telas principais, tabela de atalhos e notas para implementar em Godot.

**Como julgaremos o resultado** (seção 3): as tarefas mais comuns em poucos cliques; o modo atual sempre visível; nada se sobrepõe; o globo continua sendo o protagonista da tela.

---

## 2. Produto e usuário

### 2.1 O produto

- Um **globo 3D** é a tela principal. O planeta tem raio de 6.371 km. A base é um conjunto de mapas reais (altitude, clima, biomas, solos, rios…) com ~9,8 km por pixel no equador e relevo em alta resolução por blocos quando a câmera se aproxima.
- Tudo é feito **sobre o mapa**: selecionar um país clicando nele, pintar território, esculpir relevo, ver uma camada de clima ou de geologia.
- O mundo tem **tempo próprio**: um calendário de 365 dias, uma data atual e a possibilidade de **consultar o passado** (nomes, vínculos e presenças variam por data) e voltar ao presente.
- Existe uma camada de **dados sem código**: o autor cria tipos de cadastro, campos, vínculos e regras de cálculo pela interface.

### 2.2 O usuário

- **Uma pessoa só**, autora do mundo (mestre de RPG / construtor de mundo). Não é um jogador competindo: é quem decide tudo.
- Usuário avançado e dedicado, mas **não programador**. Sessões longas e repetitivas (pintar dezenas de províncias, cadastrar centenas de entidades).
- Usa **mouse e teclado**. Não há toque nem controle.

### 2.3 O que o autor faz, e com que frequência

| Atividade | Frequência | Observação |
|---|---|---|
| Girar, aproximar, selecionar no mapa | contínua | é o "chão" de tudo |
| Trocar o que o mapa mostra (política, clima, relevo…) | muito alta | 54 camadas hoje |
| Pintar território (países, províncias, municípios) | muito alta | a tarefa mais longa |
| Abrir e editar a ficha de uma entidade (nome, vínculos, população) | muito alta | |
| Desfazer / refazer | muito alta | Ctrl+Z / Ctrl+Y |
| Criar uma sociedade nova (país + cultura + etnia) | alta | |
| Pintar áreas de religião, cultura, etnia, raça, idioma | alta | mesma mecânica do território |
| Mudar a data do mundo e comparar épocas | alta | |
| Esculpir o relevo (montanhas, vales, erosão) | média | |
| Desenhar contorno de lugar à mão | média | |
| Criar tipos, campos, regras | baixa, mas importante | configuração do mundo |
| Exportar / importar o mundo, calendários | baixa | |

---

## 3. Metas e critérios de sucesso

**Metas**

1. **Fluidez.** As tarefas frequentes cabem em **no máximo 2 cliques ou 1 atalho**. Nenhuma tarefa de uso diário exige abrir uma janela modal.
2. **Descobribilidade.** Cada função tem um nome claro, um ícone coerente e uma dica (tooltip) que mostra o atalho. **Cada coisa tem um lugar só**, previsível.
3. **Contexto.** O que está selecionado decide o que aparece. O **modo atual** (navegar, pintar país, pintar província, esculpir relevo…) fica **sempre visível** e fácil de sair (Esc).
4. **Sensação de Grand Strategy.** Barra superior com data e controle de tempo, modos de mapa laterais, painel de contexto do selecionado, dicas ricas ao passar o mouse, avisos discretos.
5. **O mapa em primeiro lugar.** Com qualquer painel aberto, o globo ainda ocupa a maior parte da tela; os painéis recolhem, não se empilham.
6. **Sessões longas.** Baixo cansaço visual (contraste, tamanho de fonte, densidade), sem pop-ups desnecessários, **desfazer e estado de gravação à vista**.

**Anti-metas**

- Não esconder funções poderosas para "simplificar": elas só precisam estar organizadas.
- Nada de animações longas ou efeitos que atrasem o trabalho repetitivo.
- Nada que exija rolagem para uma ação frequente.
- Não tratar o usuário como iniciante: é uma ferramenta profissional de autoria.

**Como medir** (pedimos que o design indique o número de passos de cada uma, hoje e na proposta):

| # | Tarefa | Hoje (aprox.) | Alvo |
|---|---|---|---|
| T1 | Criar um país novo e pintar o território dele | ~9 cliques, com painel sobreposto | ≤ 4 |
| T2 | Criar uma província dentro do país e pintá-la | ~5 | ≤ 3 |
| T3 | Trocar o mapa para "clima" e ler a legenda | 3, legenda em outro painel | 1 (um clique no modo de mapa) |
| T4 | Ver o mundo numa data do passado e voltar ao presente | ~5 | ≤ 3 |
| T5 | Achar uma entidade pelo nome e abrir a ficha | 2–3 | 1 atalho + digitar |
| T6 | Esculpir uma serra e desfazer | 3 + sliders | ≤ 2 |
| T7 | Pintar a área de uma religião | ~9 | ≤ 4 |
| T8 | Exportar o mundo | 3 | ≤ 2 |

---

## 4. A interface atual

### 4.1 Mapa da tela (1920 × 1080)

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ Evron │ Navegar  Terreno │ ↶ ↷ │ [Edição territorial]            [Mapa] [Cadastros] [Legenda]│  barra superior
│  (quando "Terreno" está ativo, abre uma 2ª linha: 7 pincéis + 3 sliders e EMPURRA os painéis)    │
├───────────────┐                                                       ┌────────────────────────┤
│ Camadas do    │                                                       │ Cadastros (busca) ou   │
│ mapa          │                                                       │ Ficha (5 abas)         │
│  · camada ▼   │                                                       │  · e, por cima dela:   │
│  · território │            G L O B O   3 D                            │ barra de pintar        │
│  · leitura do │      (clique seleciona; arrastar gira;                │ território (flutuante) │
│    cursor     │       roda aproxima)                                  │                        │
│  · exportar / │                                                       └────────────────────────┤
│    importar   │                                                       ┌────────────────────────┤
├───────────────┘                                                       │ Legenda (camada atual) │
│ Presenças no mapa (recolhido)                                         └────────────────────────┘
│ ┌───────────────────────────────────────────────┐
│ │ data · pausado · Continuar · velocidade ▼ · Calendário · Avançar…                            │  barra de tempo
└─┴───────────────────────────────────────────────┘
```

Medidas aproximadas hoje: barra superior ~52 px de altura; painel esquerdo 350 px de largura; painel direito (busca/ficha) 320–505 px; barra de tempo ~895 × 58 px.

### 4.2 Inventário por painel (o que existe de verdade)

**Barra superior** (`01_inicio_mundo_vazio.png`)
- Marca "Evron" (fonte com serifa, cor latão).
- **Navegar** e **Terreno** (alternam o modo; "Terreno" abre uma segunda linha). **Desfazer** e **Refazer** (só ícones; a dica mostra o nome do que será desfeito).
- Indicador de texto "Edição territorial" quando se está pintando território.
- À direita, três botões que **abrem e fecham painéis**: **Mapa**, **Cadastros**, **Legenda**.

**Painel esquerdo, "Camadas do mapa"** (sempre aberto por padrão; `02_…png`)
- Menu suspenso com **54 camadas em 8 grupos** (Visão geral 4, Relevo 6, Clima 17, Ecologia 2, Solos 4, Hidrologia 10, Geologia 7, Organização 4). Lista completa no Apêndice B.
- Caixa **"Mostrar território"** e, ao lado, menu **Países / Províncias / Municípios / Religiões / Culturas / Etnias / Raças / Idiomas** (qual camada territorial editar e ver).
- **Leitura do cursor** (latitude, longitude, altitude, e uma linha "Camada de teste (demonstrativa)" que é sobra de um módulo de demonstração) e a mesma leitura repetida para o **ponto fixado** por clique; altitude da câmera.
- Botões **Exportar mundo…** e **Importar mundo…**.

**Cadastros** (painel direito; botão "Cadastros" na barra superior)
- Título, menu **＋ Novo** (Cultura, País, Raça, Etnia, Idioma, Religião, Província, Município, tipos criados pelo usuário, e "Sociedade (país + cultura + etnia)").
- Botões **Calendários…**, **Tipos…**, **Regras…**.
- Campo de busca por nome (acha também nomes alternativos e históricos), filtro por tipo e lista de resultados.

**Ficha** (substitui o painel de busca ao abrir uma entidade; `02`, `03`, `04`)
- Cabeçalho: "Ficha · País", botão **Pincel de fronteira** (só para quem tem território), fechar.
- **5 abas:** **Geral** (nome, resumo, etiquetas, nomes alternativos, "Adicionar informação…" com os campos do tipo, Duplicar, Excluir) · **Relações** (vínculos tipados e datados) · **Mapa** (território: área, cor, **Pintar território**, **Apagar território**, **Nova província**; presença no mapa: vincular a um lugar, criar lugar no ponto fixado, desenhar fronteira à mão) · **População** (estimativas por lugar e data, composição por raça/etnia/cultura/religião/idioma) · **Calendários** (calendários usados pela entidade).

**Barra de pintar território** (`05_modo_pintar_territorio.png`) — flutuante, canto inferior direito, **por cima da ficha**
- Ferramentas: **Pincel · Balde · Borracha · Conta-gotas · Fronteira**.
- Raio (slider), "Só em terra", área atual, **Unir a este** (menu de outro cadastro), **Importar PNG…**.
- "Fronteiras naturais": alcance, **Crescer este país**, **Crescer todos**, **Assentar fronteiras no relevo**.
- **Terminar** (também: Esc).
- No modo Fronteira: menu das fronteiras já desenhadas, qualidade do traço (Alta fidelidade / Equilibrado / Suavizado), mensagem de estado, **Redesenhar**, **Outro lado**.

**Ferramentas de terreno** (`06_ferramentas_de_terreno.png`)
- 7 pincéis com ícone: **Elevar, Rebaixar, Nivelar, Suavizar, Montanhas, Erosão, Vales**; sliders **Raio, Intensidade, Rugosidade**; círculo de prévia no globo.

**Barra de tempo** (canto inferior esquerdo)
- Data do mundo, estado (pausado / em execução / **CONSULTA**), **Continuar/Pausar**, menu de velocidade (só 3 opções: 1 minuto, 1 hora ou 1 dia do mundo por segundo), **Calendário** (abre uma janela com os marcos e um seletor de data para consultar o passado ou avançar até uma data) e **Avançar…** (abre uma linha de botões fixos: +1 hora, +1 dia, +7 dias, +1 mês, +1 ano). Em consulta, aparece também onde está o presente preservado.

**Presenças no mapa** (canto inferior esquerdo, recolhível): escopo ("Só a ficha aberta" / "Todas as entidades") e uma caixa por camada de presença (Fronteira política, Presença cultural, Distribuição étnica, Área linguística, Presença religiosa, Habitat de raça, mais as que o usuário criar).

**Legenda** (canto inferior direito): título e texto da camada atual, amostras de cor ou barra de escala. Fica **fechada** por padrão.

**Janelas avançadas** (diálogos genéricos do Godot, **fora do tema**)
- **Regras** (`08_janela_regras.png`): lista de regras, modo (manual/automático/desativado), **editor de nós** (Número, Campo, Vínculos, População, Área, Distância, Operação, Se → Resultado), executar na data mostrada, fixar valores.
- **Tipos, campos e vínculos** (`09_janela_tipos.png`): criar tipo de entidade, campo (texto/número/escolha/sim-não, com mínimo e máximo), camada do mapa e tipo de vínculo.
- **Importar PNG**: lista de regiões encontradas com um menu para ligar cada uma a um cadastro.
- **Calendários**: lista e formulário para criar um calendário local.
- **Desenhar fronteira de lugar**: barra com Desfazer ponto, Concluir, Cancelar (Backspace, Enter, Esc).

### 4.3 Comandos de mouse e teclado que existem hoje

| Entrada | Efeito |
|---|---|
| Clique esquerdo no globo (modo Navegar) | seleciona o país/província/lugar sob o cursor e fixa o ponto |
| Arrastar (esquerdo ou direito) | gira o globo |
| Roda do mouse | zoom logarítmico, da órbita a ~17 km do chão |
| Clique esquerdo (modos de pintar / terreno) | pinta |
| Ctrl+Z · Ctrl+Y · Ctrl+Shift+Z | desfazer · refazer · refazer |
| Esc | termina a pintura de território; cancela o desenho de lugar |
| Enter · Backspace | concluir · desfazer ponto (desenho de lugar) |

**Não há** atalhos para trocar de ferramenta, de camada, de painel nem para buscar.

### 4.4 Identidade visual atual (pode evoluir, mas é o ponto de partida)

- **Estilo:** painéis escuros azul-petróleo, borda e títulos em latão, textos em creme. Cantos de 3 px, sombra suave, linha de destaque de 2 px no topo de cada painel. Já lembra um jogo da Paradox.
- **Cores:** painel `#142328` (96% opaco) · borda `#706347` · latão `#BA9C60` · papel/texto `#F2E9D4` · botão `#25383E` · botão em hover `#345059` · botão ativo `#55462E` · campo de texto `#101C20` · foco `#F0CF82` · desabilitado `#A0A59A` sobre `#18272C`.
- **Tipografia:** títulos em serifa (Georgia, com Liberation Serif e DejaVu Serif de reserva); o resto na fonte padrão do Godot (sem serifa), 14 px.
- **Ícones:** 16 PNGs simples em `assets/ui/` (navegar, terreno, elevar, rebaixar, nivelar, suavizar, erosão, vales, desfazer, refazer, mapa, cadastros, legenda, relógio, play, pausa). Só existem na barra superior, no terreno e no tempo.
- **Cores com significado:** as seis camadas de presença têm cor própria (política laranja, cultural amarela, étnica verde, linguística azul-clara, religiosa lilás, raça rosa). Os países recebem uma cor automática distinta e o autor pode trocá-la.

---

## 5. Diagnóstico: o que está atrapalhando

Cada item aponta uma captura.

1. **A palavra "camada" tem três significados** (`01`, `02`). "Camadas do mapa" (as 54 imagens do planeta), "Presenças no mapa" (6 camadas de presença) e "Mostrar território: Países/Províncias…" (a camada que se edita). O autor não sabe qual delas está mexendo. O mesmo vale para **"Mapa"**: botão da barra superior, aba da ficha e nome de uma camada ("Mapa político").
2. **O painel esquerdo mistura cinco assuntos** (`01`): o que o mapa mostra, qual nível territorial editar, leitura do cursor, ponto fixado e exportar/importar o mundo. A linha "Camada de teste (demonstrativa)" é lixo de desenvolvimento e aparece duas vezes.
3. **Janelas se sobrepõem** (`05`). Ao pintar um território, a barra de pintar aparece flutuando **em cima da ficha**, tapando o conteúdo dela. A ficha continua aberta por trás sem necessidade.
4. **O modo de pintar é difícil de achar** (`03`). Para pintar é preciso abrir uma ficha, ir à aba **Mapa**, e clicar em **Pintar território** (ou usar o botão **Pincel de fronteira** no cabeçalho — são dois caminhos para coisas parecidas).
5. **A aba "Mapa" da ficha é um formulário longo** (`03`): território, vincular lugar, criar lugar, desenhar fronteira. Mistura ações de frequências muito diferentes.
6. **Terreno empurra tudo para baixo** (`06`). Ao ativar "Terreno" a barra cresce e os painéis descem; a tela "pula".
7. **Quatro lugares diferentes para criar/configurar** (`01`, `08`, `09`): ＋ Novo e Calendários…/Tipos…/Regras… no painel Cadastros, "Calendário" na barra de tempo e Exportar/Importar no painel de camadas. Não há uma lógica que diga onde procurar.
8. **As janelas avançadas não parecem parte do programa** (`08`, `09`): são diálogos cinza padrão do Godot, com botões e campos que ignoram o tema. Na de Regras, sem nenhuma regra cadastrada, duas listas vazias ocupam metade da janela e não há indicação do que fazer primeiro.
9. **Os controles de tempo ficam escondidos** (`01`). A data e o botão de pausa estão no canto inferior esquerdo, longe do lugar onde o olho de um jogo de estratégia espera (canto superior). "Avançar…" abre uma linha extra de botões.
10. **A legenda é um painel à parte** (`01`) e vem fechada: o autor troca a camada e não entende as cores sem abrir outro painel.
11. **O estado do programa é invisível**: não há indicação de salvamento, nem de avisos (as inconsistências entre país e província só aparecem dentro da barra de pintar), nem lista de coisas pendentes.
12. **Sem busca global nem atalhos.** Achar uma entidade exige abrir o painel Cadastros; trocar de ferramenta ou camada exige o mouse.
13. **Não há ajuda nem orientação** para um mundo vazio (`01`): a primeira tela é só o globo.
14. **Estilo inconsistente**: parte da interface tem ícones e tema; parte (janelas, abas internas, listas) não.

---

## 6. Jornadas principais (hoje e como deveria ser)

Para cada uma, pedimos ao design que mostre o fluxo em quadros, com o número de passos.

**J1 · Criar um país e pintar o território**
*Hoje:* Cadastros → ＋ Novo → País → digitar o nome (a ficha abre) → aba **Mapa** → **Pintar território** → painel flutuante cobre a ficha → pintar no globo → **Terminar**.
*Queremos:* escolher a ferramenta "País" na barra de edição, clicar no mapa e pintar; o nome e a cor se definem no próprio painel de contexto, sem sair do mapa.

**J2 · Dividir um país em províncias**
*Hoje:* ficha do país → aba **Mapa** → **Nova província** → pintar (só dentro do país) → **Terminar** → repetir tudo para a próxima.
*Queremos:* uma lista de províncias dentro do painel do país, com **"+ Província"** que já deixa o pincel ativo; trocar de província pelo mapa ou pela lista, sem fechar o modo.

**J3 · Pintar a área de uma religião / cultura / idioma**
*Hoje:* criar o cadastro → ficha → aba Mapa → Pintar território; o menu "Mostrar território" muda sozinho a camada.
*Queremos:* o mesmo fluxo do território, com o **modo de mapa** correspondente ativado automaticamente e a legenda à vista.

**J4 · Ver o mundo em outra época**
*Hoje:* barra de tempo → **Avançar…** → botões de passo fixo; para consultar uma data é preciso abrir a janela do **Calendário**.
*Queremos:* barra de tempo no topo, com uma linha do tempo ou campo de data direto, **marcos** clicáveis e um aviso claro de **"CONSULTA"** com um botão de voltar ao presente.

**J5 · Trocar o que o mapa mostra**
*Hoje:* painel esquerdo → menu com 54 itens → abrir o painel Legenda.
*Queremos:* **modos de mapa** em uma coluna de ícones (política, relevo, clima, biomas, hidrologia, geologia, cultura, religião…) com submenu para as variantes (por exemplo, clima → temperatura, chuva, ventos…) e a legenda **junto** do mapa.

**J6 · Esculpir o relevo**
*Hoje:* Terreno → pincel → três sliders → pintar → Ctrl+Z.
*Queremos:* paleta de pincéis na lateral ou numa barra inferior, sliders ao lado do cursor ou no painel de contexto, atalhos de teclado (por exemplo, `[` e `]` para o raio) e sem empurrar a tela.

**J7 · Cadastrar população e relações**
*Hoje:* ficha → abas **População** e **Relações**, com formulários próprios.
*Queremos:* o mesmo painel de contexto, com seções recolhíveis, e atalhos para os vínculos mais comuns (capital, religião oficial, idioma oficial).

**J8 · Configurar o mundo (tipos, campos, regras)**
*Hoje:* três janelas separadas, de aparência padrão.
*Queremos:* um **espaço de trabalho de configuração** (tela cheia ou painel largo, com o mesmo tema), acessível por um lugar fixo ("Configuração do mundo"), com abas Tipos, Campos, Vínculos, Camadas, Regras.

**J9 · Achar algo**
*Hoje:* painel Cadastros → campo de busca.
*Queremos:* busca global (`Ctrl+F` ou `/`) a partir de qualquer tela, com resultados por tipo e o globo voltando-se para o escolhido.

**J10 · Exportar, importar, salvar**
*Hoje:* botões no painel esquerdo; sem indicação de salvamento.
*Queremos:* menu do mundo (nome do mundo, salvar/exportar/importar), com **estado de gravação** sempre visível.

---

## 7. Direção de estilo: Grand Strategy

### 7.1 Padrões que queremos adotar

Evron **não é um jogo**, é uma ferramenta de autoria, mas a linguagem visual e a lógica de uso dos jogos da Paradox funcionam muito bem para isso. Pedimos que o design proponha, adaptando ao Evron:

- **Barra superior fixa**: nome do mundo, **data**, **pausa e velocidade**, estado de gravação e contadores úteis (por exemplo, número de países, de entidades, avisos). Inspiração: EU4/EU5, Victoria 3.
- **Modos de mapa** em coluna de ícones (política, terreno, clima, cultura, religião…), no canto, com dica ao passar o mouse. Inspiração: EU4 (map modes), Victoria 3 (map lenses).
- **Painel de contexto** do selecionado (país, província, lugar), com título, brasão ou cor, abas e seções recolhíveis; abre ao clicar no mapa e fecha com Esc. Inspiração: painel de província/país do EU4, ficha de personagem do CK3.
- **Outliner** (lista lateral recolhível) com os países e suas províncias, para navegar sem procurar no globo. Inspiração: Stellaris.
- **Dicas ricas** ao passar o mouse sobre o mapa e sobre cada botão: nome, valores, atalho. Dicas aninhadas, como no Victoria 3.
- **Avisos discretos** (toasts e uma lista de pendências): "Província X sai do país", "Lacuna de 12.000 km² sem província".
- **Minimapa** opcional, com a posição da câmera.
- **Barra de edição contextual** no rodapé central: aparece quando há ferramenta ativa (pincel, balde, borracha, conta-gotas, fronteira), com raio e opções; some quando se volta a Navegar.
- **Estética**: materiais escuros foscos, filetes e cantos em latão, tipografia com serifa nos títulos, ícones monocromáticos, destaques dourados. Já está na direção certa; falta consistência, densidade e hierarquia.

### 7.2 O que evitar

- Painéis que se sobrepõem uns aos outros.
- Janelas de configuração com aparência de outro programa.
- Mais de um caminho para a mesma ação sem motivo.
- Texto longo em botões; usar ícone + rótulo curto + tooltip.
- Cores de dados usadas como cor de interface (as cores dos países e camadas precisam se destacar da moldura).

---

## 8. Requisitos por área

**8.1 Barra superior.** Data e controle de tempo; modo de ferramenta atual; desfazer/refazer com histórico (lista dos últimos comandos); estado de gravação (salvo / alterações pendentes / erro); menu do mundo (salvar, exportar, importar, preferências); botão de busca global; indicador de avisos.

**8.2 Modos de mapa e legenda.** Os 54 modos precisam caber em uma hierarquia curta (8 grupos). Os mais usados ficam à mão; os demais, num submenu ou pesquisa. A legenda acompanha o modo e pode ser recolhida, não "fechada e esquecida". Presenças no mapa (6 camadas + as do usuário) ficam num seletor próprio, com nome diferente de "camada".

**8.3 Painel de contexto (a ficha).** Mesmo painel para qualquer entidade, com as abas atuais reorganizadas por frequência. Ações de território (pintar, apagar, nova subdivisão) como **barra de ações** no topo do painel, não escondidas numa aba. Seções recolhíveis, com a memória do estado entre entidades.

**8.4 Edição territorial.** A barra de ferramentas contextual aparece no rodapé; o painel de contexto continua visível ao lado. Ferramentas: Pincel, Balde, Borracha, Conta-gotas, Fronteira (traço aberto e contorno fechado), Importar PNG, Unir, Crescer pela terra livre, Assentar no relevo. O **nível** (país/província/município/religião…) é parte do modo, mostrado claramente, e a pintura respeita a hierarquia (província só dentro do país). A **prévia** do traço aparece quando o mouse para, e o traço se aplica ao soltar.

**8.5 Terreno.** Paleta de 7 pincéis com ícone e dica; raio, intensidade e rugosidade ao alcance sem mover a tela; atalhos de teclado para o raio e a intensidade.

**8.6 Tempo.** Data editável, pausa, velocidades, "avançar até…", marcos, e o estado **CONSULTA** sempre evidente (cor, faixa) com retorno ao presente em um clique.

**8.7 Busca e navegação de entidades.** Busca global; outliner com os países e subdivisões; resultados agrupados por tipo; ir para o selecionado no globo.

**8.8 Configuração avançada.** Tipos, campos, vínculos, camadas e regras num único espaço de trabalho com o tema do programa. O editor de nós das regras precisa de uma área de trabalho grande e uma paleta de nós clara.

**8.9 Avisos e validações.** Um lugar único para as inconsistências (província fora do país, lacuna, território sem cadastro) e para erros de gravação, com um clique que leva ao problema no mapa.

**8.10 Ajuda e primeiro uso.** Tela inicial orientadora com um mundo vazio ("Comece criando uma sociedade"), dicas de contexto e uma lista de atalhos (`F1` ou `?`).

**8.11 Acessibilidade e conforto.** Tamanho de fonte ajustável, contraste adequado, não depender só de cor para distinguir países e camadas, alvos clicáveis de pelo menos 28 px, suporte a 1280 × 720.

---

## 9. O que esperamos que você entregue

1. **Princípios e arquitetura de informação:** o mapa de onde cada função mora, com a justificativa. Um glossário único de nomes (resolver "camada", "mapa", "território", "ficha"…).
2. **Wireframes** das telas principais em 1920 × 1080 e em 1280 × 720: início (mundo vazio), mapa político com país selecionado, edição territorial, relevo, tempo/consulta, busca/outliner, configuração avançada.
3. **Sistema de design:** cores (com os papéis: moldura, dado, destaque, perigo, aviso), tipografia, espaçamento, cantos, sombras, grade, ícones; componentes com todos os estados (normal, hover, pressionado, desabilitado, foco): botão, botão de alternância, aba, lista, campo, menu suspenso, slider, caixa de seleção, tooltip, toast, painel, janela.
4. **Mockups de alta fidelidade** das mesmas telas, com os textos reais em português.
5. **Fluxos** de J1 a J10 em quadros, com a contagem de passos de hoje e da proposta.
6. **Tabela de atalhos** de teclado e mouse.
7. **Notas de implementação para Godot** (seção 10): para cada componente, o nó equivalente e o que precisa de textura ou de código.
8. **Plano de migração em etapas**, da menor mudança que traz mais ganho (por exemplo: unificar o tema e mover a barra de tempo) até a reorganização completa.

---

## 10. Restrições técnicas

- **Motor:** Godot 4.7.2 (.NET). A interface é uma árvore de nós `Control` sobre o globo 3D, estilizada por um `Theme` (caixas `StyleBoxFlat`, fontes e ícones). **Não há HTML/CSS.** Efeitos como desfoque de fundo e vidro translúcido de verdade são caros ou inviáveis; preferir cores sólidas ou levemente translúcidas e texturas de 9 fatias (`StyleBoxTexture`) para molduras ornamentadas.
- **Resolução:** referência de 1920 × 1080, mínimo de 1280 × 720. A proposta precisa dizer como cada painel se comporta em cada tamanho (larguras fixas, recolher, ancorar).
- **Entrada:** o globo recebe o mouse onde não houver painel. Todo painel deve bloquear o clique só dentro do seu retângulo. Atalhos não podem disparar enquanto se digita num campo de texto.
- **Fontes e ícones:** devem ser **redistribuíveis** (licença livre, por exemplo OFL). A fonte Georgia não existe no Linux; sugerir uma serifa livre. Ícones em SVG ou PNG de 24 e 32 px; um único estilo.
- **Idioma:** português do Brasil. Os textos precisam poder ser trocados no futuro (sem texto dentro de imagens).
- **Plataformas:** Windows e Linux (a validação no CachyOS ainda está pendente).
- **Desempenho:** a interface é quase estática; evitar o que force redesenho contínuo. O globo precisa manter ≥ 55 fps ao pintar.
- **Dados que a interface mostra e que mudam muito:** listas de até centenas de entidades, 54 modos de mapa, até milhares de pontos pintados (só o resultado aparece, não a lista).

---

## 11. Decisões em aberto (queremos a sua opinião)

1. **Um painel de contexto único ou dois** (um para países/subdivisões e outro para lugares/população)?
2. **Modos de mapa:** coluna lateral de ícones ou menu suspenso na barra superior? Como acomodar 54 variantes sem virar uma lista gigante?
3. **Configuração avançada:** janela larga, tela cheia ou painel acoplado?
4. **Outliner:** sempre visível, recolhível ou sob demanda?
5. **Mapa plano:** a especificação prevê, além do globo, uma vista de mapa plano. Como a interface se adapta aos dois?
6. **Marca visual:** manter o latão e o azul-petróleo atuais ou propor uma evolução?
7. **Primeiro uso:** assistente de início (criar mundo) ou tela vazia com dicas?

---

## Apêndice A · Glossário (termos usados no programa)

| Termo | Significado |
|---|---|
| **Mundo** | o conjunto de tudo o que o autor cria (banco de dados, relógio, relevo editado). Exporta como pasta `.world`. |
| **Cadastro / entidade** | qualquer coisa registrada: país, província, município, cultura, etnia, raça, idioma, religião, ou um tipo criado pelo usuário. |
| **Ficha** | o painel de edição de um cadastro. |
| **Vínculo** | relação tipada e datada entre dois cadastros (por exemplo, "idioma oficial", "província de"). |
| **Lugar** | um ponto, disco ou contorno desenhado no mapa. |
| **Presença** | a ligação entre um cadastro e um lugar, com uma função (capital, sede, território…). |
| **Território / área** | o que é pintado no mapa para um cadastro (um dono por pixel, por nível). |
| **Nível territorial** | país, província, município (hierarquia) ou religião, cultura, etnia, raça, idioma (independentes). |
| **Camada do mapa** | uma das 54 imagens do planeta (clima, relevo, biomas…). |
| **Camada de presença** | um conjunto de presenças do mesmo tipo desenhado sobre o globo. |
| **Fronteira natural** | crescer um território pela terra livre seguindo serras, rios e mares. |
| **Consulta** | olhar o mundo numa data do passado sem alterar o presente. |
| **Regra** | cálculo declarativo que gera um campo (por exemplo, "poder = guarnição × cidades protegidas"). |
| **Fixação** | valor que o autor decidiu e que nenhuma regra substitui. |

## Apêndice B · As 54 camadas do mapa, por grupo

- **Visão geral (4):** Satélite (Gleba) · Satélite experimental · **Mapa político** · Satélite (anterior)
- **Relevo (6):** Altitude (calibrada) · Relevo 16K (em blocos) · Elevação (cores do Gleba) · Elevação sem gelo · Elevação na era glacial · Declividade
- **Clima (17):** Temperatura sazonal (estimada) · Temperatura janeiro · julho · Chuva média mensal · janeiro · julho · Umidade média · janeiro · julho · Clima de Köppen · Sombra de chuva · Continentalidade · Ventos · Correntes oceânicas · ZCIT · Altas subtropicais · Frente polar
- **Ecologia (2):** Biomas · Vegetação
- **Solos (4):** Textura · Riqueza · Espessura · Permeabilidade
- **Hidrologia (10):** Terra e água · Rios principais · Fluxo de água · Corpos de água · Bacias endorreicas · Drenagem · Aquíferos · Profundidade dos aquíferos · Espessura dos aquíferos · Distância ao oceano
- **Geologia (7):** Rocha do substrato · Placas tectônicas · Microplacas · Limites de placas · Orogenia · Vulcanismo · Províncias geológicas
- **Organização (4):** Regiões geográficas · Super-regiões · Subcontinentes · Latitude e longitude

## Apêndice C · Funcionalidades que a interface precisa prever (roteiro)

Já existem: globo, 54 camadas, relevo editável, cadastros com ficha, tipos/campos/vínculos criados pelo usuário, regras com editor de nós, território por nível, importação de PNG, exportar/importar mundo, calendário e consulta ao passado.

Ainda virão (o design deve deixar espaço, sem desenhar em detalhe): **mapa plano**, **simulação** (ciclos econômicos e demográficos, eventos), **linhas históricas alternativas** (ramificações do mundo), **módulos** instaláveis, **reprodução** da simulação, **mais resolução** do mapa e **ferramentas de rios, lagos e costas**.

## Apêndice D · Capturas anexas

| Arquivo | Mostra |
|---|---|
| `01_inicio_mundo_vazio.png` | primeira tela com um mundo vazio |
| `02_mapa_politico_ficha_geral.png` | mapa político, país selecionado, ficha na aba Geral |
| `03_ficha_aba_mapa.png` | aba Mapa da ficha (território, presença no mapa, desenhar fronteira) |
| `04_ficha_aba_relacoes.png` | aba Relações |
| `05_modo_pintar_territorio.png` | modo de pintar território (barra flutuante sobre a ficha) |
| `06_ferramentas_de_terreno.png` | ferramentas de terreno (a barra cresce e empurra os painéis) |
| `07_satelite_sem_ficha.png` | satélite, sem ficha aberta |
| `08_janela_regras.png` | janela de Regras (diálogo fora do tema) |
| `09_janela_tipos.png` | janela de Tipos, campos e vínculos (diálogo fora do tema) |

*Nas capturas, os países de exemplo ("Reino de Aren", "Dravia") são círculos de teste, não geografia real.*
