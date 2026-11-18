"""Gera Calibracao_Mapas_Evron.pdf a partir de calibracao_evron.json. Uso: python gerar_pdf.py <pasta_calibracao>"""
import sys, os, json, io
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import colormaps
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, PageBreak, KeepTogether)

OUT = sys.argv[1]
cal = json.load(open(os.path.join(OUT, "calibracao_evron.json"), encoding="utf-8"))
L = cal["camadas"]

F = "C:/Windows/Fonts/"
pdfmetrics.registerFont(TTFont("Arial", F + "arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-B", F + "arialbd.ttf"))
pdfmetrics.registerFont(TTFont("Arial-I", F + "ariali.ttf"))
from reportlab.lib.fonts import addMapping
addMapping("Arial", 0, 0, "Arial"); addMapping("Arial", 1, 0, "Arial-B"); addMapping("Arial", 0, 1, "Arial-I")

NAVY = colors.HexColor("#1F3A5F"); GRAY = colors.HexColor("#5A6270"); LINE = colors.HexColor("#D5DAE1"); ZEBRA = colors.HexColor("#F3F5F8")
st = lambda name, **k: ParagraphStyle(name, **{"fontName": "Arial", "fontSize": 9.5, "leading": 13, "textColor": colors.HexColor("#1B1F24"), **k})
H1 = st("h1", fontSize=20, leading=24, spaceAfter=4, textColor=NAVY)
H2 = st("h2", fontSize=13.5, leading=17, spaceBefore=12, spaceAfter=5, textColor=NAVY)
P = st("p", spaceAfter=5)
SM = st("sm", fontSize=8.2, leading=10.5)
SMB = st("smb", fontSize=8.2, leading=10.5, textColor=colors.white)
META = st("meta", fontSize=9, textColor=GRAY, spaceAfter=10)
CONF = {"alta": colors.HexColor("#2E7D4F"), "média": colors.HexColor("#B7791F"), "baixa": colors.HexColor("#C0392B"),
        "hipótese": colors.HexColor("#7B3FA0"), "medido": colors.HexColor("#1F6FB2"), "definido": NAVY, "relativo": GRAY,
        "guia": colors.HexColor("#2A7F86")}

def table(rows, widths, header=True, extra=()):
    data = [[c if not isinstance(c, str) else Paragraph(c, SMB if (header and i == 0) else SM) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    style = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
             ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
    if header: style += [("BACKGROUND", (0, 0), (-1, 0), NAVY)]
    style += [("BACKGROUND", (0, i), (-1, i), ZEBRA) for i in range(2 if header else 1, len(rows), 2)]
    t.setStyle(TableStyle(style + list(extra))); return t

def badge(c):
    return f'<font color="{CONF[c].hexval().replace("0x", "#")}"><b>{c}</b></font>'

def fig_to_img(fig, width_mm):
    buf = io.BytesIO(); fig.savefig(buf, format="png", dpi=200, bbox_inches="tight"); plt.close(fig); buf.seek(0)
    w, h = fig.get_size_inches(); img = Image(buf, width=width_mm * mm, height=width_mm * mm * h / w); return img

def legend_bars():
    specs = [("Temperatura mensal (°C)", "magma", lambda t: -20 + 60 * t, [-20, -10, 0, 10, 20, 30, 40], None),
             ("Chuva (mm por mês)", "viridis", lambda t: 20 + 298 * t, [20, 50, 100, 150, 200, 250, 300], "escuro: 0–20 mm"),
             ("Umidade (%) — baixa confiança", "viridis", lambda t: 100 * t, [0, 25, 50, 75, 100], None),
             ("Profundidade do aquífero (m)", "viridis", lambda t: 1500 * t, [0, 250, 500, 750, 1000, 1250, 1500], None),
             ("Espessura do aquífero (m)", "viridis", lambda t: 100 * t, [0, 25, 50, 75, 100], None)]
    fig, axes = plt.subplots(len(specs), 1, figsize=(7.2, 0.62 * len(specs) + 0.3))
    for ax, (title, cm, f, ticks, note) in zip(axes, specs):
        grad = np.linspace(0, 1, 512)[None]
        if note:  # dark fade below the ramp start
            ext = np.linspace(0, 1, 60)[None, :, None] * np.array(colormaps[cm](0.0)[:3])[None, None]
            img = np.concatenate([ext, colormaps[cm](grad)[..., :3]], axis=1)
            ax.imshow(img, aspect="auto", extent=(-60 / 512, 1, 0, 1))
            ax.text(-30 / 512, -0.55, "0", ha="center", va="top", fontsize=7)
        else:
            ax.imshow(grad, aspect="auto", cmap=cm, extent=(0, 1, 0, 1))
        inv = {"Temperatura mensal (°C)": lambda v: (v + 20) / 60, "Chuva (mm por mês)": lambda v: (v - 20) / 298}
        tpos = [inv.get(title, lambda v, f=f: v / f(1))(v) for v in ticks]
        ax.set_xticks(tpos); ax.set_xticklabels([str(v) for v in ticks], fontsize=7); ax.set_yticks([])
        ax.set_title(title, fontsize=8, loc="left", pad=2)
        for s in ax.spines.values(): s.set_visible(False)
        ax.tick_params(length=2, pad=1)
    fig.tight_layout(h_pad=0.6); return fig_to_img(fig, 165)

def temp_chart():
    pts = [(0.6276, 18, "tropical (A)\nmês frio ≥ 18", (12, -22)), (0.5044, 10, "polar (E)\nmês quente < 10", (10, -20)),
           (0.6979, 22, "verão quente (a)\nmês quente ≥ 22", (-92, 6)), (0.3245, 0, "C × D\nmês frio > 0", (-62, 4)),
           (0.3324, 0, "ET × EF\nmês quente ≥ 0", (10, -20))]
    fig, ax = plt.subplots(figsize=(6.4, 3.0))
    x = np.linspace(0, 1, 50); ax.plot(x, -20 + 60 * x, color="#1F3A5F", lw=1.6, label="T = −20 + 60·t")
    for t, T, lab, off in pts:
        ax.scatter([t], [T], color="#C0392B", zorder=3, s=22)
        ax.annotate(lab, (t, T), xytext=off, textcoords="offset points", fontsize=6.5, color="#333")
    ax.set_xlabel("posição na escala de cores magma (t)", fontsize=8); ax.set_ylabel("temperatura (°C)", fontsize=8)
    ax.tick_params(labelsize=7); ax.grid(alpha=.25); ax.legend(fontsize=7, loc="upper left"); ax.set_xlim(0, 1); ax.set_ylim(-22, 42)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
    return fig_to_img(fig, 150)

def swatch_table(classes, cols, widths, desc):
    rows = [cols]; extra = []
    for i, (rgb, val) in enumerate(classes.items(), start=1):
        r, g, b = map(int, rgb.split(","))
        rows.append(["", f"{r}, {g}, {b}"] + desc(val))
        extra.append(("BACKGROUND", (0, i), (0, i), colors.Color(r / 255, g / 255, b / 255)))
    t = table(rows, widths, extra=extra)
    # keep the swatch column free of zebra striping
    t.setStyle(TableStyle(extra + [("BOX", (0, i), (0, i), 0.4, colors.HexColor("#999999")) for i in range(1, len(rows))]))
    return t

story = []
story += [Paragraph("Calibração dos mapas de Evron", H1),
          Paragraph(f"Projeto Evron RPG · versão {cal['versao']} · {cal['data'].split('-')[2]}/{cal['data'].split('-')[1]}/{cal['data'].split('-')[0]} · fonte: mapas.zip (Gleba 0.3.5), guia de legendas e valores do autor", META),
          Paragraph("Este documento registra como cada mapa exportado pelo Gleba é convertido em valores físicos para o gerenciador de Evron. "
                    "O Gleba não publica legendas numéricas; por isso, parte dos valores foi <b>calibrada pelas próprias regras físicas do modelo</b> "
                    "(limiares de Köppen e de biomas) e conferida pixel a pixel. Cada item indica seu grau de confiança.", P),
          table([["Grau", "Significado"],
                 [badge("definido"), "Informado pelo autor do mundo."],
                 [badge("medido"), "Verificado diretamente nos pixels dos arquivos."],
                 [badge("guia"), "Documentado no guia de legendas do Gleba, sem conferência numérica."],
                 [badge("alta"), "Estimado por regras físicas, com várias verificações independentes concordando."],
                 [badge("média"), "Estimado com bom ajuste, mas com faixa plausível ainda larga."],
                 [badge("baixa"), "Suposição razoável sem regra física para conferir."],
                 [badge("relativo"), "Só a ordem dos valores (0 a 1) é conhecida; falta a unidade."],
                 [badge("hipótese"), "Nome provável de uma categoria; precisa de confirmação."]], [28 * mm, 142 * mm])]

story += [Paragraph("1. Planeta e coordenadas", H2),
          table([["Medida", "Valor", "Grau"],
                 ["Forma", "Esfera", badge("definido")],
                 ["Raio", "8.282,3 km", badge("definido")],
                 ["Circunferência", "≈ 52.039 km", badge("definido")],
                 ["Superfície", "≈ 862 milhões de km²", badge("definido")],
                 ["Calendário", "Gregoriano (igual ao da Terra)", badge("definido")],
                 ["Projeção dos mapas", "Equiretangular: 4096 × 2048 px cobrem 360° × 180°", badge("medido")],
                 ["Pixel no equador", "≈ 12,7 km (mapas de 4096 px) · ≈ 3,2 km (relevo de 16384 px)", badge("medido")],
                 ["1° de latitude", "≈ 144,6 km; na horizontal o pixel encolhe com o cosseno da latitude", badge("medido")]],
                [38 * mm, 108 * mm, 24 * mm])]

story += [Paragraph("2. Elevação", H2),
          Paragraph("O mapa <b>Elevation GrayScale.png</b> (16 bits) tem o nível do mar exatamente no valor 32767: nenhum pixel de terra fica abaixo dele. "
                    "Os extremos informados pelo autor exigem escalas separadas para terra e mar.", P),
          table([["Faixa do pixel (p)", "Fórmula", "Metros por unidade"],
                 ["p ≥ 32767 (terra)", "h = (p − 32767) × 9.103,40 / 17.336", "≈ 0,525 m"],
                 ["p < 32767 (mar)", "h = (p − 32767) × 13.500 / 32.767", "≈ 0,412 m"]], [40 * mm, 90 * mm, 40 * mm]),
          Spacer(1, 4),
          Paragraph("Exemplos: p = 50.103 → +9.103,40 m · p = 40.000 → ≈ +3.798 m · p = 32.767 → 0 m · p = 20.000 → ≈ −5.260 m · p = 0 → −13.500 m. "
                    "Os mapas <i>Land</i> e <i>Bathy</i> são apenas as duas metades do mapa combinado esticadas (≈ 2·(p − 32767) e ≈ 2·p) e não trazem informação nova. "
                    "Os 29.173 pixels de água acima do nível do mar são lagos interiores, não erros.", P)]

story += [PageBreak(), Paragraph("3. Legendas reconstruídas", H2),
          Paragraph("Os mapas contínuos usam escalas de cores padrão: <b>magma</b> para temperatura e <b>viridis</b> para os demais "
                    "(diferença mediana de 1 a 2 tons em 0–255). A posição de cada cor na escala (t, de 0 a 1) é convertida em valor pelas fórmulas abaixo.", P),
          legend_bars()]

story += [Paragraph("4. Temperatura — de −20 a +40 °C · " + badge("alta"), H2),
          Paragraph("O mapa de clima usa a classificação de Köppen, cujas fronteiras são temperaturas conhecidas. Para cada fronteira procurei a posição t "
                    "que melhor separa as classes vizinhas no <b>Clima.png</b>. As cinco fronteiras caem sobre a mesma reta, com erro máximo de 0,5 °C:", P),
          temp_chart(),
          table([["Fronteira de Köppen", "Temperatura", "t encontrado", "Acerto", "Pela fórmula"],
                 ["Tropical (A) × temperado/frio", "mês frio 18 °C", "0,628", "99,5%", "17,7 °C"],
                 ["Polar (E) × demais", "mês quente 10 °C", "0,504", "99,4%", "10,3 °C"],
                 ["Verão quente (a) × ameno (b)", "mês quente 22 °C", "0,698", "97,3%", "21,9 °C"],
                 ["Temperado (C) × frio (D)", "mês frio 0 °C", "0,325", "99,1%", "−0,5 °C"],
                 ["Tundra (ET) × gelo (EF)", "mês quente 0 °C", "0,332", "99,6%", "−0,1 °C"]],
                [52 * mm, 32 * mm, 26 * mm, 22 * mm, 30 * mm]),
          Spacer(1, 4),
          Paragraph("<b>Fórmula: T = −20 + 60·t</b> (°C, média do mês). A escala satura no início: t = 0 significa −20 °C <i>ou menos</i> "
                    "(7,9% da terra em janeiro, 4,4% em julho). A média mensal mais alta de Evron fica em ≈ 31 °C.", P)]

story += [KeepTogether([Paragraph("5. Chuva — de ≈ 20 a ≈ 320 mm por mês · " + badge("média"), H2),
          Paragraph("<b>Average Rainfall é a média mensal, não o total anual</b> (o inspetor do Gleba mostra mm por mês). "
                    "Abaixo do início da escala viridis há uma faixa roxo-escura que desce até o preto, usada pelos lugares mais secos.", P),
          Paragraph("Com a temperatura já calibrada, testei escalas lineares, logarítmicas e de potência contra cinco regras de Köppen que dependem da chuva. "
                    "A melhor foi linear:", P),
          table([["Regra de Köppen", "O que testa", "Acerto"],
                 ["Árido (B) × úmido", "chuva anual < 20·Tmédia + 140 a 280", "96,6%"],
                 ["Deserto (BW) × estepe (BS)", "metade do limiar anterior", "90,8%"],
                 ["Floresta tropical (Af)", "mês mais seco ≥ 60 mm", "99,6%"],
                 ["Monção (Am) × savana (Aw)", "mês seco ≥ 100 − anual/25", "96,7%"],
                 ["Verão seco (s) / inverno seco (w)", "razões entre estações", "93,0%"]], [52 * mm, 88 * mm, 30 * mm]),
          Spacer(1, 4),
          Paragraph("<b>Fórmula:</b> t ≥ 0 → <b>P = 20 + 298·t</b> mm/mês · faixa escura → P = 20·(1 + t), indo de 20 mm até 0 no preto. "
                    "Ajustes quase tão bons ficam entre 20 e 30 mm no início e entre 250 e 330 mm no topo; por isso a confiança é média. "
                    "Escala logarítmica: 93,2% · potências: até 92%.", P)])]

def conf_of(v):
    """the confidence keyword that appears first in the text wins"""
    c = v.get("confianca", "")
    hits = [(c.find(k), k) for k in ("hipótese", "hipotese", "baixa", "média", "alta", "relativo", "medido", "definido", "guia") if k in c]
    return {"hipotese": "hipótese"}.get(min(hits)[1], min(hits)[1]) if hits else "relativo"

TIPO = {"continuo": "contínuo", "referencia": "referência", "categorico": "categórico", "composicao_rgb": "composição RGB"}
SECAO = {"Clima.png": "ver seção 7", "Provincias geologicas.png": "ver seção 8", "Vulcanismo.png": "ver seção 9"}
pretty = lambda s: s.replace(">=", "≥").replace("*", "·").replace("-20 ", "−20 ")

story += [PageBreak(), Paragraph("6. Todos os mapas", H2)]
rows = [["Arquivo", "Tipo e unidade", "Conversão", "Grau"]]
for name, v in L.items():
    unit = v.get("unidade", ""); kind = TIPO.get(v.get("tipo", ""), v.get("tipo", ""))
    conv = SECAO.get(name) or v.get("formula") or v.get("relacao") or v.get("uso") or v.get("legenda") or \
        (", ".join(f"{k} = {x}" for k, x in v["canais"].items()) if "canais" in v else
         " · ".join(f"{x} = RGB {k}" for k, x in v.get("classes", {}).items()))
    rows.append([name.replace(".png", ""), f"{kind}{' · ' + unit if unit else ''}", pretty(conv), badge(conf_of(v))])
story.append(table(rows, [42 * mm, 38 * mm, 68 * mm, 22 * mm]))
story += [Spacer(1, 4), Paragraph("<b>Declividade:</b> a calculada a partir da elevação oficial e do raio de Evron concorda só em parte com o mapa do Gleba (correlação 0,61). "
                                  "O gerenciador deve usar a própria. No mapa de 4096 px, a mediana em terra é 0,08°, o p90 é 1,3° e o p99 é 5,7°: o pixel de 12,7 km achata as encostas. "
                                  "<b>Inacessibilidade:</b> a escala é contínua; recalcular a distância ao oceano sobre a esfera de Evron.", P)]

k = L["Clima.png"]
story += [PageBreak(), Paragraph("7. Clima de Köppen · " + badge("alta"), H2),
          Paragraph("As 24 cores do <b>Clima.png</b> correspondem à paleta padrão de Köppen-Geiger de Beck et al. (2018). "
                    "Validação: a taiga do Gleba exige ET, Dfc, Dwc ou Dsc e aparece 100% em ET e Dfc; a vegetação mediterrânea exige Cs e aparece 100% em Csa e Csb. "
                    "Cfb e Cfc têm cor um pouco diferente da paleta padrão.", P)]
KN = {"Af": "Equatorial úmido", "Am": "Monção", "Aw": "Savana (inverno seco)", "BWh": "Deserto quente", "BWk": "Deserto frio",
      "BSh": "Estepe quente", "BSk": "Estepe fria", "Csa": "Mediterrâneo, verão quente", "Csb": "Mediterrâneo, verão ameno",
      "Csc": "Mediterrâneo, verão frio", "Cwa": "Subtropical, inverno seco, verão quente", "Cwb": "Altitude, inverno seco, verão ameno",
      "Cwc": "Altitude, inverno seco, verão frio", "Cfa": "Subtropical úmido", "Cfb": "Oceânico", "Cfc": "Subpolar oceânico",
      "Dsb": "Continental, verão seco e ameno", "Dsc": "Subártico, verão seco", "Dwc": "Subártico, inverno seco",
      "Dfa": "Continental úmido, verão quente", "Dfb": "Continental úmido, verão ameno", "Dfc": "Subártico", "ET": "Tundra", "EF": "Calota de gelo", "água": "Água"}
story.append(swatch_table(k["classes"], ["Cor", "RGB", "Código", "Clima"], [12 * mm, 30 * mm, 20 * mm, 108 * mm],
                          lambda v: [v, KN.get(v, "")]))

for title, key in (("8. Províncias geológicas", "Provincias geologicas.png"), ("9. Vulcanismo", "Vulcanismo.png")):
    v = L[key]
    block = [Paragraph(f"{title} · " + badge("hipótese"), H2)]
    if "observacao" in v: block.append(Paragraph(v["observacao"][0].upper() + v["observacao"][1:] + ".", P))
    block.append(swatch_table(v["classes"], ["Cor", "RGB", "Nome provável", "Evidência"], [12 * mm, 26 * mm, 70 * mm, 62 * mm],
                              lambda c: [c["nome"], c.get("evidencia", "")]))
    story.append(KeepTogether(block))

story += [Paragraph("10. Pendências e limites", H2),
          table([["Item", "Situação"],
                 ["Texto de Fāhīmium", "Necessário para posicionar cidades, povo, religião e instituições de teste."],
                 ["Região de teste", "A definir pelo autor."],
                 ["Data atual da campanha e contagem dos anos", "Ano zero e eras ainda não definidos."],
                 ["Profundidade e permeabilidade do solo, fluxo d'água", "Só valores relativos; dois pontos lidos no inspetor (F1) do Gleba calibrariam cada mapa."],
                 ["Umidade e riqueza do solo", "Assumido 0–100%; sem regra física para conferir."],
                 ["Províncias e vulcanismo", "Nomes são hipóteses baseadas em rochas, altitude e limites de placas."],
                 ["Meses extremos", "O Gleba exportou só janeiro e julho; as regras de Köppen foram aplicadas supondo que sejam os meses extremos."]],
                [62 * mm, 108 * mm]),
          Spacer(1, 6),
          Paragraph("Reprodução: os scripts em <i>calibracao/scripts</i> refazem todas as medições a partir de mapas.zip. "
                    "Os valores completos estão em <i>calibracao_evron.json</i>.", SM)]

def footer(c, d):
    c.saveState(); c.setFont("Arial", 7.5); c.setFillColor(GRAY)
    c.drawString(20 * mm, 10 * mm, "Evron RPG · Calibração dos mapas")
    c.drawRightString(190 * mm, 10 * mm, str(d.page)); c.restoreState()

pdf = os.path.join(OUT, "Calibracao_Mapas_Evron.pdf")
SimpleDocTemplate(pdf, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=18 * mm, bottomMargin=18 * mm,
                  title="Calibração dos mapas de Evron", author="Projeto Evron RPG").build(story, onFirstPage=footer, onLaterPages=footer)
print("ok", pdf)
