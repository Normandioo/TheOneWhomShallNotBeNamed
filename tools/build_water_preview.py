"""Empacota a prévia da água dos dois ensaios regionais para o Godot."""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coast", type=Path)
    parser.add_argument("bathymetry", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--region", default="continental")
    args = parser.parse_args()
    coast_info = json.loads((args.coast / "report.json").read_text())
    bathy_info = json.loads((args.bathymetry / "report.json").read_text())
    center = coast_info["regions"][args.region]["center_xy"]
    if center != bathy_info["regions"][args.region]["center_xy"]:
        raise ValueError("Os dois recortes precisam ter o mesmo centro.")
    with np.load(args.coast / f"{args.region}.npz") as coast:
        land = coast["limit025"]
    with np.load(args.bathymetry / f"{args.region}.npz") as bathy:
        depth, ocean = -bathy["after"], bathy["ocean"]
    scale = coast_info["subpixels_per_pixel"]
    if land.shape != tuple(size * scale for size in depth.shape) or not ocean.any():
        raise ValueError("As grades dos recortes não são compatíveis ou faltam amostras oceânicas.")

    # Amplia só a superfície de profundidade. O vizinho oceânico mais próximo
    # fornece contexto na borda da máscara, inclusive nas células recém-expostas.
    nearest = ndimage.distance_transform_edt(~ocean, return_distances=False, return_indices=True)
    depth = ndimage.zoom(depth[tuple(nearest)], scale, order=1, grid_mode=True, mode="nearest")
    distance = (ndimage.distance_transform_edt(~land) - ndimage.distance_transform_edt(land)) / scale
    coast_weight = np.exp(-np.maximum(distance, 0) / 1.4)
    h, w = land.shape
    row, col = np.ogrid[:h, :w]
    edge = np.minimum(np.minimum(row, h - 1 - row), np.minimum(col, w - 1 - col))
    fade = np.clip(edge / (12 * scale), 0, 1)
    texture = np.stack((depth, coast_weight, fade, np.ones_like(depth)), axis=-1).astype("<f4")
    if not np.isfinite(texture).all() or (texture[..., 0] < 0).any():
        raise ValueError("A prévia contém uma profundidade inválida.")
    args.output.mkdir(parents=True, exist_ok=True)
    texture.tofile(args.output / "water.rgbaf")
    (args.output / "water.json").write_text(json.dumps({
        "center": center, "size": [w, h], "source_size": [w // scale, h // scale],
    }), encoding="utf-8")


if __name__ == "__main__":
    main()
