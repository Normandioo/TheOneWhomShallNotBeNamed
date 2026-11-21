"""Compara limites de suavização em recortes reais. Rodar na raiz com --output PASTA."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage.measure import find_contours

from bathymetry_prototype import LAND, crop, file_hash
from coast_fix import signed_dist
from coast_prototype import MARGIN, SH, coast_density, load_land, pick_crops

SCALE = 8
SAMPLE_STEP = 1 / 32  # em pixels fonte
STRUCTURES = (ndimage.generate_binary_structure(2, 2), ndimage.generate_binary_structure(2, 1))


def components(mask):
    return tuple(ndimage.label(part, conn) for part, conn in zip((mask, ~mask), STRUCTURES))


def preserves_components(original, candidate):
    for (old, before), (new, after) in zip(original, components(candidate)):
        if before != after:
            return False
        shared = (old > 0) & (new > 0)
        pairs = np.unique(old[shared].astype(np.int64) * (after + 1) + new[shared])
        # Identifica cada componente por sobreposição. Contagem igual, por si só, permite troca de identidades.
        if (len(pairs) != before or len(np.unique(pairs // (after + 1))) != before
                or len(np.unique(pairs % (after + 1))) != after):
            return False
    return True


def contour_samples(mask):
    curves = find_contours(mask, 0.5, fully_connected="high")
    if not curves:
        return np.empty((0, 2)), 0.0
    starts = np.concatenate([curve[:-1] for curve in curves]) / SCALE
    vectors = np.concatenate([np.diff(curve, axis=0) for curve in curves]) / SCALE
    lengths = np.linalg.norm(vectors, axis=1)
    count = np.maximum(1, np.ceil(lengths / SAMPLE_STEP).astype(int))
    samples = [curve[-1:] / SCALE for curve in curves]
    for step in range(count.max()):
        active = count > step
        samples.append(starts[active] + vectors[active] * (step / count[active, None]))
    return np.concatenate(samples), float(lengths.sum())


def displacement(original, before_tree, candidate):
    after, length = contour_samples(candidate)
    if not len(after):
        return float("inf"), float("inf"), length
    forward = before_tree.query(after)[0]
    backward = cKDTree(after).query(original)[0]
    # O alvo amostrado superestima a distância à curva. Meia passada cobre o intervalo
    # entre amostras na curva de origem, por continuidade da função distância.
    return float((forward.mean() + backward.mean()) / 2), float(max(forward.max(), backward.max()) + SAMPLE_STEP / 2), length


def smooth(mask, limit, field, labels, samples, tree):
    # Mantém o perímetro do contexto e só altera células próximas da linha original.
    allowed = np.abs(field) <= limit * SCALE
    edge = MARGIN * SCALE // 2
    allowed[:edge] = allowed[-edge:] = False
    allowed[:, :edge] = allowed[:, -edge:] = False
    for fraction in (1, 0.75, 0.5, 0.25):
        sigma = limit * SCALE * fraction
        candidate = np.where(allowed, ndimage.gaussian_filter(field, sigma) > 0, mask)
        if np.array_equal(candidate, mask) or not preserves_components(labels, candidate):
            continue
        mean, upper, length = displacement(samples, tree, candidate)
        if upper <= limit:
            return candidate, mean, upper, length, sigma / SCALE
    return mask, 0.0, 0.0, 0.0, 0.0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    land = load_land()
    bounds = pick_crops(land)
    density = coast_density(land, 180)
    density[SH // 6:5 * SH // 6] = -1
    density[:90 + MARGIN] = -1
    density[SH - 90 - MARGIN:] = -1
    y, x = np.unravel_index(np.argmax(density), density.shape)
    bounds["latitude_alta"] = (y, x, 90)
    manifest = {"version": 1, "landmask_sha256": file_hash(LAND), "subpixels_per_pixel": SCALE, "regions": {}}
    for name, (y, x, half) in bounds.items():
        native = crop(land, y, x, half)
        mask = native.repeat(SCALE, axis=0).repeat(SCALE, axis=1)
        field = signed_dist(mask).astype(np.float32)
        samples, length = contour_samples(mask)
        if not len(samples):
            raise ValueError(f"{name}: recorte sem contorno")
        tree, labels = cKDTree(samples), components(mask)
        pad = MARGIN * SCALE
        core = np.s_[pad:-pad, pad:-pad]
        original = mask[core]
        region = {"center_xy": [int(x), int(y)], "context_px": MARGIN,
                  "components_land_water": [n for _, n in labels], "variants": {}}
        variants = [original]
        for limit in (0.25, 0.5):
            candidate, mean, upper, perimeter, sigma = smooth(mask, limit, field, labels, samples, tree)
            after = candidate[core]
            variants.append(after)
            change = after != original
            region["variants"][str(limit)] = {
                "mean_displacement_px_estimate": mean, "max_displacement_px_upper_bound": upper,
                "sigma_px": sigma, "area_delta_source_cells": float((after.sum() - original.sum()) / SCALE**2),
                "changed_subpixels": int(change.sum()), "perimeter_px_before": length,
                "perimeter_px_after": perimeter if sigma else length,
            }
            diff = np.zeros((*original.shape, 3), np.uint8)
            diff[original & ~after] = (239, 109, 59)
            diff[~original & after] = (56, 181, 227)
            Image.fromarray(diff).save(args.output / f"{name}_diff_{limit}.png")
        panels = np.concatenate(variants, axis=1)
        Image.fromarray(np.where(panels[..., None], (220, 203, 166), (28, 68, 103)).astype(np.uint8)).save(
            args.output / f"{name}.png")
        np.savez_compressed(args.output / f"{name}.npz", original=variants[0], limit025=variants[1], limit05=variants[2])
        manifest["regions"][name] = region
    (args.output / "report.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
