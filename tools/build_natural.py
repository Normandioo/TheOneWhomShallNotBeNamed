"""Cor natural de Evron em 8K (estilo das composições de satélite da NASA), montada a partir dos dados do Gleba.

Cada pixel de saída (8192x4096, 6,35 km no equador) sai do que os mapas medem, não de uma pintura:
  - vegetação: frações de "Vegetação.png" (arbustos, gramíneas, árvores); o tom das árvores vem do bioma
    (tropical úmida/seca, temperada, conífera, mediterrânea, montana), o das gramíneas da chuva, da estação seca,
    da umidade e da tundra;
  - chão nu: a cor do solo pela textura (areia, silte, argila), escurecida pela riqueza (matéria orgânica) onde chove
    e avermelhada nos desertos quentes; a rocha ("Bedrock.png", real_color do Gleba, dessaturada) aparece onde a
    encosta é íngreme, o solo é raso ou a orogenia é forte; derrames vulcânicos ativos escurecem;
  - salinas: fundo das bacias endorreicas secas e afloramentos de halita;
  - gelo: calota (Köppen EF) e geleiras; neve permanente onde nem o mês mais quente passa de ~1 °C; gelo marinho
    pela temperatura, com a borda quebrada em placas;
  - vales pelo fluxo de "Waterflow.png" (as linhas do Gleba têm a largura de um vale, 12,7 km; a água do rio, com
    largura em metros, é desenhada pelo shader a partir de tools/build_rivers.py) e lagos por "Waterbodies.png"
    (salgados nas bacias secas).
Os mapas são de células de 12,7 km (hexágonos do Gleba). Para a imagem não mostrar as células, os limites
interiores (biomas, solos, rochas) são amostrados com um deslocamento suave por ruído (domain warp) e afinados por
ruído fractal em várias escalas. A costa, os rios e os lagos NÃO são deslocados: a geografia de Evron fica igual.
O ruído é uma função da posição 3D na esfera (sem emenda na longitude 180° nem estiramento nos polos) com semente
fixa: a importação dá sempre a mesma imagem.

O mar NÃO é pintado aqui: o alfa marca terra e gelo (1) e água aberta (0), e o shader pinta a água pela
profundidade da altitude ao vivo (assim uma edição de terreno muda a cor do mar). Nos lagos o RGB guarda a
cor da água (doce ou salgada), para o shader poder usá-la.

Saída: data/evron/natural.png (RGBA, 8192x4096). Rodado por import_maps.py; sozinho: python tools/build_natural.py
Leva ~2 min e ~4 GB de RAM.
"""
import os

import numpy as np
from PIL import Image

D = "data/evron"
SW, SH = 4096, 2048     # grade dos mapas do Gleba
W, H = 8192, 4096       # saída
BAND = 128              # linhas de saída por vez: limita a memória (~1 GB por faixa)
SEED = 20261117
WARP_PX = 2.0           # deslocamento máximo dos limites interiores, em pixels do Gleba (~25 km)

VIRIDIS = np.array([(0.267, 0.005, 0.329), (0.279, 0.175, 0.483), (0.230, 0.322, 0.546), (0.173, 0.449, 0.558), (0.128, 0.567, 0.551),
                    (0.158, 0.684, 0.502), (0.369, 0.789, 0.383), (0.678, 0.864, 0.190), (0.993, 0.906, 0.144)])
MAGMA = np.array([(0.001, 0.000, 0.014), (0.113, 0.065, 0.277), (0.317, 0.072, 0.485), (0.513, 0.148, 0.508), (0.716, 0.215, 0.475),
                  (0.904, 0.320, 0.388), (0.987, 0.536, 0.382), (0.997, 0.770, 0.535), (0.987, 0.991, 0.750)])

# Cores de referência (sRGB 0..1), pelo aspecto de imagens de satélite em cor real (Blue Marble).
TREE = {  # dossel por bioma
    "wet_jungle": (0.07, 0.20, 0.06), "dry_jungle": (0.19, 0.27, 0.09), "temperate": (0.14, 0.27, 0.09),
    "conifer": (0.07, 0.14, 0.08), "mediterranean": (0.24, 0.28, 0.14), "montane": (0.15, 0.23, 0.11),
}
DRY_CANOPY = (0.30, 0.31, 0.15)  # floresta seca na estação sem chuva (folhas caídas)
SHRUB_WET, SHRUB_DRY = (0.26, 0.32, 0.16), (0.46, 0.41, 0.28)
GRASS_WET, GRASS_DRY = (0.30, 0.42, 0.15), (0.67, 0.60, 0.38)
GRASS_TUNDRA = (0.43, 0.42, 0.31)
SAND, SILT, CLAY = (0.86, 0.75, 0.55), (0.67, 0.59, 0.47), (0.58, 0.40, 0.28)
LAVA = (0.12, 0.11, 0.11)
SALT = (0.90, 0.88, 0.83)
SNOW = (0.93, 0.95, 0.98)
PACK_ICE = (0.86, 0.89, 0.93)
RIPARIAN = (0.20, 0.34, 0.12)  # mata ciliar: o verde que acompanha o rio no seco (o Nilo visto do espaço)
LAKE_FRESH, LAKE_SALT = (0.07, 0.19, 0.25), (0.33, 0.52, 0.50)

# Rochas do Gleba: cor no mapa "Bedrock.png" -> real_color (paletas do Gleba 0.3.5, common/mods/*/data).
# Conglomerado e brecha não têm real_color no Gleba: tons de cascalho escolhidos aqui.
ROCKS = {
    (200, 190, 15): (240, 224, 192), (190, 155, 165): (175, 155, 135), (180, 124, 135): (150, 130, 120),
    (166, 131, 17): (240, 208, 192), (163, 78, 30): (128, 96, 64), (160, 40, 46): (160, 128, 64),
    (239, 228, 176): (160, 160, 145), (195, 220, 195): (230, 230, 210), (82, 242, 77): (220, 210, 230),
    (34, 177, 76): (230, 210, 210), (30, 147, 56): (210, 210, 215), (255, 235, 235): (200, 200, 200),
    (190, 100, 220): (150, 140, 125), (170, 80, 200): (150, 140, 145), (150, 60, 180): (150, 150, 180),
    (130, 40, 160): (70, 60, 80), (110, 20, 140): (100, 220, 110), (15, 21, 239): (135, 140, 200),
    (13, 20, 211): (124, 130, 150), (11, 19, 190): (40, 40, 50), (10, 18, 165): (30, 30, 40),
    (6, 15, 140): (200, 200, 170), (200, 200, 250): (240, 230, 200), (250, 200, 200): (230, 220, 200),
    (40, 145, 145): (180, 210, 170), (20, 223, 200): (160, 190, 155), (56, 56, 56): (100, 110, 100),
    (85, 85, 85): (140, 140, 165), (100, 100, 100): (180, 180, 200), (120, 120, 120): (96, 112, 96),
    (143, 143, 143): (76, 92, 76), (0, 50, 100): (76, 72, 120), (0, 50, 50): (206, 142, 120),
    (0, 100, 0): (75, 150, 100), (0, 50, 0): (140, 200, 125), (0, 75, 0): (70, 140, 90), (0, 25, 0): (70, 80, 110),
}
HALITE = (255, 235, 235)
GROUPS = ["wet_jungle", "dry_jungle", "temperate", "conifer", "mediterranean", "montane",
          "tundra", "desert", "savanna", "steppe", "glacier"]
BIOMES = {  # cor em "BiomasGleba.png" -> grupo de tom do dossel ou de cobertura
    (68, 120, 33): "wet_jungle", (212, 170, 0): "dry_jungle", (113, 200, 55): "temperate",
    (0, 85, 0): "conifer", (44, 160, 90): "conifer", (200, 113, 55): "mediterranean", (198, 175, 233): "montane",
    (135, 222, 205): "tundra", (255, 246, 213): "desert", (255, 221, 85): "savanna", (205, 222, 135): "steppe",
    (236, 236, 236): "glacier",
}
VOLCANO_ACTIVE = [(0, 250, 50), (255, 255, 255), (250, 0, 0), (250, 150, 0)]  # Vulcanismo.png (calibração: hipótese)
LIP = (153, 102, 153)  # Províncias geológicas: grande província ígnea (derrames de basalto)


# --- leitura -------------------------------------------------------------------------------------------------------

def load(name):
    return np.array(Image.open(os.path.join(D, name)).convert("RGB"))


def ramp_t(rgb, stops):
    """Posição 0..1 de cada cor numa escala de cores (9 pontos interpolados para 256), pela cor mais próxima."""
    x = np.linspace(0, 1, 256)
    lut = np.stack([np.interp(x, np.linspace(0, 1, 9), stops[:, c]) for c in range(3)], 1) * 255
    u, inv = np.unique(rgb.reshape(-1, 3), axis=0, return_inverse=True)
    t = ((u[:, None, :].astype(np.float32) - lut[None]) ** 2).sum(-1).argmin(1) / 255.0
    return t[inv.ravel()].reshape(rgb.shape[:2]).astype(np.float32)


def is_color(rgb, col):
    return (rgb == col).all(-1)


def lookup(rgb, table, default):
    """Troca cada cor de `rgb` pelo valor de `table` (cor -> tupla); cores fora da tabela recebem `default`."""
    key = (rgb[..., 0].astype(np.int32) << 16) | (rgb[..., 1].astype(np.int32) << 8) | rgb[..., 2]
    u, inv = np.unique(key, return_inverse=True)
    vals = np.array([table.get((k >> 16, (k >> 8) & 255, k & 255), default) for k in u.tolist()], np.float32)
    return vals[inv.ravel()].reshape(rgb.shape[:2] + vals.shape[1:])


# --- filtros (longitude dá a volta, latitude não) -------------------------------------------------------------------

def blur(a, r):
    """Média móvel 2x (quase gaussiana) de raio r."""
    a = a.astype(np.float32)
    for _ in range(2):
        a = sum(np.roll(a, k, 1) for k in range(-r, r + 1)) / (2 * r + 1)
        p = np.pad(a, ((r, r), (0, 0)) + ((0, 0),) * (a.ndim - 2), mode="edge")
        a = sum(p[r + k: r + k + a.shape[0]] for k in range(-r, r + 1)) / (2 * r + 1)
    return a


def fill(a, mask):
    """Estende `a` (válido só onde mask) para fora da máscara, por pirâmide de médias ponderadas (push-pull).
    Os dados da terra entram no mar: a amostragem bilinear e o deslocamento na costa não trazem valores do mar."""
    w = mask.astype(np.float32)
    wa = a * (w[..., None] if a.ndim == 3 else w)
    levels = []
    while min(w.shape[:2]) > 4:
        levels.append((wa, w))
        wa = (wa[0::2, 0::2] + wa[1::2, 0::2] + wa[0::2, 1::2] + wa[1::2, 1::2]) / 4
        w = (w[0::2, 0::2] + w[1::2, 0::2] + w[0::2, 1::2] + w[1::2, 1::2]) / 4
    res = wa / np.maximum(w, 1e-6)[(...,) + (None,) * (a.ndim - 2)]
    for la, lw in reversed(levels):
        up = res.repeat(2, 0).repeat(2, 1)
        k = lw[(...,) + (None,) * (a.ndim - 2)]
        res = np.where(k > 0, la / np.maximum(k, 1e-6), 0) * np.minimum(k * 4, 1) + up * (1 - np.minimum(k * 4, 1))
    return res.astype(np.float32)


def sample(F, sx, sy):
    """Bilinear de F (h, w, C) nas coordenadas de pixel (sx, sy) (centro do pixel 0 = 0,0)."""
    h, w = F.shape[:2]
    x0 = np.floor(sx).astype(np.int32)
    y0 = np.floor(sy).astype(np.int32)
    fx = (sx - x0).astype(np.float32)[..., None]
    fy = (sy - y0).astype(np.float32)[..., None]
    x0 %= w
    x1 = (x0 + 1) % w
    y1 = np.clip(y0 + 1, 0, h - 1)
    y0 = np.clip(y0, 0, h - 1)
    return (F[y0, x0] * (1 - fx) + F[y0, x1] * fx) * (1 - fy) + (F[y1, x0] * (1 - fx) + F[y1, x1] * fx) * fy


# --- ruído na esfera -----------------------------------------------------------------------------------------------

def _hash(ix, iy, iz, seed):
    h = (ix * np.uint32(0x8DA6B343)) ^ (iy * np.uint32(0xD8163841)) ^ (iz * np.uint32(0xCB1AB31F)) ^ np.uint32(seed)
    h ^= h >> np.uint32(15)
    h *= np.uint32(0x2C1B3C6D)
    h ^= h >> np.uint32(12)
    h *= np.uint32(0x297A2D39)
    h ^= h >> np.uint32(15)
    return h.astype(np.float32) * np.float32(1 / 4294967295.0)


def vnoise(p, seed):
    """Ruído de valor 3D (-1..1), contínuo, com hash inteiro: estável entre execuções e máquinas."""
    i = np.floor(p)
    f = (p - i).astype(np.float32)
    i = i.astype(np.int64).astype(np.uint32)  # negativos dão a volta em 2^32: o hash continua bem definido
    u = f * f * (3 - 2 * f)
    one = np.uint32(1)
    out = np.zeros(p.shape[:-1], np.float32)
    for dx in (0, 1):
        wx = u[..., 0] if dx else 1 - u[..., 0]
        for dy in (0, 1):
            wy = u[..., 1] if dy else 1 - u[..., 1]
            for dz in (0, 1):
                wz = u[..., 2] if dz else 1 - u[..., 2]
                out += wx * wy * wz * _hash(i[..., 0] + one * dx, i[..., 1] + one * dy, i[..., 2] + one * dz, seed)
    return out * 2 - 1


def fbm(dirs, freq, octaves, seed):
    """Soma fractal (-1..1). freq em ciclos por raio: a célula tem 8.282 km / freq."""
    total, amp, norm = 0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * vnoise(dirs * np.float32(freq * 2 ** o), seed + 101 * o)
        norm += amp
        amp *= 0.5
    return total / norm


def sphere_dirs(rows, w, h):
    """Direções (convenção de EvronGeo) dos centros dos pixels das linhas `rows` de um mapa w x h."""
    lat = np.deg2rad(90 - (rows + 0.5) * 180 / h).astype(np.float32)[:, None]
    lon = np.deg2rad((np.arange(w) + 0.5) * 360 / w - 180).astype(np.float32)[None, :]
    return np.stack(np.broadcast_arrays(np.cos(lat) * np.sin(lon), np.sin(lat), np.cos(lat) * np.cos(lon)), -1)


def noise_grid(w, h, freq, octaves, seed):
    out = np.empty((h, w), np.float32)
    for y in range(0, h, 256):
        out[y:y + 256] = fbm(sphere_dirs(np.arange(y, min(y + 256, h)), w, h), freq, octaves, seed)
    return out


# --- etapa 1: campos na grade do Gleba (4096x2048) ----------------------------------------------------------------

def fields():
    """Tudo o que os mapas dizem, por pixel do Gleba. F = campos da terra (estendidos ao mar), G = geografia fixa."""
    land = load("Landmask.png")[..., 0] == 80
    wb = load("Waterbodies.png")
    lake = ~is_color(wb, (30, 30, 30)) & ~is_color(wb, (80, 80, 80))  # cada lago tem uma cor (identificador)
    biome = load("BiomasGleba.png")
    koppen = load("Clima.png")
    t_jan = -20 + 60 * ramp_t(load("Temperatura Janeiro.png"), MAGMA)
    t_jul = -20 + 60 * ramp_t(load("Temperatura Julho.png"), MAGMA)
    rain = 20 + 298 * ramp_t(load("Average Rainfall.png"), VIRIDIS)  # mm/mês (faixa escura vira ~20: só seco)
    rain_min = 20 + 298 * np.minimum(ramp_t(load("January Rainfall.png"), VIRIDIS), ramp_t(load("July Rainfall.png"), VIRIDIS))
    hum = ramp_t(load("Umidade Média.png"), VIRIDIS)  # 0..1, confiança baixa: entra com peso pequeno

    # Frações de vegetação: R arbustos, G gramíneas, B árvores; o resto é chão nu. Suavizadas: o Gleba é em hexágonos.
    veg = load("Vegetação.png").astype(np.float32) / 255.0
    shrub, grass, trees = (blur(veg[..., c], 1) for c in range(3))
    k = np.minimum(1.0, 1.0 / np.maximum(shrub + grass + trees, 1e-6))
    shrub, grass, trees = shrub * k, grass * k, trees * k

    bw = [blur(sum(is_color(biome, c) for c, g in BIOMES.items() if g == n), 1) for n in GROUPS]

    # Solo: textura (R areia, G silte, B argila), espessura e riqueza (relativas).
    tex = load("Soil Texture.png").astype(np.float32)
    tex /= np.maximum(tex.sum(-1, keepdims=True), 1)
    # Solo e rocha mudam de célula em célula: suavizados mais que a vegetação, senão os hexágonos aparecem no chão nu.
    tex = blur(tex, 2)
    depth = blur(ramp_t(load("Soil Depth.png"), VIRIDIS), 2)
    rich = blur(ramp_t(load("Soil Richness.png"), VIRIDIS), 2)

    # Rocha: real_color dessaturada (a paleta do jogo tem rochas verdes e azuis vivas) e com brilho comprimido para
    # a faixa de albedo de rocha exposta vista do alto.
    bed = load("Bedrock.png")
    rock = lookup(bed, ROCKS, (128, 124, 118)) / 255.0
    lum = (rock @ np.array([0.30, 0.59, 0.11], np.float32))[..., None]
    rock = lum + 0.35 * (rock - lum)
    rock *= (0.16 + 0.46 * lum) / np.maximum(lum, 1e-3)
    rock = blur(rock, 2)
    halite = is_color(bed, HALITE)

    # Declividade da altitude calibrada (pixel de ~12,7 km achata as encostas: 3° já é íngreme nesta escala).
    # O mar conta como 0 m: senão o degrau da costa até o fundo vira "encosta".
    hraw = np.fromfile(os.path.join(D, "height_4096x2048.f32"), "<f4").reshape(SH, SW)
    h = np.maximum(hraw, 0)
    lat = np.deg2rad(90 - (np.arange(SH) + 0.5) * 180 / SH)[:, None]
    dy = 8282.3e3 * np.pi / SH
    dx = np.maximum(np.cos(lat), 0.05) * dy * 2
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * dx)
    hp = np.pad(h, ((1, 1), (0, 0)), mode="edge")
    gy = (hp[2:] - hp[:-2]) / (2 * dy)
    slope = np.degrees(np.arctan(np.hypot(gx, gy))).astype(np.float32)
    orogeny = ramp_t(load("Orogeny Strenght.png"), VIRIDIS)

    volc = blur(sum(is_color(load("Vulcanismo.png"), c) for c in VOLCANO_ACTIVE) > 0, 2) * 3
    lip = blur(is_color(load("Provincias geologicas.png"), LIP), 2)

    # Salinas: o fundo (abaixo da média em volta) das bacias endorreicas secas, e a halita exposta.
    # Bacias endorreicas = os tons de azul-escuro de "Bacias Endorreicas.png" em terra (guia do Gleba).
    endo_rgb = load("Bacias Endorreicas.png").astype(np.int32)
    endo = land & (endo_rgb[..., 2] >= 75) & (endo_rgb[..., 2] > endo_rgb[..., 0] + 20)
    arid = np.clip((35 - rain) / 15, 0, 1)
    low = np.clip((blur(h, 4) - h - 20) / 80, 0, 1)
    playa = np.clip(blur(endo * arid * low, 1) * 2.5 + halite * 0.8, 0, 1)

    land_ice = (is_color(koppen, (104, 104, 104)) | is_color(biome, (236, 236, 236))).astype(np.float32)

    # Rios pelo fluxo de água do Gleba (viridis, já em escala que realça a rede): os grandes nítidos, os afluentes
    # mais fracos. Os vales (fluxo médio) escurecem um pouco.
    flow = ramp_t(load("Waterflow.png"), VIRIDIS) * land
    river = np.clip((flow - 0.68) / 0.20, 0, 1) ** 1.5  # t > 0,68 ≈ 4% da terra; > 0,88 ≈ 1% (rio cheio)
    valley = np.clip((flow - 0.35) / 0.35, 0, 1)
    riparian = np.clip(blur(river, 1) * 3, 0, 1)  # ~15 km de cada lado: a faixa verde do Nilo tem 5 a 20 km

    # Lagos: salgados nas bacias secas (sem saída, a água evapora e o sal fica).
    saline = blur(lake & (blur(arid, 3) > 0.5), 1)

    print("ruído na grade do Gleba...")
    n_low = noise_grid(SW, SH, 28, 4, SEED + 1)     # tons regionais (células de ~300 km)
    n_mid = noise_grid(SW, SH, 160, 3, SEED + 2)    # manchas (~50 km)
    n_mid2 = noise_grid(SW, SH, 160, 3, SEED + 3)
    warp = np.stack([noise_grid(SW, SH, 200, 2, SEED + 4), noise_grid(SW, SH, 200, 2, SEED + 5)], -1)

    landf = [shrub, grass, trees, *bw, tex[..., 0], tex[..., 1], tex[..., 2], depth, rich, *np.moveaxis(rock, -1, 0),
             slope, orogeny, volc, lip, playa, land_ice, valley, riparian]
    F_land = fill(np.stack(landf, -1), land)
    raw = [(t_jan + t_jul) / 2, np.maximum(t_jan, t_jul), rain, rain_min, hum, n_low, n_mid, n_mid2]
    F = np.concatenate([F_land, np.stack(raw, -1).astype(np.float32)], -1)
    keys = ["shrub", "grass", "trees", *GROUPS, "sand", "silt", "clay", "depth", "rich", "rock_r", "rock_g", "rock_b",
            "slope", "orogeny", "volc", "lip", "playa", "land_ice", "valley", "riparian",
            "t_mean", "t_max", "rain", "rain_min", "hum", "n_low", "n_mid", "n_mid2"]
    # Geografia fixa (amostrada sem deslocamento): costa, lagos e rios ficam onde o Gleba pôs.
    G = np.stack([blur(land, 1), blur(lake, 1), saline, blur(river, 1)], -1).astype(np.float32)  # river = vale
    return F, {k: i for i, k in enumerate(keys)}, G, warp


# --- etapa 2: imagem final em 8K, por faixas -----------------------------------------------------------------------

def mix(w, col):
    return w[..., None] * np.array(col, np.float32)


def lerp(a, b, t):
    return a + (b - a) * t[..., None]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def render_band(F, ix, G, warp, y0, y1):
    rows = np.arange(y0, y1)
    dirs = sphere_dirs(rows, W, H)
    sx = np.broadcast_to((np.arange(W) + 0.5) * SW / W - 0.5, (y1 - y0, W)).astype(np.float32)
    sy = np.broadcast_to(((rows + 0.5) * SH / H - 0.5)[:, None], (y1 - y0, W)).astype(np.float32)
    wv = sample(warp, sx, sy) * WARP_PX
    f = sample(F, sx + wv[..., 0], sy + wv[..., 1])
    g = sample(G, sx, sy)
    c = {k: f[..., i] for k, i in ix.items()}
    n_fine = fbm(dirs, 650, 2, SEED + 6)  # ~12 e ~6 km: o grão de um pixel desta imagem
    n_mid, n_low = c["n_mid"], c["n_low"]

    # Biomas: os limites (borrados nas células) viram bordas irregulares; os pesos são renormalizados.
    bw = {k: smooth(0.15, 0.85, c[k] + 0.30 * n_mid + 0.12 * n_fine) for k in GROUPS}
    tot = sum(bw.values())
    bw = {k: v / np.maximum(tot, 1e-6) for k, v in bw.items()}

    # Vegetação com manchas: mais variação onde a cobertura é parcial (savanas, bordas de floresta).
    def patchy(v, n):
        return np.clip(v + n * v * (1 - v) * 2.2, 0, 1)
    trees = patchy(c["trees"], 0.55 * n_mid + 0.30 * n_fine)
    grass = patchy(c["grass"], 0.40 * c["n_mid2"] + 0.25 * n_fine)
    shrub = patchy(c["shrub"], 0.40 * c["n_mid2"] - 0.25 * n_fine)

    # Rocha exposta: encosta íngreme, solo raso, orogenia forte; a vegetação recua onde ela aparece.
    expo = np.clip((c["slope"] - 0.8) / 3.0, 0, 1) * 0.85 + (1 - c["depth"]) ** 2 * 0.35 + c["orogeny"] * 0.15
    expo = np.clip(expo + 0.18 * n_mid + 0.10 * n_fine, 0, 0.95)
    keep = 1 - 0.75 * expo
    trees, grass, shrub = trees * keep, grass * keep, shrub * keep
    s = trees + grass + shrub
    k = np.minimum(1.0, 1.0 / np.maximum(s, 1e-6))
    trees, grass, shrub = trees * k, grass * k, shrub * k
    bare = 1 - trees - grass - shrub

    wet = np.clip(0.8 * np.clip((c["rain"] - 30) / 90, 0, 1) + 0.2 * c["hum"], 0, 1)
    dry_season = np.clip((40 - c["rain_min"]) / 30, 0, 1)
    hot = np.clip((c["t_mean"] - 12) / 12, 0, 1)
    cold = np.clip((4 - c["t_mean"]) / 10, 0, 1)
    arid = np.clip((40 - c["rain"]) / 25, 0, 1)

    tree_col = sum(mix(bw[k], TREE[k]) for k in TREE) + mix(1 - sum(bw[k] for k in TREE), TREE["temperate"])
    deciduous = (bw["dry_jungle"] + 0.6 * bw["savanna"] + 0.4 * bw["mediterranean"]) * dry_season
    tree_col = lerp(tree_col, np.broadcast_to(np.array(DRY_CANOPY, np.float32), tree_col.shape), np.clip(deciduous, 0, 0.35))
    grass_col = lerp(mix(np.ones_like(wet), GRASS_DRY), mix(np.ones_like(wet), GRASS_WET), wet * (1 - 0.3 * dry_season))
    grass_col = lerp(grass_col, mix(np.ones_like(wet), GRASS_TUNDRA), np.clip(bw["tundra"] + cold, 0, 1))
    shrub_col = lerp(mix(np.ones_like(wet), SHRUB_DRY), mix(np.ones_like(wet), SHRUB_WET), wet)

    # Solo nu: textura -> cor; óxido de ferro nos desertos quentes (manchas regionais); matéria orgânica onde chove.
    soil = mix(c["sand"], SAND) + mix(c["silt"], SILT) + mix(c["clay"], CLAY)
    iron = arid * hot * np.clip(0.45 + 0.6 * n_low + 0.2 * n_mid, 0, 1)
    soil *= 1 + iron[..., None] * np.array([0.08, -0.10, -0.22], np.float32)
    soil *= (1 - 0.40 * c["rich"] * wet)[..., None]
    grey = soil.mean(-1, keepdims=True)
    soil = lerp(soil, np.broadcast_to(grey, soil.shape), 0.45 * cold)
    rock = np.stack([c["rock_r"], c["rock_g"], c["rock_b"]], -1)
    rock = lerp(rock, soil, np.full(rock.shape[:2], 0.25, np.float32))  # rocha intemperizada leva um pouco do solo
    rock = lerp(rock, np.broadcast_to(np.array(LAVA, np.float32), rock.shape), np.clip(c["lip"], 0, 1) * 0.35)
    ground = lerp(soil, rock, expo)

    rgb = trees[..., None] * tree_col + shrub[..., None] * shrub_col \
        + grass[..., None] * grass_col + bare[..., None] * ground
    rgb = lerp(rgb, np.broadcast_to(np.array(LAVA, np.float32), rgb.shape), np.clip(c["volc"], 0, 1) * (0.35 + 0.25 * n_mid))
    rgb = lerp(rgb, np.broadcast_to(np.array(SALT, np.float32), rgb.shape),
               np.clip(c["playa"] * (0.75 + 0.35 * n_mid + 0.2 * n_fine), 0, 1))
    # Vales escurecem um pouco; no seco o rio leva uma faixa verde.
    rgb *= (1 - 0.04 * c["valley"])[..., None]
    rgb = lerp(rgb, np.broadcast_to(np.array(RIPARIAN, np.float32), rgb.shape), np.clip(c["riparian"] * (1 - wet) * 0.7, 0, 1))
    # Grão fino e variação regional de brilho: a terra não pode parecer pintada a pincel largo.
    rgb *= (1 + 0.05 * n_fine + 0.035 * n_mid + 0.03 * n_low)[..., None]

    # Gelo: calota e geleiras; neve permanente no alto e no frio (menos nas encostas íngremes, onde ela escorrega).
    perm = np.clip((1.0 - c["t_max"]) / 5 + 0.25 * n_mid + 0.10 * n_fine, 0, 1) * (1 - 0.35 * expo)
    snow = np.clip(np.maximum(smooth(0.2, 0.8, c["land_ice"] + 0.25 * n_mid), perm), 0, 1)
    rgb = lerp(rgb, mix(1 - 0.04 * n_fine, SNOW), snow)

    # Gelo marinho onde nem o mês mais quente passa de -2 °C, em placas: borda larga por ruído médio, rachaduras finas.
    land_a = g[..., 0]
    sea_ice = smooth(-0.12, 0.12, (-2 - c["t_max"]) / 4 + 0.45 * n_low + 0.35 * n_mid + 0.15 * n_fine) * (1 - land_a)
    leads = 1 - 0.18 * np.clip(-n_fine * 2, 0, 1)
    rgb = lerp(rgb, mix(leads, PACK_ICE), sea_ice)

    # Água interior: lagos (doces ou salgados, congelados no frio). O RGB guarda a cor da água.
    lake, saline, valley = g[..., 1], np.clip(g[..., 2] * 1.5, 0, 1), g[..., 3]
    lake_ice = lake * smooth(-1, 1, -c["t_max"])
    water_col = lerp(mix(np.ones_like(lake), LAKE_FRESH), mix(np.ones_like(lake), LAKE_SALT), saline)
    # As linhas de fluxo do Gleba têm a largura de uma célula (12,7 km): são os vales, não o rio. Aqui o vale grande
    # fica só um pouco mais escuro (sombra, umidade); a água do rio, com a largura certa, é desenhada pelo shader a
    # partir de tools/build_rivers.py.
    rgb *= (1 - 0.12 * np.clip(valley * 2, 0, 1) * (1 - snow))[..., None]
    wmask = smooth(0.3, 0.7, lake) * (1 - lake_ice)
    rgb = lerp(rgb, water_col, wmask)

    # Alfa: superfície sólida (terra ou gelo) = 1, água aberta = 0. O shader corta em 0,5 com suavização: a costa
    # borrada de 1 pixel do Gleba vira curva lisa.
    alpha = np.clip(land_a * (1 - lake) + lake_ice + sea_ice, 0, 1)
    return np.dstack([np.clip(rgb, 0, 1), alpha]), snow, sea_ice, bw


def build():
    F, ix, G, warp = fields()
    out = np.empty((H, W, 4), np.uint8)
    stats = {"desert": [], "jungle": [], "ice_top": 0.0, "ice_bottom": 0.0}
    print("imagem 8K...")
    for y in range(0, H, BAND):
        band, snow, sea_ice, bw = render_band(F, ix, G, warp, y, min(y + BAND, H))
        out[y:y + BAND] = np.round(band * 255).astype(np.uint8)
        if y < 40:
            stats["ice_top"] = np.maximum(snow, sea_ice)[: 40 - y].mean()
        if y + BAND > H - 40:
            stats["ice_bottom"] = np.maximum(snow, sea_ice)[-40:].mean()
    Image.fromarray(out, "RGBA").save(os.path.join(D, "natural.png"), compress_level=3)
    check(out, stats)


def check(out, stats):
    """Autoteste: deserto claro e quente, floresta tropical escura e verde, polos de gelo, mar aberto transparente,
    sem emenda na longitude 180° e costa no mesmo lugar do Landmask."""
    assert out.shape == (H, W, 4)
    land = load("Landmask.png")[..., 0] == 80
    biome = load("BiomasGleba.png")
    rgb = out[1::2, 1::2, :3].astype(np.float32) / 255  # um pixel de saída por pixel do Gleba
    alpha = out[1::2, 1::2, 3]
    core = land & (blur(land, 2) > 0.99)  # longe da costa
    desert = is_color(biome, (255, 246, 213)) & core & (rgb.min(-1) < 0.85)  # sem neve
    jungle = is_color(biome, (68, 120, 33)) & core
    assert rgb[desert].mean() > rgb[jungle].mean() + 0.2, "deserto deveria ser bem mais claro que a floresta tropical"
    assert (rgb[jungle][:, 1] > rgb[jungle][:, 0]).mean() > 0.9, "floresta tropical deveria ser verde"
    assert stats["ice_top"] > 0.8 and stats["ice_bottom"] > 0.8, "os polos deveriam estar cobertos de gelo"
    sea = ~land & (blur(~land, 3) > 0.99)
    tropic = np.zeros_like(sea)
    tropic[600:1450] = True
    assert (alpha[sea & tropic] < 13).mean() > 0.99, "o mar aberto dos trópicos deveria ser transparente"
    # Costa = pixels com um vizinho do outro lado; fora dos polos (gelo marinho cobre a costa de propósito).
    near = blur(land, 1)
    coast = (near > 0.05) & (near < 0.95) & tropic
    coast_ok = ((alpha > 127) == land)[coast].mean()
    assert coast_ok > 0.85, f"a costa saiu do lugar ({coast_ok:.0%} dos pixels de costa batem com o Landmask)"
    # Só onde a cor aparece (terra ou gelo dos dois lados); no mar aberto o RGB é só o preenchimento da terra.
    def step(a, b):
        vis = (out[:, a, 3] > 127) & (out[:, b, 3] > 127)
        return np.abs(out[vis, a, :3].astype(int) - out[vis, b, :3].astype(int)).mean()
    seam, inner = step(0, -1), np.mean([step(x, x + 1) for x in range(500, W, 500)])
    assert seam < inner * 2 + 2, f"emenda na longitude 180°: diferença {seam:.1f} (dentro da imagem {inner:.1f})"
    print(f"natural.png 8192x4096: costa {coast_ok:.1%} igual ao Landmask, emenda {seam:.1f} (interior {inner:.1f})")


if __name__ == "__main__":
    build()
