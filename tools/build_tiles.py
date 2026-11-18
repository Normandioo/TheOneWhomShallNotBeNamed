"""Pirâmide de blocos de uma imagem equiretangular grande (o relevo de 16K do Gleba).

Nível z tem 2^(z+1) x 2^z blocos de TILE x TILE px (largura 1024·2^z). Com 16384 px de largura são os níveis 0 a 4
(2 + 8 + 32 + 128 + 512 = 682 blocos). Assim o programa carrega só os blocos que a câmera vê, no nível que o zoom
pede, sem ter a imagem inteira na memória (512 MiB em RGBA).

Saída: data/evron/tiles/<nome>/<z>/<y>_<x>.jpg e manifest.json. Rodado por import_maps.py; sozinho:
  python tools/build_tiles.py D:/downloads/mapas.zip
"""
import io
import json
import os
import sys
import zipfile

from PIL import Image

TILE = 512
QUALITY = 90  # JPEG: decodifica rápido no carregamento; a perda não aparece neste relevo de cores chapadas


def build(img: Image.Image, name: str, out_root="data/evron/tiles") -> dict:
    w, h = img.size
    assert w == 2 * h and w % (2 * TILE) == 0, f"precisa ser equiretangular 2:1 e múltipla de {2 * TILE}: {img.size}"
    levels = (w // (2 * TILE)).bit_length()  # 16384 -> 5 níveis (0..4)
    out = os.path.join(out_root, name)
    count = 0
    level_img = img
    for z in reversed(range(levels)):  # do mais detalhado para o menos: cada nível é a metade do anterior
        lw = 2 * TILE * 2 ** z
        if level_img.size[0] != lw:
            level_img = level_img.resize((lw, lw // 2), Image.BOX)
        os.makedirs(os.path.join(out, str(z)), exist_ok=True)
        for y in range(2 ** z):
            for x in range(2 ** (z + 1)):
                tile = level_img.crop((x * TILE, y * TILE, (x + 1) * TILE, (y + 1) * TILE))
                tile.save(os.path.join(out, str(z), f"{y}_{x}.jpg"), quality=QUALITY)
                count += 1
    manifest = {"name": name, "tile": TILE, "levels": levels, "width": w, "height": h, "format": "jpg",
                "projection": "equiretangular, coluna 0 = -180°, linha 0 = 90°N (EvronGeo)"}
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    expected = sum(2 * 4 ** z for z in range(levels))
    assert count == expected, f"esperava {expected} blocos, gerou {count}"
    print(f"{name}: {count} blocos em {levels} níveis ({TILE} px)")
    return manifest


def build_from_zip(zip_path: str) -> None:
    Image.MAX_IMAGE_PIXELS = None  # 16384x8192 passa do limite de segurança do Pillow (imagem nossa, conhecida)
    with zipfile.ZipFile(zip_path) as z:
        img = Image.open(io.BytesIO(z.read("resized/relevo.png"))).convert("RGB")
    build(img, "relevo")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build_from_zip(sys.argv[1])
