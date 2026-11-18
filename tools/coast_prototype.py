"""Protótipo regional da correção de costa (docs/plano_correcao_costas/Plano_Correcao_Costas_e_Batimetria_Evron.pdf,
etapas 1 e 2 — diagnóstico e protótipo regional). NÃO toca no planeta, no shader nem em natural.png: só lê
data/evron/Landmask.png (intocado) e escreve relatório e imagens em docs/coast_proto/.

Diagnóstico (etapa 1): a costa visual vem do alfa de natural.png, derivado de Landmask.png com um blur de 1-2
células e, nesta branch, um warp próprio (tools/build_natural.py: COAST_WARP_PX) — mas a MÁSCARA usada ali é a
mesma grade quadriculada de 4096x2048 (9,77 km/px, raio de 6.371 km). O degrau é da fonte, não do blur: suavizar
a textura não cria uma costa nova. Este protótipo testa uma reconstrução que de fato muda a forma do contorno,
com deslocamento limitado e validado, antes de decidir se ela entra no pipeline de verdade (build_natural.py).

Método (etapa 2): em vez de extrair, suavizar e re-rasterizar contornos vetoriais (mais fiel ao plano, mas sem
uma biblioteca topológica no projeto), suaviza-se um campo de distância com sinal (positivo em terra, negativo
em água) com um desfoque gaussiano e re-corta-se em zero. Isso quebra o serrilhado sem precisar de uma malha de
polígonos, e o deslocamento do contorno é medido depois (não presumido): por isso os sigmas de cada intensidade
são calibrados no recorte "continental" e reaplicados aos outros. A extração de contorno (marching squares, via
skimage) entra só para desenhar a linha de comparação sobre as imagens, como a seção 17 do plano pede.
Para cada recorte: extrai o contorno original, gera a versão suavizada em duas intensidades (deslocamento médio
alvo de 0,25 e 0,5 pixel da fonte), valida área e conectividade (ilhas, estreitos) e salva capturas comparáveis.

Saída: docs/coast_proto/<recorte>/{original,d025,d05,diff025,diff05}.png + docs/coast_proto/relatorio.md
Rodar: python tools/coast_prototype.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

D = "data/evron"
OUT = "docs/coast_proto"
SW, SH = 4096, 2048
MARGIN = 24  # px de contexto em volta do recorte, descartados ao final (seção 4 do plano)
UPSAMPLE = 4  # 0,25 px da fonte (~2,4 km) é menor que 1 px da própria grade: sem isso, nenhum deslocamento abaixo
              # de 1 px da fonte (9,77 km) é sequer representável numa máscara binária na resolução original.


def load_land() -> np.ndarray:
    return np.array(Image.open(os.path.join(D, "Landmask.png")).convert("RGB"))[..., 0] == 80


def coast_density(land: np.ndarray, win: int) -> np.ndarray:
    """Pixels de costa (terra com vizinho de água) por janela win x win, uma medida por canto de janela."""
    coast = land & (ndimage.binary_erosion(land, border_value=0) == False)
    return ndimage.uniform_filter(coast.astype(np.float32), win, mode="wrap") * win * win


def pick_crops(land: np.ndarray) -> dict:
    """Recortes escolhidos por medida, não à mão: maior densidade de costa (continental com degraus) e maior
    número de componentes pequenos isolados (arquipélago). A emenda de longitude é fixa, por definição."""
    win = 180
    dens = coast_density(land, win)
    # Longe dos polos (faixa de gelo entra como "costa" mas não é o que queremos) e da própria emenda (reservada).
    lat = 90 - (np.arange(SH) + 0.5) * 180 / SH
    far_pole = (np.abs(lat) < 60)[:, None] & np.ones((1, SW), bool)
    away_seam = np.ones((SH, SW), bool)
    away_seam[:, :win] = False
    away_seam[:, -win:] = False
    cont_mask = dens.copy()
    cont_mask[~(far_pole & away_seam)] = -1
    cy, cx = np.unravel_index(np.argmax(cont_mask), cont_mask.shape)

    lbl, n = ndimage.label(land, structure=np.ones((3, 3)))
    sizes = ndimage.sum(np.ones_like(lbl), lbl, index=np.arange(1, n + 1))
    small = np.isin(lbl, np.where((sizes > 3) & (sizes < 400))[0] + 1)
    small_density = ndimage.uniform_filter(small.astype(np.float32), win, mode="wrap") * win * win
    small_density[~away_seam] = -1
    ay, ax = np.unravel_index(np.argmax(small_density), small_density.shape)

    half = win // 2
    return {
        "continental": (cy, cx, half),
        "arquipelago": (ay, ax, half),
        "emenda_longitude": (SH // 2, 0, half),  # centro exatamente na emenda -180/180 (coluna 0)
    }


def crop_wrapped(a: np.ndarray, cy: int, cx: int, half: int) -> np.ndarray:
    """Recorte de (2*half + 2*MARGIN) px em volta de (cy, cx), encapsulando a longitude e grampeando a latitude,
    reamostrado UPSAMPLE x sem inventar informação (cada pixel da fonte vira um bloco UPSAMPLE x UPSAMPLE)."""
    rows = np.clip(np.arange(cy - half - MARGIN, cy + half + MARGIN), 0, SH - 1)
    cols = (cx - half - MARGIN + np.arange(2 * (half + MARGIN))) % SW
    crop = a[rows][:, cols]
    return np.repeat(np.repeat(crop, UPSAMPLE, 0), UPSAMPLE, 1)


def signed_dist(land: np.ndarray) -> np.ndarray:
    return ndimage.distance_transform_edt(land) - ndimage.distance_transform_edt(~land)


def boundary_shift_km(a: np.ndarray, b: np.ndarray, km_px: float) -> tuple:
    """Deslocamento da costa entre duas máscaras: para cada pixel que mudou de lado, a distância até a fronteira
    de `a` mais próxima (|campo de distância com sinal|; um limite inferior do deslocamento real do contorno,
    mas na prática bem próximo dele)."""
    changed = a != b
    if not changed.any():
        return 0.0, 0.0
    dist_to_boundary = np.abs(signed_dist(a))
    vals = dist_to_boundary[changed] * km_px
    return float(vals.mean()), float(vals.max())


def regularize(land: np.ndarray, sigma: float) -> np.ndarray:
    sdf = signed_dist(land)
    smooth = ndimage.gaussian_filter(sdf, sigma)
    return smooth > 0


def validate(before: np.ndarray, after: np.ndarray) -> dict:
    """Área e conectividade: nenhuma ilha deve sumir nem dois continentes se fundir (seção 5 do plano)."""
    lbl0, n0 = ndimage.label(before, structure=np.ones((3, 3)))
    lbl1, n1 = ndimage.label(after, structure=np.ones((3, 3)))
    merges, splits = 0, 0
    for i in range(1, n0 + 1):
        hits = set(np.unique(lbl1[lbl0 == i])) - {0}
        if len(hits) > 1:
            splits += 1
    for j in range(1, n1 + 1):
        hits = set(np.unique(lbl0[lbl1 == j])) - {0}
        if len(hits) > 1:
            merges += 1
    return {
        "area_antes": int(before.sum()), "area_depois": int(after.sum()),
        "componentes_antes": n0, "componentes_depois": n1,
        "ilhas_que_sumiriam": max(0, n0 - n1) if merges else 0,
        "fusoes_de_massa_de_terra": merges, "ilhas_partidas_em_duas": splits,
    }


def overlay_contour(land: np.ndarray, mark_on: np.ndarray) -> None:
    """Desenha o contorno (marching squares) de `land` em vermelho sobre `mark_on` (RGB, in-place)."""
    for c in measure.find_contours(land.astype(np.float32), 0.5):
        ys = np.clip(np.round(c[:, 0]).astype(int), 0, mark_on.shape[0] - 1)
        xs = np.clip(np.round(c[:, 1]).astype(int), 0, mark_on.shape[1] - 1)
        mark_on[ys, xs] = (255, 60, 60)


def save_crop(name: str, land: np.ndarray, title_land: np.ndarray) -> None:
    img = np.where(title_land[..., None], (230, 215, 180), (25, 60, 95)).astype(np.uint8)
    overlay_contour(land, img)
    Image.fromarray(img).resize((img.shape[1] * 2, img.shape[0] * 2), Image.NEAREST).save(
        os.path.join(OUT, name) + ".png")


def run() -> None:
    os.makedirs(OUT, exist_ok=True)
    land_full = load_land()
    crops = pick_crops(land_full)
    # Calibra o sigma no recorte continental: mede o deslocamento médio real e ajusta até bater 0,25 e 0,5 px.
    cal = crop_wrapped(land_full, *crops["continental"])
    km_px = 9.77
    targets = {"d025": 0.25 * km_px, "d05": 0.5 * km_px}
    sigmas = {}
    for key, target_km in targets.items():
        sigma = 1.0
        for _ in range(12):  # busca binária simples no sigma até a média bater o alvo
            after = regularize(cal, sigma)
            mean_km, _ = boundary_shift_km(cal, after, km_px / UPSAMPLE)
            if mean_km < target_km:
                sigma *= 1.3
            else:
                sigma /= 1.15
        sigmas[key] = sigma
    print(f"sigmas calibrados: {sigmas}")

    report = ["# Protótipo de correção de costa\n",
              f"Recortes escolhidos por medida (maior densidade de costa / mais ilhas pequenas), raio 6.371 km, "
              f"9,77 km/px na grade de 4096x2048. Sigmas calibrados no recorte continental: "
              f"d025 = {sigmas['d025']:.2f}, d05 = {sigmas['d05']:.2f}.\n"]
    for name, bounds in crops.items():
        land = crop_wrapped(land_full, *bounds)
        save_crop(f"{name}_original", land, land)
        report.append(f"\n## {name}\n")
        for key, sigma in sigmas.items():
            after = regularize(land, sigma)
            mean_km, max_km = boundary_shift_km(land, after, km_px / UPSAMPLE)
            v = validate(land, after)
            save_crop(f"{name}_{key}", after, land)
            diff = np.zeros((*land.shape, 3), np.uint8)
            diff[land & ~after] = (255, 120, 0)   # virou água
            diff[~land & after] = (0, 160, 255)   # virou terra
            Image.fromarray(diff).resize((diff.shape[1] * 2, diff.shape[0] * 2), Image.NEAREST).save(
                os.path.join(OUT, f"{name}_diff_{key}.png"))
            ok = v["fusoes_de_massa_de_terra"] == 0 and v["ilhas_partidas_em_duas"] == 0
            report.append(f"- **{key}** (alvo {targets[key]/km_px:.2f} px): deslocamento médio {mean_km:.2f} km "
                           f"({mean_km/km_px:.2f} px), máximo {max_km:.2f} km; área terra {v['area_antes']} -> "
                           f"{v['area_depois']} px ({100*(v['area_depois']-v['area_antes'])/max(v['area_antes'],1):+.1f}%); "
                           f"componentes {v['componentes_antes']} -> {v['componentes_depois']}; "
                           f"fusões {v['fusoes_de_massa_de_terra']}, ilhas partidas {v['ilhas_partidas_em_duas']} "
                           f"— {'OK' if ok else 'REJEITAR'}\n")
    with open(os.path.join(OUT, "relatorio.md"), "w", encoding="utf-8") as f:
        f.writelines(report)
    print("".join(report))


if __name__ == "__main__":
    run()
