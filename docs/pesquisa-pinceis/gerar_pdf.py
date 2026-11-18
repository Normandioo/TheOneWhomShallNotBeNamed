"""Monta o PDF do estudo a partir das figuras (figuras.py) e dos números (numeros.json).
Uso: python gerar_pdf.py <pasta_com_reportlab_se_precisar>
"""
import json
import os
import sys

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.fonts import addMapping
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(HERE, "figuras")
N = json.load(open(os.path.join(HERE, "numeros.json"), encoding="utf-8"))
V = json.load(open(os.path.join(HERE, "variedade.json"), encoding="utf-8"))

F = "C:/Windows/Fonts/"
pdfmetrics.registerFont(TTFont("Arial", F + "arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-B", F + "arialbd.ttf"))
pdfmetrics.registerFont(TTFont("Arial-I", F + "ariali.ttf"))
addMapping("Arial", 0, 0, "Arial"); addMapping("Arial", 1, 0, "Arial-B"); addMapping("Arial", 0, 1, "Arial-I")

NAVY = colors.HexColor("#1F3A5F"); GRAY = colors.HexColor("#5A6270"); LINE = colors.HexColor("#D5DAE1"); ZEBRA = colors.HexColor("#F3F5F8")
GOOD = colors.HexColor("#2E7D4F"); WARN = colors.HexColor("#B7791F"); BAD = colors.HexColor("#C0392B")
def st(name, **k):
    base = {"fontName": "Arial", "fontSize": 9.5, "leading": 13.2, "textColor": colors.HexColor("#1B1F24")}
    base.update(k)
    return ParagraphStyle(name, **base)
H1 = st("h1", fontSize=22, leading=26, textColor=NAVY, spaceAfter=3)
H2 = st("h2", fontSize=14.5, leading=18, textColor=NAVY, spaceBefore=10, spaceAfter=5)
H3 = st("h3", fontSize=11, leading=14, textColor=NAVY, spaceBefore=6, spaceAfter=2, fontName="Arial-B")
P = st("p", spaceAfter=5)
SM = st("sm", fontSize=8.4, leading=10.8)
SMB = st("smb", fontSize=8.4, leading=10.8, textColor=colors.white, fontName="Arial-B")
META = st("meta", fontSize=9, textColor=GRAY, spaceAfter=8)
CAP = st("cap", fontSize=8.3, leading=10.5, textColor=GRAY, spaceAfter=6)
BOX = st("box", fontSize=9.6, leading=13.4, backColor=colors.HexColor("#EEF3F9"), borderPadding=(6, 7, 6, 7), spaceBefore=4, spaceAfter=9)


def img(name, width_mm=174):
    path = os.path.join(FIG, name)
    w, h = PILImage.open(path).size
    return Image(path, width=width_mm * mm, height=width_mm * mm * h / w)


def table(rows, widths, header=True, extra=()):
    data = [[c if not isinstance(c, str) else Paragraph(c, SMB if (header and i == 0) else SM) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    style = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
             ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
    if header:
        style.append(("BACKGROUND", (0, 0), (-1, 0), NAVY))
    style += [("BACKGROUND", (0, i), (-1, i), ZEBRA) for i in range(2 if header else 1, len(rows), 2)]
    t.setStyle(TableStyle(style + list(extra)))
    return t


def bullets(items):
    return [Paragraph("• " + i, st("b", leftIndent=10, firstLineIndent=-8, spaceAfter=1.5)) for i in items]


def method(letter, key, title, how, signature, pros, cons, cost, source, implemented=True):
    block = [Paragraph(f"{letter} · {title}", H2), img(f"metodo_{key}.png"), Spacer(1, 3)]
    block += [Paragraph("<b>Como funciona.</b> " + how, P), Paragraph("<b>Como reconhecer nas imagens.</b> " + signature, P)]
    t = table([["Vantagens", "Limites"], [Paragraph("<br/>".join("• " + x for x in pros), SM), Paragraph("<br/>".join("• " + x for x in cons), SM)]],
              [87 * mm, 87 * mm])
    block += [t, Spacer(1, 3), Paragraph(f"<b>Custo medido aqui:</b> {cost}  ·  <b>Fonte:</b> {source}", SM)]
    return KeepTogether(block)


story = []

# ---------------------------------------------------------------------------------------------------------------- capa
story += [Paragraph("Pincéis de terreno realistas", H1),
          Paragraph("Projeto Evron · estudo comparativo (versão revisada) · 18/11/2026 · todas as imagens foram geradas implementando os métodos (docs/pesquisa-pinceis)", META),
          Paragraph("<b>A pergunta:</b> qual é o melhor método para pincéis de terreno procedurais que pareçam relevo de verdade, e como os métodos se "
                    "diferenciam na imagem?", P),
          Paragraph("<b>Resposta curta.</b> Nenhum ruído sozinho (fBm, cristas, deslocamento) chega perto de uma serra real: falta a "
                    "<b>hierarquia de drenagem</b>, isto é, cume contínuo, esporões e vales que se juntam em rios maiores. Quem produz isso é a "
                    "<b>erosão fluvial</b> (lei de potência de corrente) aplicada enquanto o terreno é soerguido (Cordonnier et al. 2016, 2023). "
                    "É o método <b>G</b>, o que organizou melhor o relevo <b>no cenário testado</b>. Mas isso não o torna um vencedor universal: o ensaio "
                    "original usava uma só cordilheira sobre uma planície (esta versão revisada acrescenta outros terrenos, sementes e alturas "
                    "equivalentes). O <b>híbrido</b> (I) é um candidato promissor, ainda por validar no editor.", BOX),
          Paragraph("<b>Atenção a duas coisas.</b> (1) O raio de Evron é <b>6.371 km</b> (a Terra), então o pixel do mapa de 4096 px mede "
                    "<b>9,8 km no equador</b> (e menos nas latitudes altas); a primeira versão deste estudo usava 12,7 km, de um raio antigo. "
                    "Mesmo assim, em um pixel dessa largura cabe um vale inteiro e as diferenças entre os métodos encolhem muito (seção 7). "
                    "(2) G e I <b>reorganizam o terreno ao redor do traço</b>, não só sob ele, e a drenagem depende da água que vem de fora "
                    "da região editada: isso ainda não foi resolvido (seção 9).", BOX),
          Paragraph("Os nove métodos testados", H2),
          table([["", "Método", "Em uma frase", "Tempo*"],
                 ["A", "Cone liso", "Soma a máscara do pincel: uma colina lisa. É o ponto de partida.", f"{N['cone']['tempo_s']:.2f} s"],
                 ["B", "Ruído fBm", "Colinas com ondulação em várias escalas.", f"{N['fbm']['tempo_s']:.2f} s"],
                 ["C", "Cristas (ridged)", "Ruído de cristas finas (Musgrave): serras e vales em V. É o 'Montanhas' do jogo.", f"{N['ridges']['tempo_s']:.2f} s"],
                 ["D", "Cristas + deslocamento", "Cristas lidas numa posição deslocada por outro ruído (Quilez): serpenteiam.", f"{N['warped']['tempo_s']:.2f} s"],
                 ["E", "+ Erosão térmica", "D mais escorrimento acima do ângulo de repouso (Musgrave 1989).", f"{N['thermal']['tempo_s']:.2f} s"],
                 ["F", "+ Erosão por gotas", "D mais milhares de gotas que entalham e depositam (Beyer 2015).", f"{N['droplets']['tempo_s']:.2f} s"],
                 ["G", "Soerguimento + erosão fluvial", "O terreno sobe sob o pincel e a água entalha por lei de potência (Cordonnier 2016).", f"{N['stream']['tempo_s']:.0f} s"],
                 ["H", "Carimbo de relevo real", "Usa um pedaço de relevo real como molde (baseado em exemplos).", f"{N['exemplar']['tempo_s']:.2f} s"],
                 ["I", "Híbrido", "D como relevo inicial mais poucos passos de erosão fluvial.", f"{N['hybrid']['tempo_s']:.0f} s"]],
                [8 * mm, 42 * mm, 105 * mm, 19 * mm]),
          Paragraph("* Tempo medido em NumPy puro numa grade de 320 × 320 células, no PC de desenvolvimento. Serve para comparar os métodos "
                    "entre si, não como previsão do tempo no jogo (ver seção 9).", CAP),
          PageBreak()]

# -------------------------------------------------------------------------------------------------- como ler as imagens
story += [Paragraph("1. Como ler as imagens", H2),
          Paragraph("Todos os métodos recebem <b>o mesmo terreno-base</b> (uma planície a ~300 m, o interior de um continente) e <b>o mesmo traço</b> "
                    "do pincel (uma curva em S de 75 km de raio, com peso 1 no eixo e 0 na borda). Assim, o que muda de uma imagem para outra vem só "
                    "do método. A grade tem 480 km de lado, com células de 1,5 km, bem mais fina que a do jogo, para mostrar o que cada método "
                    "é capaz de fazer.", P),
          img("base.png", 130),
          Paragraph("Cada método aparece em três vistas:", P)]
story += bullets(["<b>Relevo sombreado</b> (cinza): luz vinda do noroeste. É a melhor vista para ver cristas e vales: a luz revela a forma.",
                  "<b>Relevo colorido</b>: verde (planície), amarelo, marrom, branco (altitudes acima de ~4.500 m), com o mesmo sombreado.",
                  "<b>Corte transversal</b>: o perfil da altitude ao longo da linha vermelha, que cruza o traço. Um cone aparece como um morro "
                  "liso; relevo real, como uma linha serrilhada com picos e vales."])
story += [Spacer(1, 4), Paragraph("O que procurar para distinguir um terreno realista de um artificial:", H3)]
story += bullets(["<b>Hierarquia:</b> pequenos vales se juntam em vales maiores, que se juntam em rios (rede em forma de árvore).",
                  "<b>Cumes contínuos:</b> uma serra tem uma linha de cume que dura, não picos soltos espalhados.",
                  "<b>Assimetria:</b> vales são côncavos e estreitos; espigões, convexos. Ruído puro é simétrico (picos e vales parecem espelhados).",
                  "<b>Escalas misturadas:</b> grandes cristas, esporões médios e ravinas pequenas ao mesmo tempo."])
story += [PageBreak(),
          Paragraph("2. Visão geral: o mesmo traço, nove métodos", H2),
          img("visao_geral.png", 176),
          Paragraph("Compare em ordem: A é uma almofada; B, uma pele rugosa; C e D têm cristas, mas soltas e sem hierarquia; E e F suavizam; "
                    "G tem cume contínuo e ravinas ramificadas; H empresta uma forma real mas borrada; I fica entre D e G.", CAP),
          PageBreak()]

# ------------------------------------------------------------------------------------------------------ métodos
story += [Paragraph("3. Os métodos, um a um", H2)]
story += [method("A", "cone", "Cone liso (o pincel básico)",
                 "A altura do terreno ganha <i>h += A · w</i>, onde <i>w</i> vai de 1 no centro a 0 na borda: <i>(1 − (d/r)²)²</i>. Não há aleatoriedade.",
                 "Uma 'linguiça' lisa, de largura e altura uniformes, sem nenhum vale. O corte é um sino perfeito. Parece uma almofada ou massa de modelar.",
                 ["Totalmente previsível e rápido", "Ótimo para ajustar uma base (levantar um planalto, abrir uma bacia)"],
                 ["Nenhum realismo sozinho", "Sem rios, cristas nem vales"],
                 f"{N['cone']['tempo_s']:.2f} s", "base de qualquer editor de terreno"),
          method("B", "fbm", "Ruído fBm (colinas)",
                 "Soma várias camadas ('oitavas') de ruído gradiente, cada uma com o dobro da frequência e metade da amplitude: <i>fBm</i>. O pincel "
                 "multiplica a máscara por essa ondulação.",
                 "Uma pele de laranja: bolhas arredondadas de tamanho parecido, sem direção. Os picos são redondos e os vales, também (simétricos). "
                 "Nada de cristas.",
                 ["Dá colinas e morros convincentes", "Muito barato e fácil de controlar (amplitude, frequência)"],
                 ["Parece 'terreno de nuvem': simétrico, sem estrutura", "Não serve para montanhas"],
                 f"{N['fbm']['tempo_s']:.2f} s", "Perlin; amplamente usado (ver Musgrave et al. 1989)"),
          method("C", "ridges", "Cristas (ridged multifractal)",
                 "Cada oitava usa <i>(1 − |ruído|)²</i>: o valor absoluto cria dobras, e o quadrado afina as cristas. As oitavas são ponderadas pelas "
                 "anteriores, de modo que as cristas altas ganham mais detalhe. É o método do pincel 'Montanhas' do jogo.",
                 "Cristas afiadas e vales em V, aspecto de 'papel amassado'. Mas as cristas correm em todas as direções, são curtas e desconectadas, e os "
                 "vales não se juntam em vales maiores.",
                 ["Parece montanha à primeira vista", "Rápido, determinístico e fácil de dar semente"],
                 ["Sem hierarquia de drenagem", "As cristas não formam um cume contínuo"],
                 f"{N['ridges']['tempo_s']:.2f} s", "Musgrave, em 'Texturing and Modeling' (1994)"),
          method("D", "warped", "Cristas + deslocamento de domínio",
                 "Antes de ler o ruído de cristas, a posição é deslocada por outro ruído (<i>f(p + g(p))</i>). Isso torce o padrão como se fosse "
                 "empurrado por forças tectônicas.",
                 "As cristas ficam sinuosas e mais longas, parecendo dobras e falhas. Ainda não há ramificação: é a mesma textura de C, só torcida.",
                 ["Corrige o aspecto 'de grade' do ruído", "Quase de graça sobre C"],
                 ["Continua sem drenagem em árvore", "A torção não depende do declive, só do ruído"],
                 f"{N['warped']['tempo_s']:.2f} s", "Quilez, 'Domain warping' (iquilezles.org/articles/warp)"),
          method("E", "thermal", "Erosão térmica (acima de D)",
                 "Compara cada célula com as 8 vizinhas. Se o desnível passa do ângulo de repouso do material (aqui 7°), parte do excesso escorre "
                 "para a vizinha mais baixa. Repetido 120 vezes.",
                 f"Cristas arredondadas e uma 'saia' suave de entulho na base (leque de tálus). A altura máxima cai de {N['warped']['max_m']:.0f} m para "
                 f"{N['thermal']['max_m']:.0f} m e o declive de pico, de {N['warped']['declive_p95_graus']:.0f}° para {N['thermal']['declive_p95_graus']:.0f}°.",
                 ["Remove as cristas 'de agulha' do ruído", "Conserva a massa; barato", "Pode ser aplicado em qualquer terreno"],
                 ["Só suaviza: não cria vales nem rios", "Em excesso, deixa tudo borrado (como o pincel Erosão atual)"],
                 f"{N['thermal']['tempo_s']:.2f} s", "Musgrave, Kolb e Mace (SIGGRAPH 1989)"),
          method("F", "droplets", "Erosão hidráulica por gotas (acima de D)",
                 "Milhares de gotas caem aleatoriamente, descem pelo gradiente, pegam sedimento quando rápidas e o depositam quando desaceleram ou "
                 "evaporam. Aqui: 90 mil gotas de 70 passos, em lotes.",
                 "Ravinas finas descendo as encostas e pequenos leques de sedimento embaixo. O efeito é discreto sobre D e as ravinas não formam "
                 "rios grandes: cada gota vive pouco.",
                 ["Detalhe fino convincente", "Funciona em qualquer terreno, sem soerguimento"],
                 ["Precisa de muitas gotas e ajuste fino (diverge se mal calibrado: foi preciso limitar velocidade e erosão por passo)",
                  "Sem escala de bacia: não cria rios longos"],
                 f"{N['droplets']['tempo_s']:.1f} s", "Beyer (2015); descrições de implementação em itvanderveen.nl"),
          method("G", "stream", "Soerguimento + erosão fluvial (Cordonnier)",
                 "A cada passo o terreno <b>sobe</b> sob o pincel (mapa de soerguimento) e a água <b>entalha</b> pela lei de potência de corrente: "
                 "<i>dh/dt = U − K·A<super>m</super>·S</i>, com A a área de captação a montante e S o declive. Um esquema implícito torna o passo estável. "
                 "Depois de dezenas de passos, o equilíbrio entre soerguimento e erosão desenha a rede de drenagem sozinho.",
                 "Um <b>cume contínuo</b> ao longo do traço, com esporões que saem perpendiculares e se ramificam, e vales que convergem a cada nível. "
                 "A rede é em árvore, como em serras reais. O corte mostra um pico central e flancos escalonados.",
                 ["O mais realista dos testados: hierarquia de drenagem de verdade",
                  "Controle por onde o autor pinta o soerguimento (e o que sai é consistente com a água)",
                  "Cordonnier et al. (2023) mostram versões interativas"],
                 [f"O mais lento aqui ({N['stream']['tempo_s']:.0f} s, em Python)", "Menos controle fino da forma final do que com ruído",
                  "Exige tratar depressões (poços) para a água sair"],
                 f"{N['stream']['tempo_s']:.0f} s (40 passos)", "Cordonnier et al., CGF 2016; Schott et al., TOG 2023"),
          method("H", "exemplar", "Carimbo de relevo real (baseado em exemplos)",
                 "Usa um pedaço de relevo real (aqui, a cordilheira do mapa do Gleba) como molde: recorta, amplia e soma à máscara. Versões mais avançadas "
                 "(Guérin et al. 2017) treinam redes neurais que transformam um esboço em relevo.",
                 "Parece uma cópia: reaparece a forma do exemplo (o pico no canto inferior esquerdo), mas <b>borrada</b>, porque o exemplo tem pixels de "
                 "9,8 km (a grade do mapa original) e foi ampliado cerca de 8 vezes. Em outro lugar do traço a forma não se repete de modo natural. "
                 "<b>Este ensaio mede só o limite de uma fonte de baixa resolução; não avalia o potencial de carimbos feitos com elevação terrestre "
                 "medida e detalhada, que ainda não foram testados.</b>",
                 ["Detalhe e proporções de montanhas reais (com bom exemplo)", "Sem simulação: instantâneo"],
                 ["A nitidez nunca passa da do exemplo (aqui, o mapa de ~10 km por pixel do Gleba)", "Repetição visível ao usar o mesmo carimbo duas vezes",
                  "Redes neurais exigem treino, dados e GPU"],
                 f"{N['exemplar']['tempo_s']:.2f} s", "Guérin et al., SIGGRAPH Asia 2017 (versão com redes neurais)"),
          method("I", "hybrid", "Híbrido: cristas deslocadas + erosão fluvial curta",
                 "Parte do relevo de D (80% da altura), que dá a forma pedida pelo autor, e roda só 14 passos de erosão fluvial com soerguimento "
                 "fraco, o suficiente para abrir vales e juntar a água em canais sem apagar o desenho inicial.",
                 "Mantém a sinuosidade de D, mas agora há ravinas que se juntam e descem em direção à planície. É menos 'cume contínuo' que G e mais "
                 "irregular, parecido com uma serra erodida e velha.",
                 ["Combina controle de ruído com drenagem física", "Bem mais rápido que G (menos passos)", "Dá para ajustar o quanto a erosão manda"],
                 ["Mais parâmetros para equilibrar", "Resultado menos puro que G (menos coerência de cume)"],
                 f"{N['hybrid']['tempo_s']:.0f} s (14 passos)", "Combinação de D e G; sugestão deste estudo")]
story += [PageBreak()]

# ---------------------------------------------------------------------------------------------- não implementados
story += [Paragraph("4. Métodos que li, mas não implementei", H2),
          Paragraph("Estes entram na pesquisa por serem a fronteira do assunto. Não há imagem deles porque não os reproduzi (as descrições vêm de "
                    "resumos das páginas das publicações; não li os artigos completos).", P),
          table([["Método", "Ideia", "Por que não implementei"],
                 ["Rios primeiro (Génevaux et al. 2013)", "Parte de uma rede de rios desenhada ou gerada e constrói o relevo em volta dela, de modo "
                                                         "que a água sempre corre para onde deve.",
                  "Pede uma representação própria (rios como primitivas). Muda a arquitetura mais que um pincel."],
                 ["Erosão analítica (Tzathas et al. 2024)", "Calcula o terreno erodido no instante t por fórmulas fechadas, sem passos de tempo.",
                  "Muito rápido, mas os próprios autores apontam singularidades: declives muito altos nas cristas."],
                 ["Autoria interativa por soerguimento (Schott et al. 2023)", "Trabalha no domínio do soerguimento, com colar, deformar (dobras e falhas) e "
                                                                              "restrições de altura.",
                  "É a evolução natural do método G; interessante para a fase de controle fino."],
                 ["Esboço para relevo (Guérin et al. 2017)", "Redes neurais condicionais (cGAN) transformam esboços de cristas e rios em relevo detalhado.",
                  "Exige treinar com dados reais e GPU; não combina com o objetivo de funcionar local e sem dependências."],
                 ["Métricas de realismo (PTRM)", "Propõe medidas de realismo percebido de terrenos.",
                  "Só encontrei o título; sem métrica objetiva aceita, a comparação aqui é visual e por números simples."]],
                [48 * mm, 70 * mm, 56 * mm]),
          Spacer(1, 6)]

# ------------------------------------------------------------------------------------------------------- números
def row(k, name):
    v = N[k]
    return [name, f"{v['tempo_s']:.2f}", f"{v['max_m']:.0f}", f"{v['declive_medio_graus']:.1f}", f"{v['declive_p95_graus']:.1f}", f"{v['rugosidade_m']:.0f}"]


story += [Paragraph("5. Os números", H2),
          table([["Método", "Tempo (s)", "Altura máx. (m)", "Declive médio (°)", "Declive p95 (°)", "Rugosidade (m)"],
                 row("cone", "A · Cone liso"), row("fbm", "B · fBm"), row("ridges", "C · Cristas"), row("warped", "D · Cristas + deslocamento"),
                 row("thermal", "E · + térmica"), row("droplets", "F · + gotas"), row("stream", "G · Soerguimento + fluvial"),
                 row("exemplar", "H · Carimbo real"), row("hybrid", "I · Híbrido")],
                [58 * mm, 20 * mm, 24 * mm, 24 * mm, 24 * mm, 24 * mm]),
          Paragraph("Declive e rugosidade medidos dentro do traço (peso do pincel &gt; 0,3). Rugosidade = média de |Laplaciano| em metros (quanto cada "
                    "célula difere das 4 vizinhas). O declive médio e a rugosidade sobem de A a G: G tem declives 2 a 8 vezes maiores que A–D porque as "
                    "vertentes ficam entalhadas. Esses números descrevem a forma; não medem realismo.", CAP),
          Paragraph("Minha avaliação qualitativa (1 = fraco, 5 = excelente; é um julgamento meu, não uma medida):", P),
          table([["Método", "Realismo visual", "Controle do autor", "Velocidade", "Reprodutível", "Facilidade de implementar"],
                 ["A · Cone liso", "1", "5", "5", "5", "5"], ["B · fBm", "2", "5", "5", "5", "5"], ["C · Cristas", "3", "4", "5", "5", "5"],
                 ["D · Cristas + deslocamento", "3,5", "4", "5", "5", "5"], ["E · + térmica", "3", "4", "4", "5", "5"],
                 ["F · + gotas", "3", "3", "3", "4", "3"], ["G · Soerguimento + fluvial", "5", "3", "1 a 3*", "5", "3"],
                 ["H · Carimbo real", "n/a†", "4", "5", "5", "4"], ["I · Híbrido", "4", "4", "3", "5", "3"]],
                [52 * mm, 24 * mm, 24 * mm, 24 * mm, 24 * mm, 26 * mm]),
          Paragraph("* Em Python foram 65 s; em GDScript, com a região bem menor da grade do jogo (seção 8), deve ficar na casa de poucos segundos, "
                    "o que é uma estimativa a confirmar com um protótipo.", CAP),
          Paragraph("† O carimbo H só pôde ser testado com um exemplo de baixa resolução; a nota de realismo não se aplica a carimbos "
                    "de relevo detalhado.", CAP),
          img("perfis.png", 150),
          Paragraph("Cortes sobrepostos. O cone (cinza) é uma única colina. Cristas (azul) e deslocamento (verde) têm muitos picos pequenos. Soerguimento + "
                    "fluvial (vermelho) tem um pico dominante com flancos escalonados. O híbrido (roxo) fica entre eles.", CAP),
          PageBreak()]

# ---------------------------------------------------------------------------------------------------------- 3D e parâmetros
story += [Paragraph("6. Em perspectiva e o efeito dos parâmetros", H2),
          img("vista_3d.png", 176),
          Paragraph("Vista 3D (altura exagerada 3×). Repare no cone (A), liso, e na serra de G, com cume e esporões que se ramificam.", CAP),
          img("param_cristas.png", 172),
          Paragraph("Cristas: o expoente do ruído é o botão de 'rugosidade' do jogo. Baixo dá um maciço largo; alto, cristas finas e menos volume.", CAP),
          img("param_fluvial.png", 172),
          Paragraph("Erosão fluvial: o terreno sobe a cada passo e a drenagem amadurece. Com 10 passos há só ravinas nos flancos; com 40, uma rede completa.", CAP),
          PageBreak(),
          img("param_termica.png", 172),
          Paragraph("Erosão térmica: com 120 passadas as cristas ficam arredondadas e aparece uma saia suave na base.", CAP),
          img("param_gotas.png", 172),
          Paragraph("Erosão por gotas: mais gotas, mais entalhe nas encostas. Com poucas, quase nada muda.", CAP)]

# --------------------------------------------------------------------------------------------------- escala do jogo
story += [Paragraph("7. O que sobrevive à grade do jogo", H2),
          img("escala_do_jogo.png", 176),
          Paragraph("Em cima: o resultado na grade fina deste estudo (células de 1,5 km). Embaixo: o mesmo terreno reduzido a pixels de 9,8 km, como "
                    "no mapa de 4096 px do jogo (raio de 6.371 km). O cone, as cristas e o híbrido ficam parecidos; só a serra de G ainda se destaca.", CAP),
          Paragraph("<b>Consequência.</b> Num pixel de 9,8 km cabe uma serra com vales dentro. Por mais realista que seja o método, a grade "
                    "do jogo não mostra os vales finos. E como o mapa é latitude/longitude, a largura de cada célula encolhe com o cosseno da latitude "
                    "(a 60° são ~4,9 km, enquanto a altura continua 9,8 km): declive, área de captação e raio do pincel precisam ser calculados em "
                    "unidades físicas, não em pixels. Há três saídas para o detalhe:", P)]
story += bullets(["<b>Camada de detalhe:</b> o jogo guarda a altitude em 9,8 km e <i>soma</i> um detalhe procedural fino na hora de desenhar e "
                  "de consultar (ruído de cristas condicionado ao declive e à drenagem, calculados a partir da grade grossa). É a saída mais barata.",
                  "<b>Edição em malha fina local:</b> ao pintar, o pincel cria uma malha de 1–3 km só na região e guarda lá o detalhe. É mais fiel e "
                  "mais trabalhosa (exige blocos editáveis em níveis de detalhe).",
                  "<b>Aceitar a grade:</b> manter o que há, usando o método só para dar à serra altura, cume e posição certos."])
story += [Spacer(1, 4),
          Paragraph("<b>Falta decidir:</b> se o detalhe fino é só visual (enriquece a imagem, mas não prova melhora da drenagem nem da altitude usada pela "
                    "simulação) ou parte da altitude consultável (precisa ficar consistente entre níveis de zoom, consultas, rios, salvamento e reabertura). "
                    "A segunda opção é a mais útil e a mais cara.", P),
          PageBreak()]

# --- nova seção 8: mais cenários
story += [Paragraph("8. Mais terrenos, mais sementes, alturas equivalentes", H2),
          Paragraph("O ensaio original usava uma cordilheira em S sobre uma planície. Para saber se os métodos preservam a intenção do autor em outras "
                    "situações, repeti D, G e I em cinco terrenos-base (21 execuções, em paralelo). Os parâmetros são os mesmos do restante do estudo.", P),
          img("variedade_cenarios.png", 128),
          Paragraph("Cinco terrenos. O fundo de D é preservado em todos. G e I <b>mudam o terreno ao redor do traço</b>: em 'já montanhoso' e 'serras baixas', "
                    "G redesenha a drenagem do terreno inteiro; no planalto, I deixa <b>riscos radiais retos</b> na borda (artefato de roteamento em declive liso, "
                    "porque o híbrido não parte de ruído); na costa, ambos respeitam o mar.", CAP),
          img("variedade_sementes.png", 128),
          Paragraph("Três sementes. D e I variam com a semente; <b>G produz praticamente o mesmo resultado</b>: a forma vem do traço, e a semente só mexe nos detalhes. "
                    "Isso dá a G previsibilidade e controle, mas pouca variedade.", CAP),
          img("altura_equivalente.png", 174),
          Paragraph("Altura equivalente: o relevo acima da base foi reescalado para o mesmo pico (3.500 m) em cada método. G continua com cume contínuo e esporões "
                    f"ramificados (declive médio {V['altura_equivalente']['G']['declive_medio_graus']:.1f}° contra {V['altura_equivalente']['D']['declive_medio_graus']:.1f}° em D "
                    f"e {V['altura_equivalente']['I']['declive_medio_graus']:.1f}° em I), então a diferença de organização não vem só de G ser mais alto.", CAP),
          Paragraph("<b>O que isso muda.</b> G e I precisam de uma máscara que <i>limite</i> o reajuste ao redor do traço, e I precisa de ruído inicial leve para não "
                    "criar riscos em declives lisos. Ainda assim, o conjunto de cenários continua pequeno (um traço, um tamanho de região): não prova que G seja "
                    "melhor em geral.", P),
          PageBreak()]

# -------------------------------------------------------------------------------------------------- recomendação
story += [Paragraph("9. Conectar a edição ao mundo e recomendação", H2),
          Paragraph("O principal ponto em aberto não é o método, é a <b>integração hidrológica</b>. A equação de erosão usa a área de captação a montante, "
                    "e essa área pode começar muito além dos limites da pincelada. Alterar um divisor de águas também pode mudar o escoamento fora do trecho editado.", P),
          Paragraph("O que o processamento local precisa resolver", H3)]
story += bullets(["<b>Entradas de água:</b> considerar a contribuição do terreno externo para os canais dentro da região processada (hoje, o estudo e o "
                  "pincel Vales só enxergam a água da própria região).",
                  "<b>Saídas e continuidade:</b> conectar o novo relevo ao terreno e aos rios vizinhos, sem degraus nem interrupções artificiais.",
                  "<b>Área afetada:</b> saber quando é preciso recalcular uma bacia maior; uma margem fixa ao redor do pincel pode ser insuficiente.",
                  "<b>Depressões intencionais:</b> preservar lagos e bacias endorreicas definidos pelo autor, distinguindo-os de poços numéricos.",
                  "<b>Camadas dependentes:</b> clima, biomas e rios do Gleba continuam do mapa original; é preciso um fluxo de revisão quando o relevo "
                  "sofre alteração relevante (detalhes pequenos não exigem a mesma revisão de uma cordilheira nova)."])
story += [Paragraph("Duas ferramentas, não uma", H3),
          Paragraph("Manter o pincel manual de <b>Vales</b> e acrescentar a erosão como <b>operação ajustável</b>: esculpir uma passagem específica e deixar a "
                    "drenagem reorganizar uma encosta atendem a intenções diferentes do autor.", P),
          Paragraph("Sequência recomendada", H3),
          table([["Etapa", "Entrega verificável"],
                 ["1. Escala e unidades", "Confirmar a projeção e a escala vertical; calcular distâncias, declives e áreas de captação em unidades físicas "
                                          "(o mapa é latitude/longitude: a largura da célula varia com a latitude)."],
                 ["2. Protótipo híbrido", "Prévia rápida de cristas deslocadas; erosão ajustável depois do traço, com opção de desfazer."],
                 ["3. Drenagem integrada", "Testar entradas e saídas, conexões nas bordas, divisores de águas e depressões intencionais."],
                 ["4. Medição no editor", "Pinceladas pequenas, médias e grandes: tempo total (incluindo atualizar a visualização, registrar a alteração e manter "
                                          "a interface responsiva), variação entre execuções e memória."],
                 ["5. Detalhe e camadas", "Definir a altitude consultável e o fluxo de revisão de rios, clima e biomas antes de expandir o sistema."]],
                [40 * mm, 134 * mm]),
          Paragraph("Critérios para aceitar o protótipo", H3)]
story += bullets(["Mantém as conexões hidrológicas nas bordas e respeita áreas protegidas pelo autor.",
                  "Permite desfazer e sobrevive ao salvamento e à reabertura.",
                  "A mesma semente e os mesmos parâmetros reproduzem o resultado.",
                  "A comparação visual acontece <b>na escala usada no editor</b>, com alturas equivalentes e mais de um tipo de terreno."])
story += [Paragraph("Recomendação", H3),
          Paragraph("<b>G permanece uma boa referência</b> e um candidato a modo próprio de soerguimento. A escolha entre G e I deve considerar a qualidade "
                    "observada, o controle do autor e o <b>custo medido no programa</b>, não o tempo de Python deste estudo. Hoje o híbrido (I) é o candidato "
                    "mais promissor para o pincel 'Montanhas', mas depende dos pontos acima.", P),
          Paragraph("Sobre o tempo: reduzir o número de células não reduz o tempo na mesma proporção em GDScript ou C#, e a operação completa inclui "
                    "atualizar a visualização, registrar o comando e manter a interface responsiva. A documentação do Godot recomenda orientar a otimização por "
                    "medições. Nenhum tempo neste documento foi medido no editor.", P),
          Paragraph("Riscos e perguntas em aberto", H3)]
story += bullets(["<b>Calibração:</b> o equilíbrio entre soerguimento (U), erodibilidade (K) e difusão decide o aspecto; os parâmetros deste estudo foram "
                  "ajustados à vista e podem não ser os melhores.",
                  "<b>Realismo é subjetivo:</b> não há métrica aceita aqui; a decisão deve sair de o autor comparar imagens como as deste documento.",
                  "<b>Carimbos:</b> o potencial de carimbos feitos com relevo medido e detalhado não foi avaliado."])
story += [Paragraph("Fontes", H2),
          Paragraph("Consultei as páginas e os resumos abaixo (não li todos os artigos por inteiro). Os métodos A–I foram implementados por mim para "
                    "este estudo, em docs/pesquisa-pinceis/metodos.py, e os parâmetros foram escolhidos por tentativa.", SM)]
refs = [
    ("Musgrave, Kolb, Mace (1989). The synthesis and rendering of eroded fractal terrains. SIGGRAPH.", "https://history.siggraph.org/?p=119354"),
    ("Quilez. Domain warping.", "https://iquilezles.org/articles/warp"),
    ("Cordonnier et al. (2016). Large scale terrain generation from tectonic uplift and fluvial erosion. Computer Graphics Forum.", "https://diglib7.eg.org/handle/10.1111/cgf12820"),
    ("Schott et al. (2023). Large-scale terrain authoring through interactive erosion simulation. ACM TOG.", "https://dl.acm.org/doi/10.1145/3592787"),
    ("Tzathas et al. (2024). Physically-based analytical erosion for fast terrain generation.", "http://www-sop.inria.fr/reves/Basilic/2024/TGSC24/Analytical_Terrains_EG.pdf"),
    ("Génevaux et al. (2013). Terrain generation using procedural models based on hydrology. ACM TOG.", "https://www.cs.purdue.edu/homes/bbenes/papers/Genevaux13ToG.pdf"),
    ("Guérin et al. (2017). Interactive example-based terrain authoring with conditional GANs. SIGGRAPH Asia.", "https://www.researchgate.net/publication/320345887_Interactive_Example-Based_Terrain_Authoring_with_Conditional_Generative_Adversarial_Networks"),
    ("Erosão hidráulica por partículas (linhagem de Beyer 2015), descrição de implementação.", "https://itvanderveen.nl/Projects/HydraulicErosionSimulation.html"),
    ("PTRM: Perceived Terrain Realism Metrics.", "https://arxiv.org/pdf/1909.04610"),
    ("Godot Engine. General optimization tips (medir antes de otimizar).", "https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html"),
    ("Parecer técnico 'Avaliação dos pincéis de terreno realistas' (18/11/2026), que motivou esta revisão.", "D:/downloads/Avaliacao_Tecnica_Pinceis_Terreno_Evron.pdf"),
]
for text, url in refs:
    story.append(Paragraph(f"• {text}<br/><font color='#1F6FB2' size='7.5'>{url}</font>", SM))


def footer(c, d):
    c.saveState(); c.setFont("Arial", 7.5); c.setFillColor(GRAY)
    c.drawString(18 * mm, 9 * mm, "Evron RPG · Pincéis de terreno realistas")
    c.drawRightString(192 * mm, 9 * mm, str(d.page)); c.restoreState()


out = os.path.join(HERE, "Pinceis_de_Terreno_Realistas.pdf")
SimpleDocTemplate(out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=16 * mm, bottomMargin=16 * mm,
                  title="Pincéis de terreno realistas", author="Projeto Evron RPG").build(story, onFirstPage=footer, onLaterPages=footer)
print("ok", out)
