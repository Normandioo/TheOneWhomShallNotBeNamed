"""Rios de Evron com largura em metros: a linha central de cada rio e a distância até ela, para o shader desenhar.

O Gleba guarda os rios como fluxo por célula de 9,77 km ("Waterflow.png"); pintado na imagem, o rio teria no mínimo
um pixel de largura (6 a 13 km), de 5 a 15 vezes mais largo que os maiores rios da Terra. Aqui:
  1. cada célula com fluxo t > T0 vira um nó; o nó desce para o vizinho de maior fluxo (o fluxo acumula rio abaixo);
     o vizinho de água (mar ou lago) é a foz;
  2. a linha que liga os nós (escada de pixels) é suavizada ao longo do curso principal;
  3. para cada texel de 8K a até WINDOW_KM da linha, grava o vetor (leste, norte) em km até o ponto mais próximo dela.
     Esse vetor varia linearmente com a posição perto de um trecho reto: a interpolação bilinear da GPU dá a distância
     certa no meio dos texels, e o shader desenha um rio de 100 m tão nítido quanto um de 5 km.
Largura (regra escolhida, não medida: a calibração só garante a ordem dos valores de fluxo): o fluxo do Gleba está em
escala que cresce como log da vazão, e a largura dos rios cresce com a raiz da vazão; então a largura é exponencial
em t, de 0,1 km em t = 0,6 a 5 km em t = 1 (Amazonas, curso principal: 2 a 10 km; Mississippi: 1 a 2 km).

Saída em data/evron/:
  - rivers_8192x4096.rgh = float16 little-endian, 2 canais (Image.FORMAT_RGH do Godot): km até a linha (leste, norte);
    longe de qualquer rio = (FAR_KM, FAR_KM);
  - rivers_width.png = largura do rio mais próximo, código 0..255 (ver width_km), mesma grade.
Rodado por import_maps.py; sozinho: python tools/build_rivers.py   (~1 min)
"""
import os

import numpy as np
from PIL import Image

import build_natural as bn

D = bn.D
W, H = 8192, 4096
T0 = 0.60              # fluxo mínimo que vira rio desenhado (o "River.png" do Gleba usa 0,5: 17% da terra)
W_MIN, W_MAX = 0.1, 5.0  # km, em t = T0 e t = 1
WINDOW_KM = 20.0       # até onde o vetor é gravado: cobre meio pixel da tela com o globo inteiro na tela (~25 km/px)
FAR_KM = 30.0
RADIUS_KM = 6371.0  # raio médio da Terra (EvronGeo.RADIUS_KM); Evron tem o tamanho da Terra
KM_PER_DEG = 2 * np.pi * RADIUS_KM / 360


def width_km(t):
    return W_MIN * (W_MAX / W_MIN) ** np.clip((t - T0) / (1 - T0), 0, 1)


def width_code(w):
    """km -> 0..255 (log): o mesmo que o shader decodifica (globe.gdshader, river_width_km)."""
    return np.round(255 * np.log(w / W_MIN) / np.log(W_MAX / W_MIN)).clip(0, 255).astype(np.uint8)


def _nbrs(m):
    """Os 8 vizinhos P2..P9 (N, NE, L, SE, S, SO, O, NO) de cada pixel; a longitude dá a volta, os polos não."""
    p = np.pad(m, ((1, 1), (0, 0)))
    def at(dy, dx):
        return np.roll(p, -dx, 1)[1 + dy: 1 + dy + m.shape[0]]
    return [at(-1, 0), at(-1, 1), at(0, 1), at(1, 1), at(1, 0), at(1, -1), at(0, -1), at(-1, -1)]


def thin_dilate(m):
    return sum(n.astype(np.uint8) for n in _nbrs(m))


def thin(m):
    """Afinamento de Zhang-Suen (1984): reduz a faixa a uma linha de 1 pixel conectada, sem encurtar as pontas."""
    m = m.astype(np.uint8)
    while True:
        changed = False
        for step in (0, 1):
            p2, p3, p4, p5, p6, p7, p8, p9 = _nbrs(m)
            b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            a = sum(((seq[k] == 0) & (seq[k + 1] == 1)).astype(np.uint8) for k in range(8))
            if step == 0:
                c = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                c = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            rem = (m == 1) & (b >= 2) & (b <= 6) & (a == 1) & c
            if rem.any():
                m[rem] = 0
                changed = True
        if not changed:
            return m.astype(bool)


def network():
    """Nós (lon, lat, largura) e trechos (i, j) da rede de rios, já suavizados."""
    land = bn.load("Landmask.png")[..., 0] == 80
    flow = bn.ramp_t(bn.load("Waterflow.png"), bn.VIRIDIS)
    t_max = -20 + 60 * np.maximum(bn.ramp_t(bn.load("Temperatura Janeiro.png"), bn.MAGMA),
                                  bn.ramp_t(bn.load("Temperatura Julho.png"), bn.MAGMA))
    ice = bn.is_color(bn.load("Clima.png"), (104, 104, 104)) | bn.is_color(bn.load("BiomasGleba.png"), (236, 236, 236))
    on = land & (flow > T0) & ~ice & (t_max > 0)  # sem rio sob a calota nem onde a água não descongela
    # A faixa de fluxo tem 1 a 3 células de largura (o vale): afinada até 1 célula, senão vira rios paralelos.
    # A água encostada na faixa entra no afinamento, para a linha chegar até a costa em vez de recuar.
    coast = ~land & (thin_dilate(on) > 0)
    on = thin(on | coast) & land
    sh, sw = flow.shape
    ys, xs = np.nonzero(on)
    n = len(ys)
    idx = -np.ones(flow.shape, np.int64)
    idx[ys, xs] = np.arange(n)

    # Rio abaixo. O fluxo do Gleba vem de uma escala de 256 cores e empata em trechos inteiros (74% dos nós têm um
    # vizinho de fluxo igual), e a altitude de 9,77 km não desce sempre ao longo do vale: nenhum dos dois dá a direção.
    # Então cada rio corre para a sua foz pelo caminho mais curto dentro da rede (busca em largura a partir dos nós que
    # tocam água: mar ou lago); no empate, segue o vizinho de maior fluxo (o curso principal). Rede sem saída
    # (bacia endorreica) termina no seu ponto mais baixo.
    h = np.fromfile(os.path.join(D, "height_4096x2048.f32"), "<f4").reshape(flow.shape)
    nb, nby, nbx = [], [], []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            ny, nx = np.clip(ys + dy, 0, sh - 1), (xs + dx) % sw
            nb.append(np.where((ny == ys) & (nx == xs), -1, idx[ny, nx]))
            nby.append(ny)
            nbx.append(nx)
    nb, nby, nbx = np.stack(nb, 1), np.stack(nby, 1), np.stack(nbx, 1)
    water = ~land[nby, nbx]
    mouth = water.any(1)
    wk = water.argmax(1)  # um vizinho de água qualquer: a foz fica entre os dois
    by, bx = nby[np.arange(n), wk], nbx[np.arange(n), wk]

    dist = np.full(n, np.iinfo(np.int64).max)

    def spread(seeds):
        dist[seeds] = 0
        front, d = seeds, 0
        while front.size:
            c = nb[front].ravel()
            c = np.unique(c[c >= 0])
            c = c[dist[c] > d + 1]
            d += 1
            dist[c] = d
            front = c

    spread(np.nonzero(mouth)[0])
    left = dist == np.iinfo(np.int64).max
    if left.any():  # sem saída: o ponto mais baixo (entre os nós ainda sem caminho) de cada pedaço da rede
        nh = np.where((nb >= 0) & left[np.maximum(nb, 0)], h[nby, nbx], np.inf)
        spread(np.nonzero(left & (h[ys, xs] <= nh.min(1)))[0])
    assert (dist < np.iinfo(np.int64).max).all(), "nó de rio sem caminho até a foz"
    fl = np.where(nb >= 0, flow[nby, nbx], -1.0)
    ok = (nb >= 0) & (dist[np.maximum(nb, 0)] == dist[:, None] - 1)
    down = np.where(dist > 0, nb[np.arange(n), np.where(ok, fl, -2.0).argmax(1)], -1)

    lon = (xs + 0.5) * 360 / sw - 180
    lat = 90 - (ys + 0.5) * 180 / sh
    t = flow[ys, xs]
    # Foz: o ponto da costa entre o nó e a água (meio caminho entre os centros dos dois pixels).
    mlon = lon + 0.5 * ((((bx + 0.5) * 360 / sw - 180) - lon + 180) % 360 - 180)
    mlat = lat + 0.5 * ((90 - (by + 0.5) * 180 / sh) - lat)

    # Suavização ao longo do curso principal: média com o nó de cima (o afluente de maior fluxo) e o de baixo.
    # A escada de pixels de 9,77 km vira curva; nascentes e foz ficam no lugar.
    up = -np.ones(n, np.int64)
    has_down = (down >= 0) & ~mouth
    order = np.argsort(t)  # o afluente de maior fluxo grava por último e fica como o principal
    up[down[order][has_down[order]]] = order[has_down[order]]
    inner = has_down & (up >= 0)
    for _ in range(4):
        d_lon = ((lon[down] - lon + 180) % 360 - 180)
        u_lon = ((lon[up] - lon + 180) % 360 - 180)
        nlon = lon + 0.25 * (d_lon + u_lon)
        nlat = lat + 0.25 * ((lat[down] - lat) + (lat[up] - lat))
        lon = np.where(inner, (nlon + 180) % 360 - 180, lon)
        lat = np.where(inner, nlat, lat)

    w = width_km(t)
    seg_a = np.nonzero(has_down)[0]
    segs = [(lon[seg_a], lat[seg_a], w[seg_a], lon[down[seg_a]], lat[down[seg_a]], w[down[seg_a]])]
    m = np.nonzero(mouth)[0]
    segs.append((lon[m], lat[m], w[m], mlon[m], mlat[m], w[m] * 1.2))  # a foz alarga um pouco
    return [np.concatenate(c) for c in zip(*segs)], n


def rasterize(segs):
    """Para cada texel de 8K perto de um trecho: vetor (leste, norte) em km até o ponto mais próximo, e a largura."""
    alon, alat, aw, blon, blat, bw = segs
    # Caixa de texels em volta do meio de cada trecho: a janela mais meio trecho (o trecho tem até ~25 km).
    hy = int(np.ceil((WINDOW_KM + 15) / (KM_PER_DEG * 180 / H)))
    best_d = np.full(W * H, np.inf, np.float32)
    off = np.full((W * H, 2), FAR_KM, np.float32)
    wid = np.zeros(W * H, np.float32)
    for c0 in range(0, len(alon), 4000):
        sl = slice(c0, c0 + 4000)
        la, lb = alat[sl], blat[sl]
        dlon = ((blon[sl] - alon[sl] + 180) % 360) - 180
        mid_lat = (la + lb) / 2
        cos_m = np.maximum(np.cos(np.deg2rad(mid_lat)), 0.2)
        hx = int(np.ceil((WINDOW_KM + 15) / cos_m.min() / (KM_PER_DEG * 360 / W)))
        cy = np.round((90 - mid_lat) * H / 180 - 0.5).astype(np.int64)
        cx = np.round(((alon[sl] + dlon / 2 + 180) % 360) * W / 360 - 0.5).astype(np.int64)
        gy, gx = np.meshgrid(np.arange(-hy, hy + 1), np.arange(-hx, hx + 1), indexing="ij")
        ty = np.clip(cy[:, None] + gy.ravel()[None], 0, H - 1)
        tx = (cx[:, None] + gx.ravel()[None]) % W
        tlat = 90 - (ty + 0.5) * 180 / H
        tlon = (tx + 0.5) * 360 / W - 180
        cos_t = np.cos(np.deg2rad(tlat))
        # Plano local do texel (km): A e B relativos a ele.
        ax = (((alon[sl][:, None] - tlon + 180) % 360) - 180) * cos_t * KM_PER_DEG
        ay = (la[:, None] - tlat) * KM_PER_DEG
        bx = ax + dlon[:, None] * cos_t * KM_PER_DEG
        by = (lb[:, None] - tlat) * KM_PER_DEG
        ex, ey = bx - ax, by - ay
        s = np.clip(-(ax * ex + ay * ey) / np.maximum(ex * ex + ey * ey, 1e-9), 0, 1)
        px, py = ax + s * ex, ay + s * ey
        d = np.hypot(px, py)
        ok = d < WINDOW_KM
        tid = (ty * W + tx)[ok]
        dd = d[ok].astype(np.float32)
        ww = (aw[sl][:, None] + s * (bw[sl] - aw[sl])[:, None])[ok]
        # O menor por texel: ordena por (texel, distância) e fica com o primeiro de cada texel.
        o = np.lexsort((dd, tid))
        tid, dd = tid[o], dd[o]
        first = np.r_[True, tid[1:] != tid[:-1]]
        tid, dd = tid[first], dd[first]
        sel = o[first]
        closer = dd < best_d[tid]
        tid, dd, sel = tid[closer], dd[closer], sel[closer]
        best_d[tid] = dd
        off[tid, 0] = px[ok][sel]
        off[tid, 1] = py[ok][sel]
        wid[tid] = ww[sel]
    return off.reshape(H, W, 2), wid.reshape(H, W), best_d.reshape(H, W)


def build():
    segs, nodes = network()
    print(f"rios: {nodes} nós, {len(segs[0])} trechos")
    off, wid, dist = rasterize(segs)
    off.astype("<f2").tofile(os.path.join(D, "rivers_8192x4096.rgh"))
    Image.fromarray(width_code(np.maximum(wid, W_MIN)), "L").save(os.path.join(D, "rivers_width.png"))

    # Autoteste: o vetor aponta para a linha (texel + vetor está sobre ela) e a interpolação acha a linha entre texels.
    near = dist < 1e9
    assert np.allclose(np.hypot(off[..., 0], off[..., 1])[near], dist[near], atol=1e-3), "vetor e distância diferentes"
    # Entre dois texels vizinhos de lados opostos de um rio, o vetor interpolado passa por zero: a distância mínima
    # ao longo da interpolação (distância da origem ao segmento o1-o2) fica perto de 0, e a linha aparece ali.
    o1, o2 = off[:, :-1][..., :2], off[:, 1:][..., :2]
    both = ((o1 * o2).sum(-1) < 0) & (dist[:, :-1] < 4) & (dist[:, 1:] < 4)
    a1, a2 = o1[both], o2[both]
    e = a2 - a1
    s = np.clip(-(a1 * e).sum(-1) / np.maximum((e * e).sum(-1), 1e-9), 0, 1)
    mid = np.hypot(*(a1 + s[:, None] * e).T)
    assert np.median(mid) < 0.05, f"a linha não cai entre os texels: {np.median(mid):.2f} km"
    print(f"rios_8192x4096.rgh: {near.sum()} texels com rio a < {WINDOW_KM:.0f} km; "
          f"largura: mediana {np.median(wid[dist < 1]):.2f} km, máx {wid.max():.1f} km; linha entre texels {np.median(mid):.2f} km")


if __name__ == "__main__":
    build()
