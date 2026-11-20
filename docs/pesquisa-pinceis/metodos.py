"""Os métodos de pincel de terreno comparados no estudo (docs/pesquisa-pinceis). Tudo em NumPy, sem dependências extras.

Convenções: o terreno é uma grade N x N de alturas em metros; cada célula tem CELL_KM de lado. O "traço" do pincel é uma
máscara 0..1 (peso do pincel: 1 no eixo do traço, 0 na borda). Todos os métodos recebem a mesma base e a mesma máscara,
para que as diferenças que se vêem nas imagens venham só do método.
"""
import heapq
import time

import numpy as np

N = 320
CELL_KM = 1.5            # 320 x 1,5 = 480 km de lado
CELL_M = CELL_KM * 1000.0


# --- Ruído (gradiente, estilo Perlin), vetorizado --------------------------------------------------------------------
class Noise:
    def __init__(self, seed: int):
        rng = np.random.default_rng(seed)
        self.perm = rng.permutation(256)
        ang = rng.uniform(0, 2 * np.pi, 256)
        self.grad = np.stack([np.cos(ang), np.sin(ang)], 1)

    def perlin(self, x, y):
        xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
        xf, yf = x - xi, y - yi
        def g(ix, iy, dx, dy):
            h = self.perm[(self.perm[ix & 255] + iy) & 255]
            gr = self.grad[h]
            return gr[..., 0] * dx + gr[..., 1] * dy
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        n00, n10 = g(xi, yi, xf, yf), g(xi + 1, yi, xf - 1, yf)
        n01, n11 = g(xi, yi + 1, xf, yf - 1), g(xi + 1, yi + 1, xf - 1, yf - 1)
        return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v   # ~ -0,7..0,7

    def fbm(self, x, y, octaves=5, gain=0.5, lac=2.0):
        s, amp, f, norm = 0.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            s = s + amp * self.perlin(x * f, y * f)
            norm += amp
            amp *= gain
            f *= lac
        return s / norm * 1.4   # ~ -1..1

    def ridged(self, x, y, octaves=6, gain=0.5, lac=2.0, offset=1.0):
        """Ridged multifractal (Musgrave): cada oitava é (offset - |ruído|)², ponderada pela oitava anterior."""
        s, amp, f, weight, norm = 0.0, 1.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            sig = offset - np.abs(self.perlin(x * f, y * f) * 1.4)
            sig = np.clip(sig, 0, 1) ** 2
            sig = sig * weight
            weight = np.clip(sig * 2.0, 0, 1)
            s = s + sig * amp
            norm += amp
            amp *= gain
            f *= lac
        return s / norm   # ~ 0..1


def coords():
    j, i = np.mgrid[0:N, 0:N]
    return i * CELL_KM, j * CELL_KM


# --- Terreno-base e traço -------------------------------------------------------------------------------------------
def base_terrain(seed=3):
    """Uma planície suave a ~300 m com ondulações de 40 m: o interior de um continente."""
    x, y = coords()
    nz = Noise(seed)
    return 300.0 + 40.0 * nz.fbm(x / 120.0, y / 120.0, 4)


def stroke_mask(radius_km=75.0):
    """Peso do pincel ao longo de um traço curvo atravessando a grade: (1 - (d/r)²)² como no jogo."""
    x, y = coords()
    t = np.linspace(0, 1, 80)
    px = 70 + 340 * t
    py = 240 - 170 * t + 70 * np.sin(t * 5.5)
    d = np.full(x.shape, 1e9)
    for a, b in zip(px, py):
        d = np.minimum(d, np.hypot(x - a, y - b))
    r = np.clip(d / radius_km, 0, 1)
    return (1 - r * r) ** 2


# --- Os métodos ---------------------------------------------------------------------------------------------------------
AMP = 3200.0   # altura de referência de uma crista cheia, em metros


def cone(h, m):
    """Elevar liso: soma a máscara. É o pincel básico (o do jogo com rugosidade 0)."""
    return h + AMP * 0.55 * m


def fbm_hills(h, m, seed=11):
    """Elevar com ruído fBm: soma a máscara modulada por ondulação em várias escalas."""
    x, y = coords()
    f = Noise(seed).fbm(x / 70.0, y / 70.0, 5, 0.55)
    return h + AMP * 0.55 * m * np.clip(1.0 + 1.4 * f, 0, 2.4)


def ridges(h, m, seed=11, power=2.2):
    """Montanhas do jogo: ridged multifractal, só soma (vale = sem mudança)."""
    x, y = coords()
    r = Noise(seed).ridged(x / 85.0, y / 85.0, 6, 0.5) ** power
    return h + AMP * 1.15 * m * np.clip(r * 1.5 - 0.1, 0, None)


def ridges_warped(h, m, seed=11, power=2.2, warp_km=70.0):
    """Cristas com deslocamento de domínio (Quilez): lê o ruído numa posição já deslocada por outro ruído."""
    x, y = coords()
    nz = Noise(seed + 100)
    wx = nz.fbm(x / 110.0 + 3.1, y / 110.0, 4) * warp_km
    wy = nz.fbm(x / 110.0, y / 110.0 + 7.7, 4) * warp_km
    r = Noise(seed).ridged((x + wx) / 85.0, (y + wy) / 85.0, 6, 0.5) ** power
    return h + AMP * 1.15 * m * np.clip(r * 1.5 - 0.1, 0, None)


def thermal(h, iters=60, talus_deg=7.0, rate=0.5):
    """Erosão térmica (Musgrave 1989): o que passa do ângulo de repouso escorre para os vizinhos mais baixos."""
    talus = np.tan(np.radians(talus_deg)) * CELL_M
    h = h.copy()
    shifts = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    for _ in range(iters):
        delta = np.zeros_like(h)
        for dy, dx in shifts:
            dist = 1.414 if dx and dy else 1.0
            nb = np.roll(np.roll(h, dy, 0), dx, 1)
            excess = np.clip((h - nb) / dist - talus, 0, None)
            move = rate * excess / 8.0
            delta -= move
            delta += np.roll(np.roll(move, -dy, 0), -dx, 1)
        h += delta
    return h


def droplets(h, m, n_drops=90000, steps=70, batches=9, seed=5):
    """Erosão hidráulica por partículas (Beyer 2015): gotas descem o terreno, pegam sedimento e depositam onde
    desaceleram. Todas as gotas de um lote andam juntas (vetorizado); chove só onde o pincel passou."""
    rng = np.random.default_rng(seed)
    hs = h.copy() / 40.0                        # unidades de simulação: 1 unidade = 40 m
    inertia, cap_f, min_slope, eros, depo, evap, grav = 0.05, 3.0, 0.01, 0.3, 0.3, 0.01, 2.0
    max_step, max_vel = 0.15, 4.0               # teto de erosão por passo (6 m) e de velocidade: sem isso a simulação diverge
    cand = np.argwhere(m > 0.05)
    for _ in range(batches):
        k = n_drops // batches
        pick = cand[rng.integers(0, len(cand), k)]
        y = pick[:, 0] + rng.random(k)
        x = pick[:, 1] + rng.random(k)
        dx = np.zeros(k); dy = np.zeros(k); vel = np.ones(k); water = np.ones(k); sed = np.zeros(k)
        alive = np.ones(k, bool)
        for _s in range(steps):
            xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
            ok = alive & (xi >= 1) & (xi < N - 2) & (yi >= 1) & (yi < N - 2)
            alive = ok
            if not alive.any():
                break
            fx, fy = x - xi, y - yi
            xi, yi = np.clip(xi, 0, N - 2), np.clip(yi, 0, N - 2)
            h00, h10, h01, h11 = hs[yi, xi], hs[yi, xi + 1], hs[yi + 1, xi], hs[yi + 1, xi + 1]
            gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
            gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            hold = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            ln = np.hypot(dx, dy)
            stuck = ln < 1e-9
            dx = np.where(stuck, rng.uniform(-1, 1, k), dx); dy = np.where(stuck, rng.uniform(-1, 1, k), dy)
            ln = np.hypot(dx, dy) + 1e-12
            dx, dy = dx / ln, dy / ln
            nx, ny = x + dx, y + dy
            nxi, nyi = np.floor(nx).astype(int), np.floor(ny).astype(int)
            alive &= (nxi >= 0) & (nxi < N - 1) & (nyi >= 0) & (nyi < N - 1)
            nxi, nyi = np.clip(nxi, 0, N - 2), np.clip(nyi, 0, N - 2)
            nfx, nfy = nx - nxi, ny - nyi
            hnew = (hs[nyi, nxi] * (1 - nfx) * (1 - nfy) + hs[nyi, nxi + 1] * nfx * (1 - nfy)
                    + hs[nyi + 1, nxi] * (1 - nfx) * nfy + hs[nyi + 1, nxi + 1] * nfx * nfy)
            dh = hnew - hold
            cap = np.maximum(-dh, min_slope) * vel * water * cap_f
            deposit_mode = (sed > cap) | (dh > 0)
            amount = np.where(deposit_mode, np.where(dh > 0, np.minimum(dh, sed), (sed - cap) * depo),
                              np.minimum(np.minimum((cap - sed) * eros, -dh), max_step))
            amount = np.where(alive, amount, 0.0)
            sign = np.where(deposit_mode, 1.0, -1.0)
            sed = sed - sign * amount
            for (oy, ox, wgt) in ((0, 0, (1 - fx) * (1 - fy)), (0, 1, fx * (1 - fy)), (1, 0, (1 - fx) * fy), (1, 1, fx * fy)):
                np.add.at(hs, (yi + oy, xi + ox), sign * amount * wgt)
            vel = np.minimum(np.sqrt(np.maximum(vel * vel - dh * grav, 0.0)), max_vel)
            water = water * (1 - evap)
            x, y = nx, ny
    return np.nan_to_num(hs) * 40.0


def _fill_pits(h, eps=0.05, max_iter=300):
    """Enche depressões (sobe cada poço até o menor vizinho + eps) para a água poder sair. Só células internas."""
    h = h.copy()
    for _ in range(max_iter):
        nb = np.minimum.reduce([np.roll(h, s, a) for s in (-1, 1) for a in (0, 1)]
                               + [np.roll(np.roll(h, a, 0), b, 1) for a in (-1, 1) for b in (-1, 1)])
        pit = (h <= nb)
        pit[0, :] = pit[-1, :] = pit[:, 0] = pit[:, -1] = False
        if not pit.any():
            break
        h[pit] = nb[pit] + eps
    return h


def _receivers(h, sea=None):
    """Para cada célula, o vizinho (entre 8) com maior declive descendente; -1 se não houver."""
    idx = np.arange(N * N).reshape(N, N)
    best = np.zeros_like(h)
    rec = np.full((N, N), -1)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nbh = np.roll(np.roll(h, -dy, 0), -dx, 1)
            nbi = np.roll(np.roll(idx, -dy, 0), -dx, 1)
            sl = (h - nbh) / (1.414 if dx and dy else 1.0)
            better = sl > best
            best = np.where(better, sl, best)
            rec = np.where(better, nbi, rec)
    rec[0, :] = rec[-1, :] = rec[:, 0] = rec[:, -1] = -1   # a borda é o nível de base
    if sea is not None:
        rec[h <= sea] = -1                                   # o mar também: a água chega nele e para
    return rec.ravel(), best.ravel()


def stream_power(h, uplift, iters=50, K=0.02, m_exp=0.5, D=0.4, dt=1.0, seed=2, noise_m=15.0, snapshots=(), sea=None):
    """Uplift + erosão fluvial (Cordonnier 2016): a cada passo o terreno sobe pelo mapa de soerguimento e a água
    entalha com a lei de potência de corrente, dh/dt = U - K A^m S. Esquema implícito (Braun & Willett), estável.
    A rede de drenagem em árvore nasce sozinha. D é a difusão de encostas (arredonda os espigões)."""
    rng = np.random.default_rng(seed)
    h = h + rng.normal(0, noise_m, h.shape)
    base = h.copy()
    cell_area = CELL_KM ** 2
    snaps = {}
    for it in range(1, iters + 1):
        h = h + dt * uplift
        hf = _fill_pits(h)
        rec, _ = _receivers(hf, sea)
        order = np.argsort(-hf.ravel())          # do mais alto ao mais baixo
        area = np.full(N * N, cell_area)
        for p in order:                          # captação acumulada
            r = rec[p]
            if r >= 0:
                area[r] += area[p]
        flat = h.ravel().copy()
        coef = dt * K * np.sqrt(area) / CELL_KM  # K A^m / dx
        for p in order[::-1]:                    # do mais baixo ao mais alto: o receptor já está atualizado
            r = rec[p]
            if r < 0:
                continue
            flat[p] = (flat[p] + coef[p] * flat[r]) / (1.0 + coef[p])
        h = flat.reshape(N, N)
        lap = (np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1) - 4 * h)
        lap[0, :] = lap[-1, :] = lap[:, 0] = lap[:, -1] = 0
        h = h + D * lap * dt * 0.2
        h[0, :], h[-1, :], h[:, 0], h[:, -1] = base[0, :], base[-1, :], base[:, 0], base[:, -1]   # a borda fica como era
        if sea is not None:
            h = np.where(base <= sea, np.minimum(h, base), h)   # o mar não sobe nem é entalhado
        if it in snapshots:
            snaps[it] = h.copy()
    return (h, snaps) if snapshots else h


def exemplar_stamp(h, m, exemplar, amp_scale=1.0):
    """Baseado em exemplo: usa um pedaço de relevo REAL (aqui, a cordilheira do mapa do Gleba) como carimbo. O detalhe
    é o do exemplo: ampliado, fica liso (a escala do dado limita a nitidez)."""
    ex = np.clip(exemplar - np.percentile(exemplar, 30), 0, None)   # só a parte montanhosa do exemplo, sem as terras baixas
    from PIL import Image
    big = np.array(Image.fromarray(ex.astype(np.float32)).resize((N, N), Image.BICUBIC))
    return h + m * big * amp_scale


def timed(fn, *a, **k):
    t = time.time()
    out = fn(*a, **k)
    return out, time.time() - t
