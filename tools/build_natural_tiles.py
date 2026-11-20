"""Pirâmide de blocos da cor natural (tools/build_natural.py), para ter mais grão perto da câmera sem mexer na
geografia: o natural.png de 8K cobre o planeta todo de longe; os blocos (TileLayer) cobrem o que está na tela de
perto, com uma oitava a mais de ruído fino (mais detalhe sintetizado, não dado novo: o Gleba não tem mais do que
4096x2048 de verdade).

Saída: data/evron/tiles/natural/ (PNG, preserva o alfa de terra/gelo) e manifest.json. Rodado por import_maps.py;
sozinho, depois de já ter rodado import_maps.py uma vez (precisa dos PNGs do Gleba em data/evron/):
  python tools/build_natural_tiles.py
Leva ~8-10 min e ~6 GB de RAM.
"""
from PIL import Image

import build_natural
import build_tiles


def build() -> None:
    print("satélite 16K para a pirâmide de blocos...")
    out = build_natural.build_tile_source()
    img = Image.fromarray(out, "RGBA")
    build_tiles.build(img, "natural", fmt="png")


if __name__ == "__main__":
    build()
