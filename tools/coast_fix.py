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
UPSAMPLE = 4  # SIGMA foi calibrado numa grade 4x mais fina que a nativa do Gleba: quem chama aqui reamostra
              # antes (coast_prototype.crop_wrapped, build_natural.coast_patch) e espera essa mesma escala.
STRUCT = np.ones((3, 3), bool)


def signed_dist(land: np.ndarray) -> np.ndarray:
    return ndimage.distance_transform_edt(land) - ndimage.distance_transform_edt(~land)


def regularize(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    return ndimage.gaussian_filter(signed_dist(land), sigma) > 0


def _critical(candidates: np.ndarray, base: np.ndarray, add: bool) -> np.ndarray:
    """De cada trecho conectado de `candidates`, mantém só os que de fato mudam a conectividade de `base`
    (tirando-o de terra, ou pondo-o, conforme `add`): uma península fina pode encolher à vontade, só o istmo
    ou o canal que liga/separa duas massas precisa ficar como está."""
    lbl_c, n_c = ndimage.label(candidates, STRUCT)
    if n_c == 0:
        return candidates
    _, n0 = ndimage.label(base, STRUCT)
    critical = np.zeros_like(candidates)
    for i in range(1, n_c + 1):
        piece = lbl_c == i
        changed = (base | piece) if add else (base & ~piece)
        _, n1 = ndimage.label(changed, STRUCT)
        if n1 != n0:  # mudou o número de componentes: essa peça liga ou separa algo
            critical |= piece
    return critical


def protect_features(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    """Máscara de feições a proteger (istmo, canal ou ilha mais fina que ~sigma): True = não suavizar ali.
    Só entra o que de fato arrisca a conectividade — uma ponta ou baía rasa sem ligação sobra de fora e pode
    suavizar à vontade (é isso que fazia a costa ficar com cara de serra: toda ponta fina ficava protegida,
    lisa só a parte mais aberta)."""
    neck_r = int(round(sigma))
    opened_land = ndimage.binary_dilation(ndimage.binary_erosion(land, STRUCT, iterations=neck_r), STRUCT, iterations=neck_r)
    thin_land = _critical(land & ~opened_land, land, add=False)
    water = ~land
    opened_water = ndimage.binary_dilation(ndimage.binary_erosion(water, STRUCT, iterations=neck_r), STRUCT, iterations=neck_r)
    thin_water = _critical(water & ~opened_water, land, add=True)

    lbl, n = ndimage.label(land, STRUCT)
    sizes = ndimage.sum(np.ones_like(lbl), lbl, index=np.arange(1, n + 1))
    small_islands = np.isin(lbl, np.where(sizes < 8 * neck_r * neck_r)[0] + 1)

    protected = small_islands | thin_land | thin_water
    return ndimage.binary_dilation(protected, STRUCT, iterations=UPSAMPLE)  # margem de ~1 px da fonte


def fix_coast(land: np.ndarray, sigma: float = SIGMA) -> np.ndarray:
    """A costa corrigida: suave onde é seguro, idêntica à fonte onde é frágil. Valide depois com o que
    coast_prototype.validate() faz (fusões e ilhas partidas = 0) antes de confiar no resultado numa área nova."""
    protected = protect_features(land, sigma)
    return np.where(protected, land, regularize(land, sigma))
