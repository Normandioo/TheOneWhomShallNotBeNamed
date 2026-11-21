"""Ensaio regional de batimetria. Executar na raiz: python tools/bathymetry_prototype.py --output PASTA."""
import argparse
import hashlib
import json
from pathlib import Path
from time import perf_counter

import numpy as np
from PIL import Image
from scipy import ndimage

from coast_prototype import MARGIN, SH, SW, coast_density, load_land, pick_crops

DATA = Path("data/evron")
HEIGHT = DATA / "height_4096x2048.f32"
WATER = DATA / "Waterbodies.png"
LAND = DATA / "Landmask.png"
SIGMA = 1.25
MAX_CHANGE_M = 120.0
COAST_GUARD_PX = 2


def crop(source, y, x, half):
    rows = np.clip(np.arange(y - half - MARGIN, y + half + MARGIN), 0, SH - 1)
    cols = np.arange(x - half - MARGIN, x + half + MARGIN) % SW
    return source[np.ix_(rows, cols)]


def reconstruct(height, ocean):
    """Filtra apenas amostras oceânicas, em metros, mantendo a faixa costeira e os extremos locais."""
    support = ndimage.gaussian_filter(ocean.astype(np.float32), SIGMA)
    weighted = ndimage.gaussian_filter(np.where(ocean, height, 0), SIGMA)
    smooth = np.divide(weighted, support, out=height.copy(), where=support > 0)
    window = ndimage.generate_binary_structure(2, 1)
    window[1, 1] = False
    low = ndimage.minimum_filter(np.where(ocean, height, np.inf), footprint=window)
    high = ndimage.maximum_filter(np.where(ocean, height, -np.inf), footprint=window)
    changeable = (ndimage.binary_erosion(ocean, iterations=COAST_GUARD_PX)
                  & (height >= low) & (height <= high))
    # Inclui a própria célula nos limites. Isso preserva o intervalo mesmo em pixels fora do oceano.
    adjusted = np.clip(smooth, np.minimum(low, height), np.maximum(high, height))
    base = height.astype(np.float64)
    adjusted = np.clip(adjusted, base - MAX_CHANGE_M, base + MAX_CHANGE_M).astype(height.dtype)
    rounded_outside = np.abs(adjusted.astype(np.float64) - base) > MAX_CHANGE_M
    adjusted[rounded_outside] = np.nextafter(adjusted[rounded_outside], height[rounded_outside])
    return np.where(changeable, adjusted, height)


def file_hash(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()

def save_comparison(path, before, after, ocean):
    def color(height):
        depth = np.clip(-height / max(1, float(-before[ocean].min())), 0, 1)
        return np.where(ocean[..., None], np.stack((48 - 39 * depth, 145 - 117 * depth,
                                                     184 - 126 * depth), axis=-1), (176, 163, 130))

    change = (after - before) / MAX_CHANGE_M
    difference = np.stack((28 + 227 * np.maximum(change, 0), np.full_like(change, 28),
                           28 + 227 * np.maximum(-change, 0)), axis=-1)
    panels = np.concatenate((color(before), color(after), difference), axis=1).astype(np.uint8)
    image = Image.fromarray(panels)
    image.resize((image.width * 3, image.height * 3), Image.Resampling.NEAREST).save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    started = perf_counter()
    land = load_land()
    with Image.open(WATER) as water:
        if water.size != (SW, SH):
            raise ValueError("Waterbodies.png tem grade diferente da altitude.")
        water_rgb = np.asarray(water.convert("RGB"))
    if land.shape != (SH, SW) or HEIGHT.stat().st_size != SW * SH * 4:
        raise ValueError("Máscara ou altitude fora da grade de referência.")
    height = np.memmap(HEIGHT, dtype="<f4", mode="r", shape=(SH, SW))
    ocean_marker = np.all(water_rgb == 30, axis=-1)
    ocean = ocean_marker & ~land & (height < 0)
    crops = pick_crops(land)
    density = coast_density(land, 180)
    density[SH // 6:5 * SH // 6] = -1
    density[:90 + MARGIN] = -1
    density[SH - 90 - MARGIN:] = -1
    y, x = np.unravel_index(np.argmax(density), density.shape)
    crops["latitude_alta"] = (y, x, 90)
    args.output.mkdir(parents=True, exist_ok=True)
    report = {
        "version": 1,
        "grid": [SW, SH],
        "sigma_px": SIGMA,
        "coast_guard_px": COAST_GUARD_PX,
        "max_change_m": MAX_CHANGE_M,
        "inputs_sha256": {p.name: file_hash(p)
                          for p in (HEIGHT, WATER, LAND)},
        "ocean_marker_on_land": int(np.count_nonzero(ocean_marker & land)),
        "ocean_marker_nonnegative": int(np.count_nonzero(ocean_marker & (height >= 0))),
        "regions": {},
    }
    core = slice(MARGIN, -MARGIN)
    for name, (y, x, half) in crops.items():
        start = perf_counter()
        source = crop(height, y, x, half)
        sea = crop(ocean, y, x, half)
        edited = reconstruct(source, sea)
        coastal = sea[core, core] & ~ndimage.binary_erosion(sea, iterations=COAST_GUARD_PX)[core, core]
        before, after, sea = (data[core, core] for data in (source, edited, sea))
        if not sea.any():
            continue
        # A margem fornece contexto, mas não deve introduzir extremos dentro da área entregue.
        shallow, deep = before[sea].max(), before[sea].min()
        original_extreme = (before == shallow) | (before == deep)
        after = np.where(sea & ~original_extreme, np.clip(after, deep, shallow), before)
        delta = after.astype(np.float64) - before
        np.testing.assert_array_equal(after[coastal], before[coastal])
        np.testing.assert_array_equal(after[~sea], before[~sea])
        np.testing.assert_array_equal(after < 0, before < 0)
        np.testing.assert_array_equal(after[delta == 0], before[delta == 0])
        if float(np.abs(delta).max()) > MAX_CHANGE_M:
            raise ValueError(f"{name}: alteração acima de {MAX_CHANGE_M} m.")
        assert after[sea].min() == before[sea].min() and after[sea].max() == before[sea].max()
        save_comparison(args.output / f"{name}.png", before, after, sea)
        profile_row = np.unravel_index(np.argmax(np.abs(delta)), delta.shape)[0]
        np.savetxt(args.output / f"{name}_perfil.csv",
                   np.column_stack((np.arange(before.shape[1]), before[profile_row], after[profile_row],
                                    sea[profile_row])), delimiter=",", fmt=["%d", "%.6f", "%.6f", "%d"],
                   header="x,original_m,reconstruido_m,oceano", comments="")
        np.savez_compressed(args.output / f"{name}.npz", before=before, after=after, ocean=sea)
        report["regions"][name] = {
            "center_xy": [int(x), int(y)], "size_px": 2 * half,
            "profile_row": int(profile_row),
            "ocean_cells": int(sea.sum()), "changed_cells": int(np.count_nonzero(delta)),
            "max_abs_difference_m": float(np.abs(delta).max()),
            "mean_abs_difference_ocean_m": float(np.abs(delta[sea]).mean()),
            "mean_neighbor_step_x_before_m": float(np.abs(np.diff(before, axis=1))[sea[:, 1:] & sea[:, :-1]].mean()),
            "mean_neighbor_step_x_after_m": float(np.abs(np.diff(after, axis=1))[sea[:, 1:] & sea[:, :-1]].mean()),
            "before_range_m": [float(before[sea].min()), float(before[sea].max())],
            "after_range_m": [float(after[sea].min()), float(after[sea].max())],
            "elapsed_s": round(perf_counter() - start, 3),
        }
    report["elapsed_s"] = round(perf_counter() - started, 3)
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["regions"], indent=2))


if __name__ == "__main__":
    main()
