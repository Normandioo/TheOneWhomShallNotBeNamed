"""Cor natural de Evron (no estilo das imagens de satélite da NASA), montada a partir dos dados do Gleba.

A "Satelite.png" do Gleba tem mar quase preto e manchado e terra num verde só. Aqui a cor sai do que os mapas medem:
  - terra = mistura de chão nu, gramíneas, arbustos e árvores pelas frações de "Vegetação.png";
    o tom das árvores vem do bioma (tropical, temperada, conífera), o da grama da chuva e o do chão nu da temperatura;
  - gelo onde o clima é EF (Köppen) ou o bioma é geleira, e gelo marinho onde o mês mais quente fica abaixo de -2 °C;
  - rios pelo fluxo de "Waterflow.png": os grandes viram água no alfa (curvas lisas no shader), com mata ciliar no seco.
O mar NÃO é pintado aqui: o alfa marca terra e gelo (1) e água aberta (0), e o shader pinta a água pela profundidade
da altitude ao vivo (assim uma edição de terreno muda a cor do mar).

Saída: data/evron/natural.png (RGBA, 4096x2048). Rodado por import_maps.py; sozinho: python tools/build_natural.py
"""
import os

import numpy as np
from PIL import Image

D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "evron")  # de qualquer pasta

VIRIDIS = np.array([(0.267, 0.005, 0.329), (0.279, 0.175, 0.483), (0.230, 0.322, 0.546), (0.173, 0.449, 0.558), (0.128, 0.567, 0.551),
                    (0.158, 0.684, 0.502), (0.369, 0.789, 0.383), (0.678, 0.864, 0.190), (0.993, 0.906, 0.144)])
MAGMA = np.array([(0.001, 0.000, 0.014), (0.113, 0.065, 0.277), (0.317, 0.072, 0.485), (0.513, 0.148, 0.508), (0.716, 0.215, 0.475),
                  (0.904, 0.320, 0.388), (0.987, 0.536, 0.382), (0.997, 0.770, 0.535), (0.987, 0.991, 0.750)])

# Cores de referência (sRGB 0..1), escolhidas pelo aspecto de imagens de satélite em cor real.
TREE_TROPICAL = (0.10, 0.26, 0.08)
TREE_TEMPERATE = (0.17, 0.31, 0.12)
TREE_CONIFER = (0.10, 0.20, 0.12)
SHRUB = (0.42, 0.40, 0.26)
GRASS_WET = (0.36, 0.47, 0.20)
GRASS_DRY = (0.66, 0.60, 0.38)
BARE_HOT = (0.84, 0.72, 0.52)
BARE_MILD = (0.62, 0.55, 0.43)
BARE_COLD = (0.50, 0.48, 0.45)
ICE = (0.93, 0.95, 0.98)
RIVER = (0.09, 0.22, 0.32)
RIPARIAN = (0.22, 0.38, 0.15)  # mata ciliar: o verde que acompanha o rio no seco (o Nilo visto do espaço)


def load(name):
    return np.array(Image.open(os.path.join(D, name)).convert("RGB"))


def ramp_t(rgb, stops):
    """Posição 0..1 de cada cor numa escala de cores (9 pontos interpolados para 256), pela cor mais próxima."""
    x = np.linspace(0, 1, 256)
    lut = np.stack([np.interp(x, np.linspace(0, 1, 9), stops[:, c]) for c in range(3)], 1) * 255
    u, inv = np.unique(rgb.reshape(-1, 3), axis=0, return_inverse=True)
    t = ((u[:, None, :].astype(np.float32) - lut[None]) ** 2).sum(-1).argmin(1) / 255.0
    return t[inv.ravel()].reshape(rgb.shape[:2])


def blur(a, r):
    """Média móvel 2x (quase gaussiana) de raio r; a longitude dá a volta, a latitude não."""
    a = a.astype(np.float32)
    for _ in range(2):
        a = sum(np.roll(a, k, 1) for k in range(-r, r + 1)) / (2 * r + 1)
        p = np.pad(a, ((r, r), (0, 0)) + ((0, 0),) * (a.ndim - 2), mode="edge")
        a = sum(p[r + k: r + k + a.shape[0]] for k in range(-r, r + 1)) / (2 * r + 1)
    return a


def mix(w, col):
    return w[..., None] * np.array(col, np.float32)


def is_color(rgb, col):
    return (rgb == col).all(-1)


def build():
    land = load("Landmask.png")[..., 0] == 80
    veg = load("Vegetação.png").astype(np.float32) / 255.0
    biome = load("BiomasGleba.png")
    koppen = load("Clima.png")
    t_jan = -20 + 60 * ramp_t(load("Temperatura Janeiro.png"), MAGMA)
    t_jul = -20 + 60 * ramp_t(load("Temperatura Julho.png"), MAGMA)
    rain = 20 + 298 * ramp_t(load("Average Rainfall.png"), VIRIDIS)  # mm/mês (faixa escura vira ~20: só seco)

    # Frações de vegetação: R arbustos, G gramíneas, B árvores; o resto é chão nu. Suavizadas: o Gleba é em hexágonos.
    shrub, grass, trees = (blur(veg[..., c], 1) for c in range(3))
    total = shrub + grass + trees
    k = np.where(total > 1.0, 1.0 / np.maximum(total, 1e-6), 1.0)
    shrub, grass, trees = shrub * k, grass * k, trees * k
    bare = 1.0 - shrub - grass - trees

    # Tons que dependem do lugar, suavizados para não mostrar as bordas das células.
    conifer = blur(is_color(biome, (44, 160, 90)) | is_color(biome, (0, 85, 0)), 4)
    tropical = blur(is_color(biome, (212, 170, 0)) | is_color(biome, (68, 120, 33)), 4)
    temperate = np.clip(1.0 - conifer - tropical, 0, 1)
    tree_col = mix(conifer, TREE_CONIFER) + mix(tropical, TREE_TROPICAL) + mix(temperate, TREE_TEMPERATE)
    wet = blur(np.clip((rain - 30) / 90, 0, 1), 2)
    grass_col = mix(wet, GRASS_WET) + mix(1 - wet, GRASS_DRY)
    t_mean = blur((t_jan + t_jul) / 2, 2)
    hot = np.clip((t_mean - 12) / 12, 0, 1)
    cold = np.clip((8 - t_mean) / 12, 0, 1)
    bare_col = mix(hot, BARE_HOT) + mix(cold, BARE_COLD) + mix(np.clip(1 - hot - cold, 0, 1), BARE_MILD)

    rgb = trees[..., None] * tree_col + shrub[..., None] * np.array(SHRUB) \
        + grass[..., None] * grass_col + bare[..., None] * bare_col

    # Encostas íngremes mostram rocha; sem isso a terra fica lisa como pintura. Declividade da altitude calibrada
    # (pixel de ~12,7 km achata as encostas: 3° já é íngreme nesta escala).
    rng = np.random.default_rng(7)  # semente fixa: a importação dá sempre a mesma imagem
    # O mar conta como 0 m: senão o degrau da costa até o fundo vira "encosta" e toda costa ganha uma borda de rocha.
    h = np.maximum(np.fromfile(os.path.join(D, "height_4096x2048.f32"), "<f4").reshape(2048, 4096), 0).astype(np.float32)
    lat = np.deg2rad(90 - (np.arange(2048) + 0.5) * 180 / 2048)[:, None]
    dy = 8282.3e3 * np.pi / 2048
    dx = np.maximum(np.cos(lat), 0.05) * dy * 2
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * dx)
    gy = (np.pad(h, ((1, 1), (0, 0)), mode="edge")[2:] - np.pad(h, ((1, 1), (0, 0)), mode="edge")[:-2]) / (2 * dy)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    rock = np.clip((slope - 1.0) / 3.0, 0, 0.8) * land
    rgb = rgb * (1 - rock[..., None]) + mix(rock, BARE_COLD)
    # Variação leve de brilho (±3%, manchas de ~5 px), para a terra não parecer pintada a pincel largo.
    grain = blur(rng.standard_normal(h.shape), 2)
    rgb *= 1 + 0.03 * (grain / grain.std())[..., None]

    # Rios pelo fluxo de água do Gleba (viridis, já em escala que realça a rede): os grandes nítidos, os afluentes
    # mais fracos. Os vales (fluxo médio) escurecem um pouco, e no seco o rio leva uma faixa verde.
    flow = ramp_t(load("Waterflow.png"), VIRIDIS) * land
    river = np.clip((flow - 0.68) / 0.20, 0, 1) ** 1.5  # t > 0,68 ≈ 4% da terra; > 0,88 ≈ 1% (rio cheio)
    rgb *= 1 - 0.10 * np.clip((flow - 0.35) / 0.35, 0, 1)[..., None]
    riparian = np.clip(blur(river, 3) * 4, 0, 1) * (1 - wet) * 0.7
    rgb = rgb * (1 - riparian[..., None]) + mix(riparian, RIPARIAN)
    # Afluentes fracos ficam só como um tom mais escuro; os rios grandes viram água no alfa (mais abaixo).
    rgb = rgb * (1 - 0.5 * river[..., None]) + mix(0.5 * river, RIVER)

    # Gelo: calota (EF) e geleiras em terra; gelo marinho onde nem o mês mais quente passa de -2 °C, com a borda
    # quebrada por ruído largo (o mapa de temperatura do Gleba é quase uma faixa reta perto dos polos).
    land_ice_mask = (is_color(koppen, (104, 104, 104)) | is_color(biome, (236, 236, 236))) & land
    wobble = blur(rng.standard_normal(h.shape), 12)
    wobble = 1.5 * wobble / wobble.std()  # ±1,5 °C: mais que isso espalha blocos de gelo até latitudes médias
    sea_ice_mask = (np.maximum(t_jan, t_jul) + wobble < -2) & ~land
    # Uma máscara só, suavizada junto: borrar terra e mar separados deixa ~50% de gelo na junta (uma linha).
    ice = np.clip(blur(land_ice_mask | sea_ice_mask, 2), 0, 1)
    rgb = rgb * (1 - ice[..., None]) + mix(ice, ICE)

    # A água leva a cor da terra vizinha: a mistura do alfa na costa não pode trazer a cor de "chão nu" da água.
    solid = (land | sea_ice_mask).astype(np.float32)
    near = blur(rgb * solid[..., None], 2) / np.maximum(blur(solid, 2), 1e-6)[..., None]
    rgb = np.where(solid[..., None] > 0, rgb, near)

    # Alfa: superfície sólida (terra ou gelo) = 1, água aberta = 0. Suavizado junto (uma máscara só), senão a junta
    # entre terra e gelo marinho fica meio transparente e aparece como linha.
    # Os rios grandes entram como água: o shader corta o alfa em 0,5 com suavização, e a linha borrada de 1 pixel
    # vira um rio de curvas lisas (em vez de degraus de 12,7 km), mais largo onde o fluxo é maior.
    river_water = np.clip(blur(river, 1) * 1.6, 0, 1) * (1 - ice)
    alpha = np.clip(blur(land | sea_ice_mask, 1), 0, 1) * (1 - river_water)
    out = np.dstack([np.clip(rgb, 0, 1), alpha]) * 255
    Image.fromarray(out.round().astype(np.uint8), "RGBA").save(os.path.join(D, "natural.png"))

    # Autoteste: deserto claro e quente, floresta tropical escura e verde, calota polar branca, mar aberto transparente.
    desert = is_color(biome, (255, 246, 213)) & land & (t_mean > 15)
    jungle = is_color(biome, (68, 120, 33))
    assert rgb[desert].mean() > rgb[jungle].mean() + 0.2, "deserto deveria ser bem mais claro que a floresta tropical"
    assert (rgb[jungle][:, 1] > rgb[jungle][:, 0]).mean() > 0.95, "floresta tropical deveria ser verde"
    assert ice[:20].mean() > 0.8 and ice[-20:].mean() > 0.8, "os polos deveriam estar cobertos de gelo"
    open_sea = ~land & (blur(sea_ice_mask, 2) < 0.01)
    assert alpha[open_sea].mean() < 0.05, "o mar aberto deveria ser transparente"
    print(f"natural.png: gelo {ice.mean():.1%} do planeta, mar aberto {open_sea.mean():.1%}")


if __name__ == "__main__":
    build()
