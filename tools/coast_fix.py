"""Reconstrução de costa validada (docs/plano_correcao_costas: etapas 1-2, ver tools/coast_prototype.py para o
protótipo e docs/coast_proto/relatorio.md para os números). Usado por build_natural.py (etapa 3: só num recorte,
não no planeta inteiro ainda) e por coast_prototype.py (o protótipo original, que continua funcionando sozinho).

Método: suaviza um campo de distância com sinal (positivo em terra) com um desfoque gaussiano e re-corta em
zero; istmos, canais e ilhas mais finos que o raio do desfoque ficam protegidos (inalterados), identificados por
abertura morfológica antes de suavizar — não por tentativa e erro depois (essa primeira tentativa funde ou parte
feições na própria costura; ver o commit que a introduziu). Sigma = 6,97 px da grade de 4096x2048 (calibrado no
recorte "continental" de coast_prototype.py para ~0,5 px de deslocamento médio da fonte, com essa proteção).
"""
import numpy as np
from scipy import ndimage

SIGMA = 6.972630474562346  # calibrado em coast_prototype.py (alvo 0,5 px da fonte no recorte "continental")
STRUCT = np.ones((3, 3), bool)


def signed_dist(land: np.ndarray) -> np.ndarray:
    return ndimage.distance_transform_edt(land) - ndimage.distance_transform_edt(~land)


def regularize(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    return ndimage.gaussian_filter(signed_dist(land), sigma) > 0


def protect_features(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    """Máscara de feições a proteger (istmo, canal ou ilha mais fina que ~sigma): True = não suavizar ali."""
    neck_r = int(round(sigma))
    opened_land = ndimage.binary_dilation(ndimage.binary_erosion(land, STRUCT, iterations=neck_r), STRUCT, iterations=neck_r)
    thin_land = land & ~opened_land
    water = ~land
    opened_water = ndimage.binary_dilation(ndimage.binary_erosion(water, STRUCT, iterations=neck_r), STRUCT, iterations=neck_r)
    thin_water = water & ~opened_water

    lbl, n = ndimage.label(land, STRUCT)
    sizes = ndimage.sum(np.ones_like(lbl), lbl, index=np.arange(1, n + 1))
    small_islands = np.isin(lbl, np.where(sizes < 8 * neck_r * neck_r)[0] + 1)

    protected = small_islands | thin_land | thin_water
    return ndimage.binary_dilation(protected, STRUCT, iterations=1)


def fix_coast(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    """A costa corrigida: suave onde é seguro, idêntica à fonte onde é frágil. Valide depois com o que
    coast_prototype.validate() faz (fusões e ilhas partidas = 0) antes de confiar no resultado numa área nova."""
    protected = protect_features(land, sigma)
    return np.where(protected, land, regularize(land, sigma))
