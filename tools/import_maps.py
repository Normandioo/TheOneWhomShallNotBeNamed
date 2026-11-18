"""Importa os mapas de Evron (mapas.zip, exportados pelo Gleba) para o formato do projeto.

Saída em data/evron/ (fora do git; o zip original é a fonte e não é alterado):
  - os PNGs da raiz do zip, como estão (camadas de exibição);
  - height_4096x2048.f32 = float32 little-endian (Image.FORMAT_RF do Godot), altitude em metros,
    convertida de "Elevation GrayScale.png" pela calibração de docs/calibracao/calibracao_evron.json;
  - natural.png = cor natural da terra e do gelo, 8192x4096 (tools/build_natural.py, ~5 min);
  - rivers_8192x4096.rgh + rivers_width.png = rios com largura em metros (tools/build_rivers.py, ~1 min);
  - tiles/relevo/ = o relevo de 16K (resized/relevo.png) em pirâmide de blocos (tools/build_tiles.py).
Os .xcf ficam de fora (decisão do autor).

Requer Pillow e numpy:  python -m pip install pillow numpy
Rodar a partir da raiz do projeto:  python tools/import_maps.py D:/downloads/mapas.zip
"""
import os
import sys
import zipfile

import numpy as np
from PIL import Image

import build_natural
import build_rivers
import build_tiles

OUT = "data/evron"
SEA_PIXEL = 32767          # nível do mar (medido: nenhum pixel de terra abaixo disto)
TOP_PIXEL, TOP_M = 50103, 9103.40      # pico de Evron (definido pelo autor)
BOTTOM_M = -13500.0                    # fundo de Evron (definido pelo autor), no pixel 0


def pixel_to_meters(p: np.ndarray) -> np.ndarray:
    """Duas retas: o Gleba normalizou terra e mar separadamente."""
    p = p.astype(np.float64)
    land = (p - SEA_PIXEL) * TOP_M / (TOP_PIXEL - SEA_PIXEL)
    sea = (p - SEA_PIXEL) * -BOTTOM_M / SEA_PIXEL
    return np.where(p >= SEA_PIXEL, land, sea)


def main(zip_path: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    # O Godot não importa nada desta pasta: as imagens são lidas em tempo de execução (ver evron_maps.gd).
    open(os.path.join(OUT, ".gdignore"), "w").close()
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.lower().endswith(".png") and "/" not in n]
        for n in names:
            with open(os.path.join(OUT, n), "wb") as f:
                f.write(z.read(n))
    print(f"{len(names)} PNGs copiados para {OUT}/")

    gray = np.array(Image.open(os.path.join(OUT, "Elevation GrayScale.png")))
    land = np.array(Image.open(os.path.join(OUT, "Landmask.png")).convert("L")) == 80
    assert gray.dtype == np.uint16 and gray.shape == (2048, 4096), f"esperava uint16 4096x2048, veio {gray.dtype} {gray.shape}"
    h = pixel_to_meters(gray)
    # float32: em float16 o passo passa de 4 m acima de 4 km e o fundo cairia em -13.504 m
    h.astype("<f4").tofile(os.path.join(OUT, "height_4096x2048.f32"))

    # Autoteste: os extremos e o nível do mar batem com a calibração, e a terra fica toda acima do mar.
    print(f"altitude: min {h.min():.1f} m, max {h.max():.1f} m, terra abaixo de 0 m: {(h[land] < 0).sum()} px")
    assert abs(h.min() - BOTTOM_M) < 0.5 and abs(h.max() - TOP_M) < 0.5, "extremos fora da calibração"
    assert (h[land] < 0).sum() == 0, "terra abaixo do nível do mar: calibração errada"

    build_natural.build()  # cor natural (usa a altitude recém-gravada)
    build_rivers.build()
    build_tiles.build_from_zip(zip_path)  # relevo de 16K em blocos


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
