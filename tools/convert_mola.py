"""Converte o relevo MOLA (NASA PDS, megt90n000cb.img) para o formato do jogo.

Entrada: 1440x720 inteiros 16 bits big-endian, metros, longitude 0..360 leste a partir da borda esquerda.
Saída:   data/mars_height_1440x720.rh = float16 little-endian (Image.FORMAT_RH do Godot), metros,
         longitude -180..180 (convenção do projeto: u = lon/360 + 0.5).

Rodar a partir da raiz do projeto: python tools/convert_mola.py
"""
import array
import struct
import sys

W, H = 1440, 720
src = array.array("h")
with open("data/mola/megt90n000cb.img", "rb") as f:
    src.fromfile(f, W * H)
if sys.byteorder == "little":
    src.byteswap()

# Desloca meia volta: a coluna 0 da saída é a longitude -180 (= 180 leste).
out = [src[y * W + (x + W // 2) % W] for y in range(H) for x in range(W)]
with open("data/mars_height_1440x720.rh", "wb") as f:
    f.write(struct.pack(f"<{W * H}e", *out))

# Autoteste: Olympus Mons (18.65N, 133.8W) é o ponto mais alto; Hellas (~42S, 70E) é bem fundo.
def at(lat, lon):
    x = int((lon / 360 + 0.5) * W) % W
    y = min(H - 1, int((0.5 - lat / 180) * H))
    return out[y * W + x]

print(f"min {min(out)} m, max {max(out)} m, Olympus {at(18.65, -133.8)} m, Hellas {at(-42, 70)} m")
assert at(18.65, -133.8) > 18000, "Olympus Mons deveria passar de 18 km"
assert at(-42, 70) < -6000, "Hellas deveria estar abaixo de -6 km"
