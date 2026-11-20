"""Variedade de cenários e sementes (resposta ao parecer técnico): roda D, G e I em cinco terrenos-base diferentes e em
três sementes da planície, em paralelo (um processo por execução). Guarda tudo em variedade.npz.
Uso: python variedade.py <pasta_com_numpy_se_precisar>
"""
import os
import sys
from concurrent.futures import ProcessPoolExecutor

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np

import metodos as M

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "variedade.npz")

# nome -> (rótulo para o documento, fator de amplitude do pincel)
CENARIOS = {
    "planicie": ("Planície", 1.0),
    "montanhoso": ("Terreno já montanhoso", 1.0),
    "planalto": ("Planalto (1.800 m)", 1.0),
    "serras_baixas": ("Serras baixas (pincel fraco)", 0.4),
    "costa": ("Montanha costeira", 1.0),
}


def base_de(nome, seed=3):
    x, y = M.coords()
    base = M.base_terrain(seed)
    if nome == "montanhoso":   # cordilheiras antigas por todo o terreno, ~1.200 m
        r = M.Noise(seed + 50).ridged(x / 140.0, y / 140.0, 6, 0.5) ** 2
        return base + 1200.0 * r
    if nome == "planalto":     # 1.800 m de altitude, borda suave
        return base + 1500.0 * np.clip(1.0 - (np.hypot(x - 240, y - 240) / 260.0) ** 4, 0, 1)
    if nome == "serras_baixas":
        r = M.Noise(seed + 60).ridged(x / 90.0, y / 90.0, 5, 0.5) ** 2
        return base + 500.0 * r
    if nome == "costa":        # mar (-300 m) à esquerda, terra à direita, costa sinuosa passando pelo traço
        shore = 150 + 40 * np.sin(y / 55.0)
        t = np.clip((x - shore) / 25.0, -1, 1)
        return np.where(t < 0, -300.0, 300.0) * 1.0 + base - 300.0 + 40 * t
    return base


def executar(args):
    """Uma execução: (cenário, método, semente) -> altura. Roda em processo separado."""
    nome, metodo, seed = args
    _, fator = CENARIOS[nome]
    M.AMP = 3200.0 * fator
    base = base_de(nome, seed)
    m = M.stroke_mask()
    sea = 0.0 if nome == "costa" else None
    land = (base > 0) if nome == "costa" else np.ones_like(base, bool)
    if metodo == "D":
        out = M.ridges_warped(base, m, seed=seed + 10)
    elif metodo == "G":
        out = M.stream_power(base, 130.0 * fator * m * land, 40, 0.08, 0.5, 0.05, 1.0, seed, 40.0, (), sea)
    else:  # I
        semente = base + 0.8 * (M.ridges_warped(base, m, seed=seed + 10) - base)
        out = M.stream_power(semente, 25.0 * fator * m * land, 14, 0.08, 0.5, 0.05, 1.0, seed + 2, 0.0, (), sea)
    return (nome, metodo, seed), out, base, m


if __name__ == "__main__":
    jobs = [(n, k, 3) for n in CENARIOS for k in "DGI"] + [("planicie", k, s) for s in (7, 11) for k in "DGI"]
    res = {}
    with ProcessPoolExecutor(max_workers=max(2, (os.cpu_count() or 4) - 2)) as ex:
        for key, out, base, m in ex.map(executar, jobs):
            res[f"{key[0]}|{key[1]}|{key[2]}"] = out
            res[f"{key[0]}|base|{key[2]}"] = base
            res["mask"] = m
            print(key, f"max {out.max():.0f} m", flush=True)
    np.savez_compressed(CACHE, **res)
    print("salvo", CACHE)
