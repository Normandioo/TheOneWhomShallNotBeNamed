"""Protótipo do mapa político com relevo (estilo de mapa de jogo de estratégia), feito só dos dados de Evron.

O que vem dos dados, na posição exata da grade de 4096x2048 (9,77 km por pixel):
  - costa: a Landmask do Gleba, como campo de distância com sinal reamostrado (a linha passa entre os centros dos
    pixels de terra e de água; ilhas de 1 pixel e canais ficam); suavizada e com ruído, mas presa a 0,8 px do dado
    (um assert confere em cada vista);
  - relevo: a altitude calibrada (height_4096x2048.f32), sombreada; o detalhe abaixo de 10 km é ruído fractal com
    amplitude proporcional ao relevo local (não move morro nenhum, só dá textura onde já há montanha);
  - mar e lagos: profundidade da mesma altitude; lagos da Waterbodies;
  - rios: a rede vetorial de tools/build_rivers.py (Waterflow do Gleba), com largura pelo fluxo.
O que é INVENTADO (não há países no banco ainda), mas derivado dos dados:
  - países: sementes onde o lugar é habitável (temperatura, chuva, solo, declividade, água por perto) e cada pixel
    vai para a capital mais "barata" de alcançar: subir serra, atravessar rio grande ou mar custa caro, então as
    fronteiras caem em cristas, rios e estreitos, como as de verdade. Depois, na resolução da tela, a fronteira
    ainda se acomoda nas cristas e nos rios desenhados (watershed numa faixa de ~1 pixel do dado);
  - povoados, cidades e estradas pela mesma habitabilidade; estradas pelo caminho de menor custo;
  - nomes.

Saída: data/evron/politico/<vista>.png (+ mundo.npz, o cache da etapa global, e mundo.png, a visão geral).
Uso: python tools/mapa_politico.py [vista ...]    (sem argumento: todas as vistas de VIEWS)
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage
from skimage.graph import MCP_Geometric
from skimage.segmentation import watershed

import build_natural as bn
import build_rivers as br

H, W = 2048, 4096
R_KM = 6371.0
KM_PX = math.pi * R_KM / H                 # 9,77 km por pixel na direção norte-sul
OUT = os.path.join(bn.D, "politico")
LAT = 90 - (np.arange(H) + 0.5) * 180 / H
LON = (np.arange(W) + 0.5) * 360 / W - 180
FONT = "C:/Windows/Fonts/bahnschrift.ttf"   # condensada e geométrica como a da referência; vem com o Windows 10/11

# Paleta tirada das imagens de referência (mediana de recortes planos) e completada no mesmo tom: cores médias,
# pouco saturadas, para o sombreado ler bem por cima. (cor, texto escuro?)
PALETTE = [("#af6a4a", 0), ("#a59c5e", 1), ("#866068", 1), ("#9a7b72", 0), ("#5a7387", 0), ("#8e5438", 0),
           ("#9a8058", 0), ("#6e6283", 0), ("#7d8a5a", 1), ("#b08c5f", 1), ("#5e7d78", 0), ("#9b4f4a", 0),
           ("#8a7aa0", 1), ("#a3735a", 0)]
UNCLAIMED = "#a08a62"
FORMAL = ["República de {}", "Reino de {}", "Estado {a}", "República Sagrada de {}", "Federação {a}", "Grão-Ducado de {}",
          "Comunidade {a}", "União Popular de {}", "Principado de {}", "Confederação {a}"]


def rgb(hexs):
    return np.array([int(hexs[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


def unit(lat, lon):
    """Graus -> direção (convenção do projeto: (cos lat sin lon, sin lat, cos lat cos lon))."""
    la, lo = np.radians(lat), np.radians(lon)
    return np.stack([np.cos(la) * np.sin(lo), np.sin(la), np.cos(la) * np.cos(lo)], -1)


def slope_deg(h):
    """Declividade em graus na grade de 4K (o mar conta como 0 m; a longitude dá a volta)."""
    h = np.maximum(h, 0)
    dx = np.maximum(np.cos(np.radians(LAT)), 0.05)[:, None] * KM_PX * 2e3
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / dx
    p = np.pad(h, ((1, 1), (0, 0)), mode="edge")
    gy = (p[2:] - p[:-2]) / (KM_PX * 2e3)
    return np.degrees(np.arctan(np.hypot(gx, gy)))


# ---------------------------------------------------------------- nomes
ONSET = ["", "b", "d", "dr", "g", "k", "kr", "l", "m", "n", "p", "pl", "q", "r", "s", "sh", "t", "tr", "v", "z", "zv",
         "x", "c", "f", "h", "j", "st", "sk"]
NUCLEUS = ["a", "e", "i", "o", "u", "oa", "ia", "ua", "ei", "ou"]
CODA = ["", "", "", "n", "r", "k", "s", "x", "l", "m"]


def make_name(rng, used):
    while True:
        n = "".join(rng.choice(ONSET) + rng.choice(NUCLEUS) + rng.choice(CODA) for _ in range(rng.choice([1, 2, 2, 2, 3])))
        if 3 <= len(n) <= 9 and n not in used:
            used.add(n)
            return n.capitalize()


def formal_name(rng, n):
    f = FORMAL[rng.integers(len(FORMAL))]
    adj = (n[:-1] if n[-1] in "aeiou" else n) + rng.choice(["ano", "ense", "iano"])
    return f.format(n, a=adj)


# ---------------------------------------------------------------- etapa global (grade de 4K), com cache
def world():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "mundo.npz")
    if os.path.exists(path):
        return dict(np.load(path, allow_pickle=True))
    rng = np.random.default_rng(2026)
    h = np.fromfile(os.path.join(bn.D, "height_4096x2048.f32"), "<f4").reshape(H, W)
    land = bn.load("Landmask.png")[..., 0] == 80
    lake = ~land & ~bn.is_color(bn.load("Waterbodies.png"), (30, 30, 30))
    ice = bn.is_color(bn.load("Clima.png"), (104, 104, 104)) | bn.is_color(bn.load("BiomasGleba.png"), (236, 236, 236))
    tm = sum(np.fromfile(os.path.join(bn.D, f"temperature_{m}_4096x2048.f32"), "<f4").reshape(H, W) for m in ("jan", "jul")) / 2
    rain = 20 + 298 * bn.ramp_t(bn.load("Average Rainfall.png"), bn.VIRIDIS)
    soil = bn.ramp_t(bn.load("Soil Richness.png"), bn.VIRIDIS)
    flow = bn.ramp_t(bn.load("Waterflow.png"), bn.VIRIDIS)
    slope = slope_deg(h)

    # Habitabilidade 0..1: onde a gente se assenta. Frio, calor, seca, serra e altitude esvaziam; água doce e costa atraem.
    near_river = np.clip(bn.blur((flow > 0.75) & land, 2) * 4, 0, 1)
    near_coast = np.clip(bn.blur(~land, 2) * 4, 0, 1)
    hab = (np.clip((tm + 3) / 15, 0, 1) * np.clip((34 - tm) / 10, 0, 1) * np.clip((rain - 18) / 50, 0, 1)
           * np.clip(1 - slope / 5, 0.15, 1) * np.clip(1 - (h - 2200) / 2500, 0.1, 1) * (0.6 + 0.4 * soil)
           * (1 + 0.8 * near_river + 0.5 * near_coast))
    hab = np.where(land & ~ice, hab, 0)
    hab = np.clip(hab / np.percentile(hab[hab > 0], 99), 0, 1).astype(np.float32)

    # Capitais: amostragem de disco de Poisson na esfera, espaçamento menor onde o lugar é bom (450 a 900 km).
    ys, xs = np.nonzero(hab > 0.15)
    pick = rng.choice(len(ys), 40000, p=hab[ys, xs] / hab[ys, xs].sum())
    pick = pick[np.argsort(-hab[ys[pick], xs[pick]] * rng.uniform(0.6, 1, len(pick)))]
    seeds, vecs = [], np.zeros((0, 3))
    for k in pick:
        y, x = ys[k], xs[k]
        v = unit(LAT[y], LON[x])
        r = (900 - 450 * hab[y, x]) / R_KM
        if len(vecs) == 0 or np.arccos(np.clip(vecs @ v, -1, 1)).min() > r:
            seeds.append((y, x))
            vecs = np.vstack([vecs, v])
    seeds = np.array(seeds)
    weight = np.clip(rng.lognormal(0, 0.22, len(seeds)), 0.7, 1.6)  # países de tamanhos diferentes

    # Atrito por km: serra, altitude, rio grande e água custam; a fronteira cai onde os dois lados chegam com o mesmo custo.
    # O ruído (manchas de 20 a 120 km) faz o papel da história: sem ele, na planície a fronteira sai reta como um Voronoi.
    noise = sum(ndimage.gaussian_filter(rng.standard_normal((H, W)), sg, mode="wrap") * sg for sg in (2, 5, 12))
    fr = (1 + 0.6 * slope + 1.2 * np.clip((h - 1500) / 1000, 0, 4)) * np.exp(0.5 * noise / noise.std())
    fr += np.where(flow > 0.7, 3 + 25 * (flow - 0.7), 0)
    fr = np.where(land, fr, np.where(lake, 8.0, np.where(h > -400, 10.0, 60.0))) + 4 * ice
    best = np.full((H, W), np.inf, np.float32)
    lab = np.zeros((H, W), np.int16)
    ry = int(1400 / KM_PX)
    for i, (y, x) in enumerate(seeds):
        c = max(math.cos(math.radians(LAT[y])), 0.15)
        rx = min(int(ry / c), W // 2 - 1)
        rows = np.arange(max(0, y - ry), min(H, y + ry + 1))
        cols = (x + np.arange(-rx, rx + 1)) % W
        # shortcut: o passo leste-oeste usa o cos da latitude da capital na janela toda (erro de ~10% a +-12°);
        # para países polares ou muito altos em latitude, refazer na esfera (grafo por vizinhança 3D).
        cost, _ = MCP_Geometric(fr[np.ix_(rows, cols)], sampling=(1.0, c)).find_costs([(y - rows[0], rx)])
        cost = (cost * KM_PX / weight[i]).astype(np.float32)
        cur, cl = best[np.ix_(rows, cols)], lab[np.ix_(rows, cols)]
        m = cost < cur
        cur[m], cl[m] = cost[m], i + 1
        best[np.ix_(rows, cols)], lab[np.ix_(rows, cols)] = cur, cl
    lab[~land | ice | (best > 2500)] = 0  # só fica sem dono o gelo e o que nenhuma capital alcança

    # Cores: vizinhos nunca iguais; entre as livres, a menos usada (a paleta se espalha).
    n = len(seeds)
    a, b = np.concatenate([lab[:, :-1].ravel(), lab[:-1].ravel()]), np.concatenate([lab[:, 1:].ravel(), lab[1:].ravel()])
    e = (a != b) & (a > 0) & (b > 0)
    adj = [set() for _ in range(n + 1)]
    for p, q in set(zip(a[e].tolist(), b[e].tolist())):
        adj[p].add(q)
        adj[q].add(p)
    color = np.zeros(n + 1, np.int16)
    used = np.zeros(len(PALETTE))
    for c in sorted(range(1, n + 1), key=lambda c: -len(adj[c])):
        free = [k for k in range(len(PALETTE)) if k not in {color[q] - 1 for q in adj[c] if color[q]}]
        k = min(free or range(len(PALETTE)), key=lambda k: used[k] + rng.uniform(0, 0.5))
        color[c] = k + 1
        used[k] += 1
    taken = set()
    names = [""] + [make_name(rng, taken) for _ in range(n)]
    formal = [""] + [formal_name(rng, s) for s in names[1:]]

    # Povoados: Poisson por pixel (densidade por km² pela habitabilidade), posição sorteada dentro do pixel.
    lam = 1.1 * hab ** 1.6 * np.cos(np.radians(LAT))[:, None]
    cnt = rng.poisson(lam)
    py, px = np.nonzero(cnt)
    rep = cnt[py, px]
    py, px = np.repeat(py, rep), np.repeat(px, rep)
    s_lat = 90 - (py + rng.uniform(0, 1, len(py))) * 180 / H
    s_lon = (px + rng.uniform(0, 1, len(px))) * 360 / W - 180
    s_pop = (np.exp(rng.normal(0, 1.1, len(py))) * (0.3 + hab[py, px]) * (1 + near_river[py, px] + near_coast[py, px])).astype(np.float32)

    (r0, a0, w0, r1, a1, w1), _ = br.network()
    d = dict(h=h, land=land, lake=lake, ice=ice, hab=hab, flow=flow.astype(np.float32), lab=lab, seeds=seeds, color=color,
             names=np.array(names, dtype=object), formal=np.array(formal, dtype=object),
             s_lat=s_lat.astype(np.float32), s_lon=s_lon.astype(np.float32), s_pop=s_pop,
             riv=np.stack([r0, a0, w0, r1, a1, w1]).astype(np.float32))
    np.savez(path, **d)
    return d


def overview(d):
    """Visão geral do planeta (equiretangular, 4096x2048): países, relevo e mar. Para escolher as vistas."""
    h = d["h"]
    pal = np.array([rgb(UNCLAIMED)] + [rgb(c) for c, _ in PALETTE])
    col = pal[np.where(d["lab"] > 0, d["color"][d["lab"]], 0)]
    g = np.gradient(ndimage.gaussian_filter(np.maximum(h, 0), 1.0) * 0.004)
    sh = np.clip(1 + (-g[1] * -0.7 + -g[0] * -0.7), 0.4, 1.5)[..., None]
    sea = np.clip(-h / 5000, 0, 1)[..., None]
    water = rgb("#2b5866") * (1 - sea) + rgb("#0f2230") * sea
    img = np.where(d["land"][..., None], col * sh, water)
    edge = (d["lab"] != np.roll(d["lab"], 1, 1)) | (d["lab"] != np.roll(d["lab"], 1, 0))
    img[edge & d["land"]] *= 0.3
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "mundo.png"))


# ---------------------------------------------------------------- vista regional
SIZE = (1920, 1440)
SS = 3  # supersampling das camadas vetoriais (rios, estradas, pontos): o PIL não suaviza linhas
VIEWS = {  # centro e largura; escolhidas na visão geral (mundo.png)
    "golfo": dict(lat=12.6, lon=46.8, km=5000),
    "oeste": dict(lat=30.6, lon=-111.6, km=5000),
    "sul": dict(lat=-25.0, lon=-79.0, km=5000),
    "leste": dict(lat=21.6, lon=129.6, km=5000),
    "norte": dict(lat=54.0, lon=81.0, km=5000),
}


class View:
    """Projeção azimutal equidistante centrada na vista: sem o estiramento leste-oeste da equiretangular.
    Cada pixel da saída sabe o seu ponto (lat, lon) e a posição fracionária na grade de 4K (amostra sem deslocar nada)."""

    def __init__(self, lat, lon, km, size=SIZE):
        self.w, self.h = size
        self.kpp = km / self.w
        self.f0, self.l0 = math.radians(lat), math.radians(lon)
        X, Y = np.meshgrid((np.arange(self.w) + 0.5 - self.w / 2) * self.kpp, (self.h / 2 - np.arange(self.h) - 0.5) * self.kpp)
        rho = np.maximum(np.hypot(X, Y), 1e-9)
        c = rho / R_KM
        la = np.arcsin(np.cos(c) * math.sin(self.f0) + Y * np.sin(c) * math.cos(self.f0) / rho)
        lo = self.l0 + np.arctan2(X * np.sin(c), rho * math.cos(self.f0) * np.cos(c) - Y * math.sin(self.f0) * np.sin(c))
        self.lat, self.lon = np.degrees(la), (np.degrees(lo) + 180) % 360 - 180
        row = (90 - self.lat) / 180 * H - 0.5
        c0 = (lon + 180) / 360 * W - 0.5
        col = ((self.lon + 180) / 360 * W - 0.5 - c0 + W / 2) % W - W / 2 + c0  # contínua em volta do centro (180° sem salto)
        r0, r1 = max(0, int(row.min()) - 10), min(H, int(row.max()) + 11)
        c_lo = int(math.floor(col.min())) - 10
        self.rows, self.cols = slice(r0, r1), np.arange(c_lo, int(col.max()) + 11) % W
        self.rr, self.cc = row - r0, col - c_lo

    def crop(self, a):
        return a[self.rows][:, self.cols]

    def sample(self, a, order=1, cropped=False):
        a = (a if cropped else self.crop(a)).astype(np.float32)
        return ndimage.map_coordinates(a, [self.rr, self.cc], order=order, mode="nearest")

    def project(self, lat, lon):
        """Graus -> pixel (x, y) contínuo da saída, e se está no hemisfério visível."""
        la, dl = np.radians(lat), np.radians(lon) - self.l0
        cosc = math.sin(self.f0) * np.sin(la) + math.cos(self.f0) * np.cos(la) * np.cos(dl)
        c = np.arccos(np.clip(cosc, -1, 1))
        k = np.where(c > 1e-9, c / np.maximum(np.sin(c), 1e-12), 1.0)
        X = R_KM * k * np.cos(la) * np.sin(dl)
        Y = R_KM * k * (math.cos(self.f0) * np.sin(la) - math.sin(self.f0) * np.cos(la) * np.cos(dl))
        return X / self.kpp + self.w / 2, self.h / 2 - Y / self.kpp, cosc > 0


def vnoise(p, seed):
    """Ruído de valor 3D (-1..1) com interpolação suave; p em unidades do reticulado."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3 - 2 * f)
    out = 0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                n = ((i[..., 0] + dx) * 73856093) ^ ((i[..., 1] + dy) * 19349663) ^ ((i[..., 2] + dz) * 83492791) ^ (seed * 2654435761)
                n = (n ^ (n >> 13)) * 1274126177
                v = ((n ^ (n >> 16)) & 0xFFFF).astype(np.float32) / 32767.5 - 1
                wgt = (u[..., 0] if dx else 1 - u[..., 0]) * (u[..., 1] if dy else 1 - u[..., 1]) * (u[..., 2] if dz else 1 - u[..., 2])
                out = out + wgt * v
    return out


def fbm(P, kms, seed, ridged=False):
    """Soma de oitavas de comprimento de onda kms (km) na posição 3D da esfera: o mesmo lugar dá o mesmo ruído em qualquer vista."""
    out, amp, tot = 0, 1.0, 0
    for k, km in enumerate(kms):
        n = vnoise(P * (R_KM / km), seed + k)
        out = out + amp * ((1 - np.abs(n)) * 2 - 1 if ridged else n)
        tot += amp
        amp *= 0.55
    return out / tot


def shade(z, kpp, exag):
    """Sombreado (1 = plano) com luz do noroeste a 40°, como a referência; z em metros, kpp em km por pixel."""
    gy, gx = np.gradient(z * exag, kpp * 1000)
    alt, az = math.radians(40), math.radians(315)
    le, ln, lu = math.sin(az) * math.cos(alt), math.cos(az) * math.cos(alt), math.sin(alt)
    return (-gx * le + gy * ln + lu) / np.sqrt(gx * gx + gy * gy + 1) / lu


def ramp(x, stops):
    xs, cs = zip(*stops)
    cs = np.array([rgb(c) for c in cs])
    return np.stack([np.interp(x, xs, cs[:, k]) for k in range(3)], -1)


def over(img, alpha, color):
    a = np.clip(alpha, 0, 1)[..., None]
    img *= 1 - a
    img += a * (rgb(color) if isinstance(color, str) else color)


def chaikin(pts, n=2):
    for _ in range(n):
        if len(pts) < 3:
            break
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        pts = np.vstack([pts[:1], np.stack([q, r], 1).reshape(-1, 2), pts[-1:]])
    return pts


def font(size, style="Bold Condensed"):
    f = ImageFont.truetype(FONT, int(size))
    f.set_variation_by_name(style)
    return f


def spaced_text(text, size, fill, stroke, track, style="Bold SemiCondensed", stroke_w=None, shadow=True):
    """Texto com espaçamento entre letras (o PIL não tem), contorno e sombra suave, em RGBA."""
    f = font(size, style)
    sw = max(1, round(size * 0.045)) if stroke_w is None else stroke_w
    widths = [f.getlength(ch) for ch in text]
    gap = track * size
    pad = int(size * 0.3) + sw + 4
    im = Image.new("RGBA", (int(sum(widths) + gap * (len(text) - 1)) + 2 * pad, int(size * 1.25) + 2 * pad))
    dr = ImageDraw.Draw(im)
    x = pad
    for ch, wch in zip(text, widths):
        dr.text((x, pad), ch, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke)
        x += wch + gap
    if shadow:
        sh = Image.new("RGBA", im.size, (20, 14, 12, 0))
        sh.putalpha(im.getchannel("A").filter(ImageFilter.GaussianBlur(size * 0.06)).point(lambda v: v * 0.55))
        moved = Image.new("RGBA", im.size)
        moved.paste(sh, (max(1, int(size) // 30),) * 2)
        im = Image.alpha_composite(moved, im)
    return im


def paste_center(base, im, x, y, angle=0.0):
    if angle:
        im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
    base.alpha_composite(im, (int(round(x - im.width / 2)), int(round(y - im.height / 2))))
    return im


def render(d, name, lat, lon, km):
    v = View(lat, lon, km)
    w, h, kpp = v.w, v.h, v.kpp
    px, py, _ = v.project(v.lat[::97, ::89], v.lon[::97, ::89])  # ida e volta da projeção: o centro de cada pixel
    assert np.allclose(px, np.arange(0, w, 89)[None] + 0.5, atol=0.01) and np.allclose(py, np.arange(0, h, 97)[:, None] + 0.5, atol=0.01)
    s = KM_PX / kpp  # pixels da saída por pixel do dado
    rng = np.random.default_rng(abs(hash(name)) % 2**32)
    P = unit(v.lat, v.lon)

    # Costa: distância com sinal à Landmask (px do dado), reamostrada. A versão suavizada tira a escada de pixels, mas
    # fica presa a +-0,5 px da original: nada anda mais que ~6 km, e ilha de 1 pixel ou canal de 1 pixel não somem.
    land4 = v.crop(d["land"])
    raw = ndimage.distance_transform_edt(land4) - ndimage.distance_transform_edt(~land4)
    raw_u = v.sample(raw, 3, cropped=True)
    sdf = np.clip(v.sample(ndimage.gaussian_filter(raw, 1.2), 3, cropped=True), raw_u - 0.5, raw_u + 0.5)
    sdf += 0.3 * fbm(P, [24, 12, 6, 3], 1)
    land = sdf > 0
    # Precisão: a costa desenhada não sai de 0,8 px do dado (0,5 da suavização + 0,3 do ruído).
    assert not (land != (raw_u > 0))[np.abs(raw_u) > 0.85].any(), "costa fora da tolerância"
    g = np.hypot(*np.gradient(sdf))
    dpx = sdf / np.maximum(g, 1e-4)  # distância à costa em pixels da saída (com sinal)
    lake = (v.sample(ndimage.binary_dilation(v.crop(d["lake"]), iterations=2), 0, cropped=True) > 0.5) & ~land

    # Relevo: altitude calibrada (sem os degraus do Gleba) + detalhe fractal proporcional ao relevo local.
    h4 = v.crop(d["h"])
    hu = v.sample(ndimage.gaussian_filter(h4, 0.8), 3, cropped=True)
    hp = np.maximum(h4, 0)
    rel = v.sample(np.sqrt(np.maximum(ndimage.gaussian_filter(hp * hp, 2) - ndimage.gaussian_filter(hp, 2) ** 2, 0)), 1, cropped=True)
    det = fbm(P, [40, 20, 10, 5], 7, ridged=True)
    hl = np.where(land, np.maximum(hu, 5) + (15 + 0.6 * rel) * det, hu)
    # Como a referência: sombras grandes e macias (relevo desfocado, bem exagerado) e só um pouco de detalhe fino.
    sh = 0.75 * shade(ndimage.gaussian_filter(hl, 3.0), kpp, 20.0) + 0.25 * shade(ndimage.gaussian_filter(hl, 0.8), kpp, 5.0)

    # Rios (rede vetorial do build_rivers): máscara suave, também usada como "muro" para a fronteira grudar no rio.
    rv = d["riv"]
    x0, y0, a0 = v.project(rv[1], rv[0])
    x1, y1, a1 = v.project(rv[4], rv[3])
    keep = a0 & a1 & (np.minimum(x0, x1) > -20) & (np.maximum(x0, x1) < w + 20) & (np.minimum(y0, y1) > -20) & (np.maximum(y0, y1) < h + 20)
    rim = Image.new("L", (w * SS, h * SS))
    dr = ImageDraw.Draw(rim)
    for xa, ya, xb, yb, wk in zip(x0[keep], y0[keep], x1[keep], y1[keep], rv[2][keep]):
        px = SS * float(np.clip(1.0 + 0.3 * math.log2(wk / 0.1), 1.0, 2.8))
        dr.line([(xa * SS, ya * SS), (xb * SS, yb * SS)], fill=255, width=max(1, round(px)))
        dr.ellipse([xb * SS - px / 2, yb * SS - px / 2, xb * SS + px / 2, yb * SS + px / 2], fill=255)
    river = np.asarray(rim.resize((w, h), Image.BOX), np.float32) / 255 * land

    # Fronteiras: rótulo de 4K suavizado (sem escada) e acomodado, numa faixa de ~1 px do dado, nas cristas e rios.
    lab4 = np.where(land4, v.crop(d["lab"]), -1)
    best = np.full((h, w), -1.0, np.float32)
    L1 = np.full((h, w), -1, np.int32)
    for c in np.unique(lab4):
        val = v.sample(ndimage.gaussian_filter((lab4 == c).astype(np.float32), 0.6), 1, cropped=True)
        m = val > best
        best[m], L1[m] = val[m], c
    edge = np.zeros((h, w), bool)
    edge[:, 1:] |= L1[:, 1:] != L1[:, :-1]
    edge[1:] |= L1[1:] != L1[:-1]
    band = ndimage.distance_transform_edt(~(edge & (L1 >= 0))) < 0.9 * s
    markers = np.where(land & ~band & (L1 >= 0), L1 + 1, 0)
    pri = (hl - hl[land].min()) / (np.ptp(hl[land]) + 1) + 3 * (river > 0.25)
    lab = watershed(pri, markers, mask=land) - 1
    if (land & (lab < 0)).any():  # terra sem marcador (ilhota da reamostragem): dono do vizinho mais perto
        _, (iy, ix) = ndimage.distance_transform_edt(lab < 0, return_indices=True)
        lab = np.where(land & (lab < 0), lab[iy, ix], lab)

    # Terra: cor do país x sombreado (sombra puxada para um marrom escuro, como na referência).
    pal = np.array([rgb(UNCLAIMED)] + [rgb(c) for c, _ in PALETTE])
    cidx = np.where(lab > 0, d["color"][np.maximum(lab, 0)], 0)
    base = pal[cidx]
    ice = (v.sample(d["ice"], 1) > 0.5) & (lab <= 0)
    base[ice] = rgb("#d6d9d6")  # calota sem dono: gelo, não "terra de ninguém"
    t = sh - 1
    lit = np.clip(t, 0, 0.6)[..., None]
    dark = np.clip(-t, 0, 0.85)[..., None]
    col = base * (1 + 0.4 * lit) * (1 - 0.62 * dark) + dark * 0.10 * rgb("#2a1a14")
    col *= 1 + 0.035 * fbm(P, [6, 3], 21)[..., None]

    # Água: cor pela profundidade (da própria altitude), relevo do fundo bem fraco, brilho e anéis junto à costa.
    depth = np.maximum(-hu, 0)
    sea = ramp(np.sqrt(depth), [(0, "#3a6a77"), (8, "#2a5363"), (16, "#1d3d4e"), (30, "#13283a"), (50, "#0e1e2b"), (80, "#0b1722")])
    sea *= (1 + 0.18 * (shade(ndimage.gaussian_filter(hu, 3), kpp, 1.5) - 1).clip(-1, 1))[..., None]
    dist_km = -sdf * KM_PX
    over(sea, 0.5 * np.exp(-np.maximum(dist_km, 0) / 14), "#3f7480")
    for r, a in ((10, 0.32), (22, 0.22), (38, 0.13)):
        over(sea, a * np.clip(1 - np.abs(dist_km / kpp - r / kpp) / 0.8, 0, 1), "#6a9aa5")
    lk = np.broadcast_to(rgb("#1f4e5a"), sea.shape).copy()
    over(lk, 0.30 * np.exp(-np.maximum(dist_km, 0) / 3), "#4c8590")
    for r, a in ((4, 0.25), (9, 0.15)):
        over(lk, a * np.clip(1 - np.abs(dist_km / kpp - r / kpp) / 0.8, 0, 1), "#5e95a0")
    img = np.where(land[..., None], col, np.where(lake[..., None], lk, sea)).astype(np.float32)

    # Textura da terra: pontinhos claros, marcas de lavoura nas planícies boas e pintas claras nas serras altas.
    hab = v.sample(d["hab"], 1)
    over(img, (rng.random((h, w)) < 0.004) * land * 0.22, "#f4ead8")
    snow = np.clip((hl - 2300) / 2500, 0, 1) * land
    over(img, (rng.random((h, w)) < 0.14 * snow) * (0.3 + 0.4 * np.clip(sh - 0.6, 0, 1)), "#f1e6e6")
    over(img, river * 0.9, "#7aa9b6")
    ov = Image.new("RGBA", (w, h))
    od = ImageDraw.Draw(ov)
    step = 15
    for gy in range(step // 2, h, step):
        for gx in range(step // 2, w, step):
            x, y = gx + rng.integers(-5, 6), gy + rng.integers(-5, 6)
            if 0 <= x < w and 0 <= y < h and land[y, x] and hab[y, x] > 0.3 and sh[y, x] > 0.85 and rng.random() < 0.55:
                for k in (0, 2):
                    od.line([(x - 1, y + k), (x + 1, y + k)], fill=(40, 32, 28, 135))
    img_rgb = np.asarray(ov, np.float32) / 255
    over(img, img_rgb[..., 3], img_rgb[..., :3])

    # Linhas de fronteira e de costa.
    e = np.zeros((h, w), np.float32)
    e[:, 1:] += (lab[:, 1:] != lab[:, :-1]) & land[:, 1:] & land[:, :-1]
    e[1:] += (lab[1:] != lab[:-1]) & land[1:] & land[:-1]
    over(img, np.clip(ndimage.gaussian_filter(np.minimum(e, 1), 0.55) * 2.2, 0, 0.95), "#1a1716")
    over(img, 0.85 * np.clip(1.15 - np.abs(dpx + 0.35), 0, 1), "#15191c")

    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    occ = np.zeros((h, w), bool)  # onde já há rótulo
    countries_in_view(d, v, lab, land, out, occ)
    roads_and_places(d, v, lab, land, hl, out, occ, rng)
    out.convert("RGB").save(os.path.join(OUT, f"{name}.png"))
    viewer(d, name, out, np.where(land, np.maximum(lab, 0), 0))
    return out


def viewer(d, name, out, ids):
    """Página com a dica ao passar o mouse (nome curto + nome formal), como na referência. Tudo embutido: abre do disco."""
    import base64
    import io
    import json

    def b64(im, fmt, **kw):
        buf = io.BytesIO()
        im.save(buf, fmt, **kw)
        return base64.b64encode(buf.getvalue()).decode()
    idimg = Image.fromarray(np.stack([ids & 255, ids >> 8, np.zeros_like(ids)], -1).astype(np.uint8))
    names = {int(c): [d["names"][c].upper(), d["formal"][c]] for c in np.unique(ids) if c > 0}
    html = f"""<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mapa político ({name})</title><style>
body{{margin:0;background:#0b1722}} img{{display:block}}
#tip{{position:fixed;pointer-events:none;display:none;background:#0c0c0c;border:1px solid #3a3a3a;padding:9px 14px 10px;color:#f2f2f2;
font-family:Bahnschrift,"IBM Plex Sans",system-ui,sans-serif}}
#tip b{{display:block;font-size:15px;letter-spacing:.04em;margin-bottom:3px}} #tip span{{font-size:13px;color:#d6d6d6}}
</style></head><body><img id="map" src="data:image/jpeg;base64,{b64(out.convert("RGB"), "JPEG", quality=92)}" alt="Mapa político de Evron, vista {name}">
<div id="tip"><b></b><span></span></div><script>
const names={json.dumps(names, ensure_ascii=False)};
const map=document.getElementById("map"), tip=document.getElementById("tip");
const ids=new Image(); let px=null;
ids.onload=()=>{{const c=document.createElement("canvas");c.width=ids.width;c.height=ids.height;const g=c.getContext("2d");g.drawImage(ids,0,0);px=g.getImageData(0,0,c.width,c.height).data;}};
ids.src="data:image/png;base64,{b64(idimg, "PNG")}";
map.addEventListener("mousemove",e=>{{if(!px)return;const r=map.getBoundingClientRect();
const x=Math.floor((e.clientX-r.left)*ids.width/r.width), y=Math.floor((e.clientY-r.top)*ids.height/r.height), i=(y*ids.width+x)*4;
const n=names[px[i]+256*px[i+1]]; if(!n){{tip.style.display="none";return;}}
tip.children[0].textContent=n[0]; tip.children[1].textContent=n[1]; tip.style.display="block";
tip.style.left=(e.clientX+18)+"px"; tip.style.top=(e.clientY+14)+"px";}});
map.addEventListener("mouseleave",()=>tip.style.display="none");
</script></body></html>"""
    with open(os.path.join(OUT, f"{name}.html"), "w", encoding="utf-8") as fh:
        fh.write(html)


def countries_in_view(d, v, lab, land, out, occ):
    """Nome do país ao longo do eixo maior da parte visível, centrado na corda mais longa pelo seu ponto mais interno.
    Os maiores primeiro; o rótulo encolhe até caber no próprio país (82% das letras) sem cobrir outro rótulo."""
    f = 4
    small = lab[::f, ::f]
    ids, area = np.unique(small[small > 0], return_counts=True)
    for c in ids[np.argsort(-area)]:
        m = small == c
        if m.sum() < 0.012 * small.size:
            continue
        dt = ndimage.distance_transform_edt(np.pad(m, 1))[1:-1, 1:-1]
        ay, ax = np.unravel_index(dt.argmax(), dt.shape)
        ys, xs = np.nonzero(m)
        dx, dy = np.linalg.eigh(np.cov(np.stack([xs, ys])))[1][:, 1]
        if dx < 0:
            dx, dy = -dx, -dy
        ang = math.degrees(math.atan2(-dy, dx))
        if abs(ang) > 65:  # quase vertical: a referência nunca passa disso
            ang = math.copysign(65, ang)
            dx, dy = math.cos(math.radians(ang)), -math.sin(math.radians(ang))

        def reach(sgn):
            k = 0
            while True:
                x, y = int(round(ax + sgn * k * dx)), int(round(ay + sgn * k * dy))
                if not (0 <= x < m.shape[1] and 0 <= y < m.shape[0]) or not m[y, x]:
                    return k
                k += 1
        a, b = reach(1), reach(-1)
        cx, cy = (ax + (a - b) / 2 * dx) * f, (ay + (a - b) / 2 * dy) * f
        text = d["names"][c].upper()
        dark = PALETTE[d["color"][c] - 1][1]
        track = 0.2
        unit_w = sum(font(100, "Bold SemiCondensed").getlength(ch) for ch in text) / 100 + track * (len(text) - 1)
        size = min((a + b) * f * 0.8 / unit_w, dt.max() * f * 2.2, 92)
        fill, stroke = ((32, 28, 27, 255), (32, 28, 27, 255)) if dark else ((246, 241, 228, 255), (38, 28, 24, 255))
        while size >= 22:
            im = spaced_text(text, size, fill, stroke, track, stroke_w=0 if dark else None, shadow=not dark)
            rot = im.rotate(ang, resample=Image.BICUBIC, expand=True)
            x0, y0 = int(round(cx - rot.width / 2)), int(round(cy - rot.height / 2))
            yy, xx = np.nonzero(np.asarray(rot.getchannel("A")) > 40)
            yy, xx = yy + y0, xx + x0
            ok = (yy >= 0) & (yy < lab.shape[0]) & (xx >= 0) & (xx < lab.shape[1])
            if ok.mean() > 0.97 and (lab[yy[ok], xx[ok]] == c).mean() > 0.82 and occ[yy[ok], xx[ok]].mean() < 0.01:
                out.alpha_composite(rot, (x0, y0))
                occ[yy[ok], xx[ok]] = True
                break
            size *= 0.88


def roads_and_places(d, v, lab, land, hl, out, occ, rng):
    w, h, kpp = v.w, v.h, v.kpp
    sx, sy, vis = v.project(d["s_lat"], d["s_lon"])
    ins = vis & (sx >= 2) & (sx < w - 2) & (sy >= 2) & (sy < h - 2)
    idx = np.nonzero(ins)[0]
    idx = idx[land[sy[idx].astype(int), sx[idx].astype(int)]]
    pop = d["s_pop"][idx]
    order = idx[np.argsort(-pop)]

    # Capitais (as sementes) que caem na vista, e as maiores cidades.
    seeds = d["seeds"]
    cx, cy, cv = v.project(LAT[seeds[:, 0]], LON[seeds[:, 1]])
    caps = [i for i in range(len(seeds)) if cv[i] and 8 <= cx[i] < w - 8 and 8 <= cy[i] < h - 8 and land[int(cy[i]), int(cx[i])]]
    nodes = [dict(x=cx[i], y=cy[i], cap=i + 1, pop=1e9, name=None) for i in caps]
    for k in order:
        if len(nodes) >= len(caps) + 10:
            break
        x, y = sx[k], sy[k]
        if all(math.hypot(x - n["x"], y - n["y"]) > 110 for n in nodes):
            nodes.append(dict(x=x, y=y, cap=0, pop=d["s_pop"][k], name=None))
    nrng = np.random.default_rng(int(abs(v.f0 * 1e6 + v.l0 * 1e3)))
    taken = set(d["names"].tolist())
    for n in nodes:
        n["name"] = make_name(nrng, taken).upper()

    # Estradas: caminho de menor custo numa grade 4x mais grossa (declividade cara, água quase intransponível);
    # quem vem depois aproveita a estrada já feita (custo menor nela), então os caminhos se juntam em troncos.
    g = 4
    hg = hl[g // 2::g, g // 2::g]
    lg = land[g // 2::g, g // 2::g]
    gy_, gx_ = np.gradient(hg, kpp * 1000 * g)
    cost = 1 + 60 * np.hypot(gx_, gy_) + np.where(lg, 0, 300)
    lab_g = lab[g // 2::g, g // 2::g]

    def route(a, b):
        ga = (min(int(a["y"] / g), hg.shape[0] - 1), min(int(a["x"] / g), hg.shape[1] - 1))
        gb = (min(int(b["y"] / g), hg.shape[0] - 1), min(int(b["x"] / g), hg.shape[1] - 1))
        m = MCP_Geometric(cost)
        m.find_costs([ga], [gb])
        p = np.array(m.traceback(gb), np.float64)
        cost[p[:, 0].astype(int), p[:, 1].astype(int)] *= 0.45
        return chaikin(p[:, ::-1] * g + g / 2, 3)

    red, yellow = [], []
    pairs = set()
    a_, b_ = np.concatenate([lab_g[:, :-1].ravel(), lab_g[:-1].ravel()]), np.concatenate([lab_g[:, 1:].ravel(), lab_g[1:].ravel()])
    e = (a_ != b_) & (a_ > 0) & (b_ > 0)
    neigh = set(zip(a_[e].tolist(), b_[e].tolist()))
    capn = {n["cap"]: n for n in nodes if n["cap"]}
    for p, q in neigh:
        if p < q and p in capn and q in capn and (q, p) not in pairs:
            pairs.add((p, q))
            red.append(route(capn[p], capn[q]))
    for n in nodes:
        if n["cap"]:
            continue
        own = int(lab[int(n["y"]), int(n["x"])])
        tgt = capn.get(own) or min((m for m in nodes if m is not n), key=lambda m: math.hypot(m["x"] - n["x"], m["y"] - n["y"]))
        (red if n["pop"] > np.percentile([m["pop"] for m in nodes if not m["cap"]] or [0], 60) else yellow).append(route(n, tgt))
    towns = [k for k in order[:400]][:60]
    for k in towns:
        t = dict(x=sx[k], y=sy[k])
        tgt = min(nodes, key=lambda m: math.hypot(m["x"] - t["x"], m["y"] - t["y"]))
        if 25 < math.hypot(tgt["x"] - t["x"], tgt["y"] - t["y"]) < 260:
            yellow.append(route(t, tgt))

    lay = Image.new("RGBA", (w * SS, h * SS))
    dr = ImageDraw.Draw(lay)

    def poly(pts, width, fill):
        q = [(float(x) * SS, float(y) * SS) for x, y in pts]
        dr.line(q, fill=fill, width=int(width * SS), joint="curve")

    # Mancha urbana das cidades grandes (verde-claro, como a referência), por baixo das estradas.
    for n in nodes:
        r = (9 if n["cap"] else 5 + 3 * nrng.random()) * SS
        for _ in range(9):
            ox, oy = nrng.normal(0, r * 0.55, 2)
            rr = r * nrng.uniform(0.35, 0.7)
            dr.ellipse([n["x"] * SS + ox - rr, n["y"] * SS + oy - rr, n["x"] * SS + ox + rr, n["y"] * SS + oy + rr],
                       fill=(186, 220, 178, 225), outline=(214, 150, 160, 200), width=SS)
    for p in yellow:
        poly(p, 3.2, (70, 58, 40, 150))
        poly(p, 2.0, (231, 214, 156, 240))
    for p in red:
        poly(p, 5.2, (150, 44, 62, 235))
        poly(p, 3.4, (222, 92, 112, 255))
        poly(p, 1.2, (240, 160, 172, 255))
    # Povoados: pontos brancos; maiores com um halo.
    for k in order[:3800][::-1]:  # os maiores por último, por cima
        r = SS * float(np.clip(1.0 + 0.6 * math.log1p(d["s_pop"][k]), 1.1, 3.0))
        x, y = sx[k] * SS, sy[k] * SS
        dr.ellipse([x - r, y - r, x + r, y + r], fill=(246, 243, 233, 225))
    out.alpha_composite(lay.resize((w, h), Image.LANCZOS))

    # Marcadores e nomes: estrela nas capitais, quadrado nas cidades; o nome vai onde não cobre outro rótulo.
    mk = Image.new("RGBA", (w * SS, h * SS))
    md = ImageDraw.Draw(mk)
    for n in nodes:
        x, y = n["x"] * SS, n["y"] * SS
        if n["cap"]:
            R, r = 9.5 * SS, 3.9 * SS
            pts = [(x + (R if i % 2 == 0 else r) * math.sin(i * math.pi / 5), y - (R if i % 2 == 0 else r) * math.cos(i * math.pi / 5)) for i in range(10)]
            md.polygon(pts, fill=(250, 248, 240, 255), outline=(30, 26, 24, 255), width=SS)
        else:
            q = 4.2 * SS
            md.rectangle([x - q, y - q, x + q, y + q], fill=(250, 248, 240, 255), outline=(30, 26, 24, 255), width=SS)
    out.alpha_composite(mk.resize((w, h), Image.LANCZOS))
    for n in sorted((n for n in nodes if not n["cap"]), key=lambda n: -n["pop"]):  # capital: só a estrela, como na referência
        im = spaced_text(n["name"], 16, (250, 248, 240, 255), (24, 20, 20, 255), 0.06, style="SemiBold", stroke_w=3, shadow=False)
        for ox, oy in ((im.width / 2 - 4, 0), (-im.width / 2 + 4, 0), (0, -16), (0, 16)):
            x, y = n["x"] + ox, n["y"] + oy
            x0, y0 = int(x - im.width / 2) + 8, int(y - im.height / 2) + 8
            x1, y1 = x0 + im.width - 16, y0 + im.height - 16
            if x0 < 0 or y0 < 0 or x1 >= w or y1 >= h or occ[y0:y1, x0:x1].any():
                continue
            paste_center(out, im, x, y)
            occ[y0:y1, x0:x1] = True
            break


if __name__ == "__main__":
    import time
    t = time.time()
    d = world()
    print("mundo", round(time.time() - t), "s;", len(d["seeds"]), "países;", len(d["s_lat"]), "povoados")
    if not os.path.exists(os.path.join(OUT, "mundo.png")):
        overview(d)
    if sys.argv[1:] == ["paises"]:  # para tools/paises_ficticios.gd: os países do protótipo como cadastros do jogo
        import json
        rng = np.random.default_rng(99)
        taken = set(d["names"].tolist())
        rows = [dict(nome=str(d["names"][c]), oficial=str(d["formal"][c]), capital=make_name(rng, taken),
                     lat=round(float(LAT[y]), 4), lon=round(float(LON[x]), 4), cor=PALETTE[d["color"][c] - 1][0])
                for c, (y, x) in enumerate(d["seeds"], start=1)]
        with open(os.path.join(OUT, "paises.json"), "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=0)
        print(len(rows), "países em", os.path.join(OUT, "paises.json"))
        sys.exit()
    for name in sys.argv[1:] or VIEWS:
        t = time.time()
        render(d, name, **VIEWS[name])
        print(name, round(time.time() - t), "s")
