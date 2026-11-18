"""Temperatura de janeiro e de julho em °C (float32), a partir das imagens do Gleba.

A interpolação sazonal precisa de valores, não de cores: misturar as cores da legenda cria valores sem sentido.
Cada pixel é convertido pela escala magma com a calibração do projeto (T = -20 + 60 t, docs/calibracao): t é a posição da
cor mais próxima numa escala de 256 passos, então a resolução é de 60/255 = 0,24 °C e o resíduo da calibração é de 0,5 °C.
t = 0 significa "-20 °C ou menos" (a escala satura): o valor gravado é -20,0 e a leitura mostra "≤ −20 °C".
Um pixel cuja cor está longe da escala (não é do mapa) vira NaN = sem dado; o relatório mostra quantos são.

Saída: data/evron/temperature_{jan,jul}_4096x2048.f32 (RF, linha a linha, mesma grade da altitude).
Rodado por import_maps.py; sozinho (da raiz do projeto): python tools/build_temperature.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import build_natural as bn  # noqa: E402

OFF_RAMP = 40.0  # distância de cor (0..255 por canal, euclidiana) acima da qual o pixel não é da escala
FILES = {"jan": "Temperatura Janeiro.png", "jul": "Temperatura Julho.png"}


def to_celsius(rgb):
    x = np.linspace(0, 1, 256)
    lut = np.stack([np.interp(x, np.linspace(0, 1, 9), bn.MAGMA[:, c]) for c in range(3)], 1) * 255
    u, inv = np.unique(rgb.reshape(-1, 3), axis=0, return_inverse=True)
    d2 = ((u[:, None, :].astype(np.float32) - lut[None]) ** 2).sum(-1)
    t = d2.argmin(1) / 255.0
    celsius = np.where(np.sqrt(d2.min(1)) > OFF_RAMP, np.nan, -20.0 + 60.0 * t).astype(np.float32)
    return celsius[inv.ravel()].reshape(rgb.shape[:2])


def build():
    for key, name in FILES.items():
        c = to_celsius(bn.load(name))
        out = os.path.join(bn.D, f"temperature_{key}_{c.shape[1]}x{c.shape[0]}.f32")
        c.tofile(out)
        ok = c[~np.isnan(c)]
        print(f"{out}: {ok.min():.1f} a {ok.max():.1f} °C, {(c <= -20.0).mean() * 100:.1f}% saturado em -20, "
              f"{np.isnan(c).mean() * 100:.2f}% sem dado")


if __name__ == "__main__":
    build()
